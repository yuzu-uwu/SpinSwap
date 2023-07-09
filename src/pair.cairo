use core::array::SpanTrait;
use starknet::StorageAccess;
use starknet::StorageBaseAddress;
use starknet::SyscallResult;
use starknet::storage_read_syscall;
use starknet::storage_write_syscall;
use starknet::storage_base_address_from_felt252;
use starknet::storage_address_from_base_and_offset;

use traits::Into;
use traits::TryInto;
use option::OptionTrait;

use serde::Serde;

// Structure to capture time period obervations every 30 minutes, used for local oracles

#[derive(Copy, Drop, Serde)]
struct Observation {
    timestamp: u128,
    reserve_0_cumulative: u256,
    reserve_1_cumulative: u256
}

impl RewardStorageAccess of StorageAccess<Observation> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult::<Observation> {
        let timestamp = StorageAccess::read(address_domain, base)?;

        let reserve_0_cumulative_base = storage_base_address_from_felt252(
            storage_address_from_base_and_offset(base, 1_u8).into()
        );
        let reserve_0_cumulative = StorageAccess::read(address_domain, reserve_0_cumulative_base)?;

        let reserve_1_cumulative_base = storage_base_address_from_felt252(
            storage_address_from_base_and_offset(base, 2_u8).into()
        );
        let reserve_1_cumulative = StorageAccess::read(address_domain, reserve_1_cumulative_base)?;

        Result::Ok(Observation { timestamp, reserve_0_cumulative, reserve_1_cumulative })
    }

    fn write(
        address_domain: u32, base: StorageBaseAddress, value: Observation
    ) -> SyscallResult::<()> {
        StorageAccess::write(address_domain, base, value.timestamp)?;

        let reserve_0_cumulative_base = storage_base_address_from_felt252(
            storage_address_from_base_and_offset(base, 1_u8).into()
        );
        StorageAccess::write(
            address_domain, reserve_0_cumulative_base, value.reserve_0_cumulative
        )?;

        let reserve_1_cumulative_base = storage_base_address_from_felt252(
            storage_address_from_base_and_offset(base, 2_u8).into()
        );
        StorageAccess::write(address_domain, reserve_1_cumulative_base, value.reserve_1_cumulative)
    }
}


#[contract]
mod Pair {
    use hash::LegacyHash;
    use traits::Into;
    use array::ArrayTrait;
    use array::SpanTrait;
    use integer::u256_sqrt;
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use starknet::class_hash::ClassHash;
    use starknet::syscalls::deploy_syscall;
    use openzeppelin::utils::serde::SpanSerde;
    use openzeppelin::security::reentrancyguard::ReentrancyGuard;
    use openzeppelin::token::erc20::interface::{IERC20, IERC20DispatcherTrait, IERC20Dispatcher};
    use openzeppelin::token::erc20::ERC20;
    use spinswap::interfaces::IPairFees::{IPairFeesDispatcherTrait, IPairFeesDispatcher};
    use spinswap::interfaces::IPairFactory::{IPairFactoryDispatcherTrait, IPairFactoryDispatcher};
    use spinswap::interfaces::IPairCallee::{IPairCalleeDispatcherTrait, IPairCalleeDispatcher};
    use spin_lib::utils::{
        get_block_timestamp_u128, get_block_number_u128, and_and, or, u128_to_u256
    };
    use spin_lib::math::{exp_by_squares, Math};
    use super::Observation;

    #[storage]
    struct Storage {
        _stable: bool, // Used to denote stable or volatile pair
        _total_supply: u256,
        _token_0: ContractAddress,
        _token_1: ContractAddress,
        _fees: ContractAddress,
        _factory: ContractAddress,
        _observations: LegacyMap<u256,
        Observation>, // Structure to capture time period obervations every 30 minutes, used for local oracles
        _observation_index: u256,
        _decimals_0: u256,
        _decimals_1: u256,
        _reserve_0: u256,
        _reserve_1: u256,
        _block_timestamp_last: u128,
        _reserve_0_cumulative_last: u256,
        _reserve_1_cumulative_last: u256,
        // index0 and index1 are used to accumulate fees, this is split out from normal trades to keep the swap "clean"
        // this further allows LP holders to easily claim fees for tokens they have/staked
        _index_0: u256,
        _index_1: u256,
        // position assigned to each LP to track their current index0 & index1 vs the global position
        _supply_index_0: LegacyMap<ContractAddress, u256>,
        _supply_index_1: LegacyMap<ContractAddress, u256>,
        // tracks the amount of unclaimed, but claimable tokens off of fees for token0 and token1
        _claimable_0: LegacyMap<ContractAddress, u256>,
        _claimable_1: LegacyMap<ContractAddress, u256>,
    }

    const MINIMUM_LIQUIDITY: u256 = 1000; // 10 ** 3
    const period_size: u128 = 1800; // Capture oracle reading every 30 minutes

    #[derive(Copy, Drop, Serde)]
    struct Metadata {
        decimals_0: u256,
        decimals_1: u256,
        reserve_0: u256,
        reserve_1: u256,
        stable: bool,
        token_0: ContractAddress,
        token_1: ContractAddress
    }

    #[event]
    fn Fees(sender: ContractAddress, amount_0: u256, amount_1: u256) {}

    #[event]
    fn Mint(sender: ContractAddress, amount_0: u256, amount_1: u256) {}

    #[event]
    fn Burn(sender: ContractAddress, amount_0: u256, amount_1: u256, to: ContractAddress) {}

    #[event]
    fn Swap(
        sender: ContractAddress,
        amount_0_in: u256,
        amount_1_in: u256,
        amount_0_out: u256,
        amount_1_out: u256,
        to: ContractAddress
    ) {}

    #[event]
    fn Sync(reserve_0: u256, reserve_1: u256) {}

    #[event]
    fn Claim(sender: ContractAddress, recipient: ContractAddress, amount_0: u256, amount_1: u256) {}

    #[constructor]
    fn constructor() {
        _factory::write(get_caller_address());
        let (token_0_, token_1_, stable_) = IPairFactoryDispatcher {
            contract_address: get_caller_address()
        }.get_initializable();
        _token_0::write(token_0_);
        _token_1::write(token_1_);
        _stable::write(stable_);

        let pair_fees_class_hash = IPairFactoryDispatcher {
            contract_address: get_caller_address()
        }.pair_fees_class_hash();

        let salt = LegacyHash::hash(token_0_.into(), token_1_);
        let salt = LegacyHash::hash(salt, stable_);

        let empyt_array = ArrayTrait::<felt252>::new().span();

        let (pair_fees_address, deploy_data) = deploy_syscall(
            pair_fees_class_hash, salt, empyt_array, false
        )
            .unwrap_syscall();

        _fees::write(pair_fees_address);

        if stable_ {
            ERC20::initializer('Spin StableV1 AMM', 'SPIN-sAMM');
        } else {
            ERC20::initializer('Spin VolatileV1 AMM', 'SPIN-vAMM')
        }

        let token_0_decimals = IERC20Dispatcher { contract_address: token_0_ }.decimals();
        let token_1_decimals = IERC20Dispatcher { contract_address: token_1_ }.decimals();

        _decimals_0::write(exp_by_squares(10, u256 { low: token_0_decimals.into(), high: 0 }));
        _decimals_1::write(exp_by_squares(10, u256 { low: token_1_decimals.into(), high: 0 }));

        append_observation(
            Observation {
                timestamp: get_block_timestamp_u128(),
                reserve_0_cumulative: 0,
                reserve_1_cumulative: 0
            }
        );
    }

    ///
    /// ERC20
    ///

    #[view]
    fn name() -> felt252 {
        ERC20::name()
    }

    #[view]
    fn symbol() -> felt252 {
        ERC20::symbol()
    }

    #[view]
    fn decimals() -> u8 {
        ERC20::decimals()
    }

    #[view]
    fn total_supply() -> u256 {
        ERC20::total_supply()
    }

    #[view]
    fn balance_of(account: ContractAddress) -> u256 {
        ERC20::balance_of(account)
    }

    #[view]
    fn allowance(owner: ContractAddress, spender: ContractAddress) -> u256 {
        ERC20::allowance(owner, spender)
    }

    #[external]
    fn transfer(recipient: ContractAddress, amount: u256) -> bool {
        ERC20::transfer(recipient, amount)
    }

    #[external]
    fn transfer_from(sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool {
        ERC20::transfer_from(sender, recipient, amount)
    }

    #[external]
    fn approve(spender: ContractAddress, amount: u256) -> bool {
        ERC20::approve(spender, amount)
    }

    #[external]
    fn increase_allowance(spender: ContractAddress, added_value: u256) -> bool {
        ERC20::increase_allowance(spender, added_value)
    }

    #[external]
    fn decrease_allowance(spender: ContractAddress, subtracted_value: u256) -> bool {
        ERC20::decrease_allowance(spender, subtracted_value)
    }

    ///
    // SWAP
    ///

    #[view]
    // use index mock length
    fn observation_length() -> u256 {
        _observation_index::read()
    }

    #[view]
    fn last_observation() -> Observation {
        if _observation_index::read() == 0 {
            return Observation { timestamp: 0, reserve_0_cumulative: 0, reserve_1_cumulative: 0 };
        }
        _observations::read(_observation_index::read() - 1)
    }

    #[view]
    fn metadata() -> Metadata {
        Metadata {
            decimals_0: _decimals_0::read(),
            decimals_1: _decimals_1::read(),
            reserve_0: _reserve_0::read(),
            reserve_1: _reserve_1::read(),
            stable: _stable::read(),
            token_0: _token_0::read(),
            token_1: _token_1::read()
        }
    }

    #[view]
    fn tokens() -> (ContractAddress, ContractAddress) {
        (_token_0::read(), _token_1::read())
    }

    #[view]
    fn is_stable() -> bool {
        _stable::read()
    }

    // claim accumulated but unclaimed fees (viewable via claimable0 and claimable1)
    #[external]
    fn claim_fees() -> (u256, u256) {
        let caller = get_caller_address();
        _update_for(caller);

        let claimed_0 = _claimable_0::read(caller);
        let claimed_1 = _claimable_1::read(caller);

        if or(claimed_0 > 0, claimed_1 > 0) {
            _claimable_0::write(caller, 0);
            _claimable_1::write(caller, 0);

            IPairFeesDispatcher {
                contract_address: _fees::read()
            }.claim_fees_for(caller, claimed_0, claimed_1);

            Claim(caller, caller, claimed_0, claimed_1);
        }
        (claimed_0, claimed_1)
    }

    #[external]
    fn claim_staking_fees() {
        let fee_handler = IPairFactoryDispatcher {
            contract_address: _factory::read()
        }.staking_fee_handler();
        IPairFeesDispatcher { contract_address: _fees::read() }.withdraw_staking_fees(fee_handler);
    }

    #[view]
    fn get_reserves() -> (u256, u256, u128) {
        (_reserve_0::read(), _reserve_1::read(), _block_timestamp_last::read())
    }

    #[view]
    // produces the cumulative price using counterfactuals to save gas and avoid a call to sync.
    fn current_cumulative_prices() -> (u256, u256, u128) {
        let mut block_timestamp = get_block_timestamp_u128();
        let mut reserve_0_cumulative = _reserve_0_cumulative_last::read();
        let mut reserve_1_cumulative = _reserve_1_cumulative_last::read();
        // if time has elapsed since the last update on the pair, mock the accumulated price values

        let (reserve_0, reserve_1, block_timestamp_last) = get_reserves();
        if block_timestamp_last != block_timestamp { // subtraction overflow is desired
            let time_elapsed = u256 { low: block_timestamp - block_timestamp_last, high: 0 };
            reserve_0_cumulative += reserve_0 * time_elapsed;
            reserve_1_cumulative += reserve_1 * time_elapsed;
        }

        (reserve_0_cumulative, reserve_1_cumulative, block_timestamp)
    }

    #[view]
    fn get_amount_out(amount_in: u256, token_in: ContractAddress) -> u256 {
        let (reserve_0, reserve_1) = (_reserve_0::read(), _reserve_1::read());
        let factory = IPairFactoryDispatcher { contract_address: _factory::read() };
        let amount_in = amount_in
            - (amount_in
                * factory.get_fee(_stable::read())
                / 1000); // remove fee from amount received
        _get_amount_out(amount_in, token_in, reserve_0, reserve_1)
    }

    // gives the current twap price measured from amountIn * tokenIn gives amountOut
    fn current(token_in: ContractAddress, amount_in: u256) -> u256 {
        let mut obervation = last_observation();
        let (reserve_0_cumulative, reserve_1_cumulative, block_timestamp) =
            current_cumulative_prices();
        if block_timestamp == obervation.timestamp {
            obervation = _observations::read(_observation_index::read() - 2);
        }

        let time_elapsed = u256 { low: block_timestamp - obervation.timestamp, high: 0 };
        let reserve_0 = (reserve_0_cumulative - obervation.reserve_0_cumulative) / time_elapsed;
        let reserve_1 = (reserve_1_cumulative - obervation.reserve_1_cumulative) / time_elapsed;
        let amount_out = _get_amount_out(amount_in, token_in, reserve_0, reserve_1);

        amount_out
    }

    #[view]
    fn sample(
        token_in: ContractAddress, amount_in: u256, points: u256, window: u256
    ) -> Array<u256> {
        let mut prices = ArrayTrait::<u256>::new();
        let length = _observation_index::read() - 1;
        let mut i = length - (points * window);
        let mut next_index = 0_u256;
        let mut index = 0_u256;

        loop {
            if i >= length {
                break ();
            }

            next_index = i + window;
            let next_observation = _observations::read(next_index);
            let current_observation = _observations::read(i);

            let time_elapsed_ = next_observation.timestamp - current_observation.timestamp;
            let time_elapsed = u256 { low: time_elapsed_, high: 0 };
            let reserve_0 = (next_observation.reserve_0_cumulative
                - current_observation.reserve_0_cumulative)
                / time_elapsed;
            let reserve_1 = (next_observation.reserve_1_cumulative
                - current_observation.reserve_1_cumulative)
                / time_elapsed;

            prices.append(_get_amount_out(amount_in, token_in, reserve_0, reserve_1));

            index = index + 1;
            i = i + window;
        };

        prices
    }

    // as per `current`, however allows user configured granularity, up to the full window size
    // get amount out
    #[view]
    fn quote(token_in: ContractAddress, amount_in: u256, granularity: u256) -> u256 {
        let prices = sample(token_in, amount_in, granularity, 1);
        let mut price_average_cumulative = 0_u256;
        let prices_length = prices.len();
        let mut i = 0_u32;

        loop {
            if i >= prices_length {
                break ();
            }
            price_average_cumulative += *prices[i];
            i = i + 1;
        };

        price_average_cumulative / granularity
    }

    // returns a memory set of twap prices
    #[view]
    fn prices(token_in: ContractAddress, amount_in: u256, points: u256) -> Array<u256> {
        sample(token_in, amount_in, points, 1)
    }

    // this low-level function should be called by addLiquidity functions in Router.sol, which performs important safety checks
    // standard uniswap v2 implementation
    // return liquidity
    #[external]
    fn mint(to: ContractAddress) -> u256 {
        ReentrancyGuard::start();
        let mut liquidity = 0_u256;
        let (reserve_0, reserve_1) = (_reserve_0::read(), _reserve_1::read());
        let balance_0 = IERC20Dispatcher {
            contract_address: _token_0::read()
        }.balance_of(get_caller_address());
        let balance_1 = IERC20Dispatcher {
            contract_address: _token_1::read()
        }.balance_of(get_caller_address());
        let amount_0 = balance_0 - reserve_0;
        let amount_1 = balance_1 - reserve_1;

        let total_supply_ =
            _total_supply::read(); //  gas savings, must be defined here since totalSupply can update in _mintFee
        if total_supply_ == 0 {
            liquidity = u256 { low: u256_sqrt(amount_0 * amount_1), high: 0 } - MINIMUM_LIQUIDITY;
            ERC20::_mint(
                Zeroable::zero(), MINIMUM_LIQUIDITY
            ); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity =
                Math::min(
                    amount_0 * total_supply_ / reserve_0, amount_1 * total_supply_ / reserve_1
                );
        }

        assert(liquidity > 0, 'INSUFFICIENT LIQUIDITY MINTED');
        ERC20::_mint(to, liquidity);

        _update(balance_0, balance_1, reserve_0, reserve_1);
        Mint(get_caller_address(), amount_0, amount_1);

        ReentrancyGuard::end();

        liquidity
    }

    // this low-level function should be called from a contract which performs important safety checks
    // standard uniswap v2 implementation
    #[external]
    fn burn(to: ContractAddress) -> (u256, u256) {
        ReentrancyGuard::start();
        let (reserve_0, reserve_1) = (_reserve_0::read(), _reserve_1::read());
        let (token_0, token_1) = (_token_0::read(), _token_1::read());
        let token_0_ = IERC20Dispatcher { contract_address: token_0 };
        let token_1_ = IERC20Dispatcher { contract_address: token_1 };

        let balance_0 = token_0_.balance_of(get_caller_address());
        let balance_1 = token_1_.balance_of(get_caller_address());
        let liquidity = IERC20::balance_of(get_contract_address());
        let total_supply_ = _total_supply::read();
        let amount_0 = liquidity
            * balance_0
            / total_supply_; // using balances ensures pro-rata distribution
        let amount_1 = liquidity
            * balance_1
            / total_supply_; //using balances ensures pro-rata distribution
        assert(and_and(amount_0 > 0, amount_1 > 0), 'INSUFFICIENT LIQUIDITY BURNED');
        ERC20::_burn(get_contract_address(), liquidity);

        token_0_.transfer(to, amount_0);
        token_1_.transfer(to, amount_1);

        let balance_0 = token_0_.balance_of(get_caller_address());
        let balance_1 = token_1_.balance_of(get_caller_address());

        _update(balance_0, balance_1, reserve_0, reserve_1);
        Burn(get_caller_address(), amount_0, amount_1, to);

        ReentrancyGuard::end();

        (amount_0, amount_1)
    }

    // this low-level function should be called from a contract which performs important safety checks
    #[external]
    fn swap(amount_0_out: u256, amount_1_out: u256, to: ContractAddress, data: Span<felt252>) {
        ReentrancyGuard::start();
        let factory = IPairFactoryDispatcher { contract_address: _factory::read() };
        assert(!factory.is_paused(), 'only not paused');
        assert(or(amount_0_out > 0, amount_1_out > 0), 'INSUFFICIENT OUTPUT AMOUNT');
        let (reserve_0, reserve_1) = (_reserve_0::read(), _reserve_1::read());
        assert(
            and_and(amount_0_out < reserve_0, amount_1_out < reserve_1), 'INSUFFICIENT LIQUIDITY'
        );

        let mut balance_0 = 0_u256;
        let mut balance_1 = 0_u256;

        let (token_0, token_1) = (_token_0::read(), _token_1::read());
        let token_0_ = IERC20Dispatcher { contract_address: token_0 };
        let token_1_ = IERC20Dispatcher { contract_address: token_1 };

        assert(and_and(to != token_0, to != token_1), 'INVALID TO');
        if amount_0_out > 0 {
            token_0_.transfer(to, amount_0_out);
        }
        if amount_1_out > 0 {
            token_1_.transfer(to, amount_1_out);
        }
        if data.len() > 0 {
            IPairCalleeDispatcher {
                contract_address: to
            }
                .hook(
                    get_caller_address(), amount_0_out, amount_1_out, data
                ); // callback, used for flash loans
        }
        balance_0 = token_0_.balance_of(get_caller_address());
        balance_1 = token_1_.balance_of(get_caller_address());

        let amount_0_in = if balance_0 > reserve_0 - amount_0_out {
            balance_0 - (reserve_0 - amount_0_out)
        } else {
            0
        };
        let amount_1_in = if balance_1 > reserve_1 - amount_1_out {
            balance_1 - (reserve_1 - amount_1_out)
        } else {
            0
        };
        assert(or(amount_0_in > 0, amount_1_in > 0), 'INSUFFICIENT INPUT AMOUNT');

        if amount_0_in > 0 {
            _update_0(
                amount_0_in * factory.get_fee(_stable::read()) / 10000
            ); // accrue fees for token0 and move them out of pool
        }
        if amount_1_in > 0 {
            _update_1(
                amount_1_in * factory.get_fee(_stable::read()) / 10000
            ); // accrue fees for token1 and move them out of pool
        }
        balance_0 = token_0_
            .balance_of(
                get_caller_address()
            ); // since we removed tokens, we need to reconfirm balances, can also simply use previous balance - amountIn/ 10000, but doing balanceOf again as safety chec
        balance_1 = token_1_.balance_of(get_caller_address());

        // The curve, either x3y+y3x for stable pools, or x*y for volatile pools
        assert(_k(balance_0, balance_1) >= _k(reserve_0, reserve_1), 'K');

        _update(balance_0, balance_1, reserve_0, reserve_1);
        Swap(get_caller_address(), amount_0_in, amount_1_in, amount_0_out, amount_1_out, to);

        ReentrancyGuard::end();
    }

    // force balances to match reserves
    #[external]
    fn skim(to: ContractAddress) {
        ReentrancyGuard::start();
        let (token_0, token_1) = (_token_0::read(), _token_1::read());
        let token_0_ = IERC20Dispatcher { contract_address: token_0 };
        let token_1_ = IERC20Dispatcher { contract_address: token_1 };
        token_0_.transfer(to, token_0_.balance_of(get_contract_address()) - _reserve_0::read());
        token_1_.transfer(to, token_1_.balance_of(get_contract_address()) - _reserve_1::read());
        ReentrancyGuard::end();
    }

    // force reserves to match balances
    #[external]
    fn sync() {
        ReentrancyGuard::start();
        let (token_0, token_1) = (_token_0::read(), _token_1::read());
        let token_0_ = IERC20Dispatcher { contract_address: token_0 };
        let token_1_ = IERC20Dispatcher { contract_address: token_1 };
        _update(
            token_0_.balance_of(get_contract_address()),
            token_1_.balance_of(get_contract_address()),
            _reserve_0::read(),
            _reserve_1::read(),
        );
        ReentrancyGuard::end();
    }
    // Accrue fees on token0
    fn _update_0(amount: u256) {
        let (ratio, total_amount) = _update_token(amount, _token_0::read());

        if ratio > 0 {
            _index_0::write(_index_0::read() + ratio);
        }

        Fees(get_caller_address(), total_amount, 0);
    }

    // Accrue fees on token1
    fn _update_1(amount: u256) {
        let (ratio, total_amount) = _update_token(amount, _token_1::read());

        if ratio > 0 {
            _index_0::write(_index_1::read() + ratio);
        }

        Fees(get_caller_address(), 0, total_amount);
    }

    // return ratio and total amount
    fn _update_token(amount: u256, token_address: ContractAddress) -> (u256, u256) {
        // get referral fee
        let factory = IPairFactoryDispatcher { contract_address: _factory::read() };
        let dibs = factory.dibs();
        let max_ref = factory.max_referral_fee();
        let referral_fee = amount * max_ref / 10000;
        IERC20Dispatcher {
            contract_address: token_address
        }.transfer(dibs, referral_fee); // transfer the fees out to PairFees

        // get lp and staking fee
        let staking_nft_fee = amount * factory.staking_nft_fee() / 10000;
        IPairFeesDispatcher {
            contract_address: _fees::read()
        }.process_staking_fees(staking_nft_fee, true);
        IERC20Dispatcher {
            contract_address: token_address
        }.transfer(_fees::read(), amount); // transfer the fees out to PairFees

        // remove staking fees from lpfees
        let amount = amount - staking_nft_fee;
        let ratio = amount
            * 1_000_000_000_000_000_000_u256
            / _total_supply::read(); // 1e18 adjustment is removed during claim

        (ratio, amount + staking_nft_fee + referral_fee)
    }

    // this function MUST be called on any balance changes, otherwise can be used to infinitely claim fees
    // Fees are segregated from core funds, so fees can never put liquidity at risk
    fn _update_for(recipient: ContractAddress) {
        let supplied = IERC20::balance_of(recipient); // get LP balance of `recipient`

        if supplied > 0 {
            let supply_index_0 = _supply_index_0::read(
                recipient
            ); // get last adjusted index0 for recipient
            let supply_index_1 = _supply_index_1::read(recipient);
            let index_0 = _index_0::read(); //get global index0 for accumulated fees
            let index_1 = _index_1::read();
            _supply_index_0::write(
                recipient, index_0
            ); // update user current position to global position
            _supply_index_1::write(recipient, index_1);
            let delta_0 = index_0
                - supply_index_0; // see if there is any difference that need to be accrued
            let delta_1 = index_1 - supply_index_1;
            if delta_0 > 0 {
                let share = supplied * delta_0 / 1_000_000_000_000_000_000_u256; // 1e18
                _claimable_0::write(recipient, _claimable_0::read(recipient) + share);
            }
            if delta_1 > 0 {
                let share = supplied * delta_1 / 1_000_000_000_000_000_000_u256; // 1e18
                _claimable_1::write(recipient, _claimable_1::read(recipient) + share);
            }
        } else {
            _supply_index_0::write(
                recipient, _index_0::read()
            ); // new users are set to the default global state
            _supply_index_1::write(
                recipient, _index_1::read()
            ); // new users are set to the default global state
        }
    }


    // update reserves and, on the first call per block, price accumulators
    fn _update(balance_0: u256, balance_1: u256, reserve_0: u256, reserve_1: u256) {
        let block_timestamp = get_block_timestamp_u128();
        let mut time_elapsed = u256 {
            low: block_timestamp - _block_timestamp_last::read(), high: 0
        }; // overflow is desired
        if and_and(and_and(time_elapsed > 0, reserve_0 != 0), reserve_1 != 0) {
            _reserve_0_cumulative_last::write(
                _reserve_0_cumulative_last::read() + (reserve_0 * time_elapsed)
            );
            _reserve_1_cumulative_last::write(
                _reserve_1_cumulative_last::read() + (reserve_1 * time_elapsed)
            );
        }

        let point = last_observation();
        time_elapsed = u256 { low: block_timestamp - point.timestamp, high: 0 };
        if time_elapsed.low > period_size {
            append_observation(
                Observation {
                    timestamp: block_timestamp,
                    reserve_0_cumulative: _reserve_0_cumulative_last::read(),
                    reserve_1_cumulative: _reserve_1_cumulative_last::read(),
                }
            );
        }

        _reserve_0::write(balance_0);
        _reserve_1::write(balance_1);
        _block_timestamp_last::write(block_timestamp);

        Sync(_reserve_0::read(), _reserve_1::read());
    }

    fn _get_amount_out(
        amount_in: u256, token_in: ContractAddress, reserve_0_: u256, reserve_1_: u256
    ) -> u256 {
        let one_power_18 = 1_000_000_000_000_000_000_u256;
        let (reserve_a, reserve_b) = if token_in == _token_0::read() {
            (_reserve_0::read(), _reserve_1::read())
        } else {
            (_reserve_1::read(), _reserve_0::read())
        };

        if _stable::read() {
            let xy = _k(reserve_0_, reserve_1_);
            let reserve_0_ = reserve_0_ * one_power_18 / _decimals_0::read();
            let reserve_1_ = reserve_1_ * one_power_18 / _decimals_1::read();

            let decimals_ = if token_in == _token_0::read() {
                _decimals_0::read()
            } else {
                _decimals_1::read()
            };
            let amount_in = amount_in * one_power_18 / decimals_;
            let y = reserve_b - _get_y(amount_in + reserve_a, xy, reserve_b);

            return y * decimals_ / one_power_18;
        } else {
            return amount_in * reserve_b / (reserve_a + amount_in);
        }
    }

    fn _f(x0: u256, y: u256) -> u256 {
        let one_power_18 = 1_000_000_000_000_000_000_u256;
        x0 * (y * y / one_power_18 * y / one_power_18) / one_power_18
            + (x0 * x0 / one_power_18 * x0 / one_power_18) * y / one_power_18
    }

    fn _d(x0: u256, y: u256) -> u256 {
        let one_power_18 = 1_000_000_000_000_000_000_u256;
        3 * x0 * (y * y / one_power_18) / one_power_18
            + (x0 * x0 / one_power_18 * x0 / one_power_18)
    }

    fn _get_y(x0: u256, xy: u256, mut y: u256) -> u256 {
        let one_power_18 = 1_000_000_000_000_000_000_u256;
        let mut i = 0_usize;
        loop {
            if i >= 255 {
                break ();
            }
            let y_prev = y;
            let k = _f(x0, y);
            if k < xy {
                let dy = (xy - k) * one_power_18 / _d(x0, y);
                y = y + dy;
            } else {
                let dy = (k - xy) * one_power_18 / _d(x0, y);
                y = y - dy;
            }

            if y > y_prev {
                if y - y_prev <= 1 {
                    break ();
                }
            } else {
                if y_prev - y <= 1 {
                    break ();
                }
            }

            i = i + 1;
        };
        y
    }

    fn _k(x: u256, y: u256) -> u256 {
        let one_power_18 = 1_000_000_000_000_000_000_u256;

        if _stable::read() {
            let x_ = x * one_power_18 / _decimals_0::read();
            let y_ = y * one_power_18 / _decimals_1::read();
            let a_ = (x_ * y_) / one_power_18;
            let b_ = ((x_ * x_) / one_power_18 + (y_ * y) / one_power_18);
            return a_ * b_ / one_power_18; // x3y + y3x >= k
        } else {
            return x * y; // xy >= k
        }
    }

    fn append_observation(observation_: Observation) -> u256 {
        let observation_index = _observation_index::read();
        _observations::write(observation_index, observation_);

        let new_index = observation_index + 1;
        _observation_index::write(new_index);

        new_index
    }
}
