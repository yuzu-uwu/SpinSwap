use core::zeroable::Zeroable;
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

/// @notice Info of each user.
#[derive(Copy, Drop, Serde)]
struct UserInfo {
    amount: u256,
    reward_debt: u256
}

/// @notice Struct of pool info
#[derive(Copy, Drop, Serde)]
struct PoolInfo {
    acc_reward_per_share: u256,
    last_reward_time: u128
}


impl UserInfoStorageAccess of StorageAccess<UserInfo> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult::<UserInfo> {
        let amount = StorageAccess::read(address_domain, base)?;

        let reward_debt_base = storage_base_address_from_felt252(
            storage_address_from_base_and_offset(base, 1_u8).into()
        );
        let reward_debt = StorageAccess::read(address_domain, reward_debt_base)?;

        Result::Ok(UserInfo { amount, reward_debt })
    }

    fn write(
        address_domain: u32, base: StorageBaseAddress, value: UserInfo
    ) -> SyscallResult::<()> {
        StorageAccess::write(address_domain, base, value.amount)?;

        let reward_debt_base = storage_base_address_from_felt252(
            storage_address_from_base_and_offset(base, 1_u8).into()
        );
        StorageAccess::write(address_domain, reward_debt_base, value.reward_debt)
    }
}

impl PoolInfoStorageAccess of StorageAccess<PoolInfo> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult::<PoolInfo> {
        let acc_reward_per_share = StorageAccess::read(address_domain, base)?;

        let last_reward_time_base = storage_base_address_from_felt252(
            storage_address_from_base_and_offset(base, 1_u8).into()
        );
        let last_reward_time = StorageAccess::read(address_domain, last_reward_time_base)?;

        Result::Ok(PoolInfo { acc_reward_per_share, last_reward_time })
    }

    fn write(
        address_domain: u32, base: StorageBaseAddress, value: PoolInfo
    ) -> SyscallResult::<()> {
        StorageAccess::write(address_domain, base, value.acc_reward_per_share)?;

        let last_reward_time_base = storage_base_address_from_felt252(
            storage_address_from_base_and_offset(base, 1_u8).into()
        );
        StorageAccess::write(address_domain, last_reward_time_base, value.last_reward_time)
    }
}


#[contract]
mod GaugeExtraRewarder {
    use zeroable::Zeroable;
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use openzeppelin::token::erc20::interface::{IERC20, IERC20DispatcherTrait, IERC20Dispatcher};
    use openzeppelin::access::ownable::Ownable;
    use spin_lib::utils::{
        get_block_timestamp_u128, get_block_number_u128, and_and, or, u128_to_u256
    };
    use spinswap::interfaces::IGauge::{IGaugeDispatcher, IGaugeDispatcherTrait};
    use super::{UserInfo, PoolInfo};

    const ACC_TOKEN_PRECISION: u256 = 1_000_000_000_000_u256; // 1e12


    struct Storage {
        _reward_token_contract: ContractAddress,
        _gauge_contract: ContractAddress,
        _pool_info: PoolInfo,
        _user_info: LegacyMap<ContractAddress, UserInfo>,
        _last_distributed_time: u128,
        _reward_per_second: u256,
        _distribute_period: u128,
    }


    #[event]
    fn OnReward(
        user: ContractAddress, lp_balance: u256, reward_amount: u256, to: ContractAddress
    ) {}

    #[constructor]
    fn constructor(reward_token_: ContractAddress, gauge_: ContractAddress) {
        _reward_token_contract::write(reward_token_);
        _gauge_contract::write(gauge_);
        _pool_info::write(
            PoolInfo { last_reward_time: get_block_timestamp_u128(), acc_reward_per_share: 0 }
        );
        _distribute_period::write(7 * 86400); // 7days

        Ownable::_transfer_ownership(get_caller_address());
    }


    /// @notice Call onReward from gauge, it saves the new user balance and get any available reward
    /// @param _user    user address
    /// @param to       where to send rewards
    /// @param userBalance  the balance of LP in gauge
    #[external]
    fn on_reward(user_: ContractAddress, to: ContractAddress, user_balance: u256) {
        let pool = update_pool();
        let mut user = _user_info::read(user_);
        let mut pending = 0_u256;

        if user.amount > 0 {
            pending = _pending_reward(user_);
            _reward_token().transfer(to, pending);
        }
        user.amount = user_balance;
        user.reward_debt = user_balance * pool.acc_reward_per_share / ACC_TOKEN_PRECISION;

        _user_info::write(user_, user);

        OnReward(user_, user_balance, pending, to);
    }

     /// @notice View function to see pending Rewards on frontend.
    /// @param _user Address of user.
    /// @return pending rewardToken reward for a given user.
    #[view]
    fn pending_reward(user_: ContractAddress) -> u256 {
        _pending_reward(user_)
    }

    /// @notice Update reward variables of the given pool.
    /// @return pool Returns the pool that was updated
    #[external]
    fn update_pool() -> PoolInfo {
        let mut pool = _pool_info::read();
        let block_timestamp = get_block_timestamp_u128();
        if block_timestamp > pool.last_reward_time {
            let lp_supply = IERC20Dispatcher {
                contract_address: _gauge().token()
            }.balance_of(_gauge_contract::read());

            if lp_supply > 0 {
                // if we reach the end, look for the missing seconds up to LastDistributedTime ; else use block.timestamp

                let mut temp_timestamp_ = 0_u128;
                if block_timestamp >= _last_distributed_time::read() {
                    // if lastRewardTime is > than LastDistributedTime then set tempTimestamp to 0 to avoid underflow
                    temp_timestamp_ =
                        if pool.last_reward_time > _last_distributed_time::read() {
                            0
                        } else {
                            _last_distributed_time::read() - pool.last_reward_time
                        }
                } else {
                    temp_timestamp_ = block_timestamp - pool.last_reward_time;
                }

                let time = temp_timestamp_;
                let reward = u128_to_u256(time) * _reward_per_second::read();

                pool.acc_reward_per_share = pool.acc_reward_per_share
                    + (reward * ACC_TOKEN_PRECISION / lp_supply)
            }

            pool.last_reward_time = block_timestamp;
            _pool_info::write(pool);
        }
        pool
    }

    /// @notice Set the distribution rate for a given distributePeriod. Rewards needs to be sent before calling setDistributionRate
    #[external]
    fn set_distribution_rate(amount: u256) {
        Ownable::assert_only_owner();

        update_pool();
        assert(_reward_token().balance_of(get_contract_address()) >= amount, 'enough');
        let mut not_distributed = 0_u256;
        let block_timestamp = get_block_timestamp_u128();
        if block_timestamp < _last_distributed_time::read() {
            let timeleft = u128_to_u256(_last_distributed_time::read() - block_timestamp);
            not_distributed = _reward_per_second::read() * timeleft;
        }

        let amount = amount + not_distributed;
        let reward_per_second = amount / u128_to_u256(_distribute_period::read());
        assert(_reward_token().balance_of(get_contract_address()) >= amount, 'too many amount');

        _reward_per_second::write(reward_per_second);
        _last_distributed_time::write(block_timestamp + _distribute_period::read());
    }

    /// @notice Recover any ERC20 available
    #[external]
    fn recover_erc20(amount: u256, token: ContractAddress) {
        Ownable::assert_only_owner();
        assert(amount > 0, 'amount > 0');
        assert(token.is_non_zero(), 'zero addr');

        let token_ = IERC20Dispatcher { contract_address: token };
        let balance = token_.balance_of(get_contract_address());
        assert(balance >= amount, 'not enough tokens');

        // if token is = reward and there are some (rps > 0), allow withdraw only for remaining rewards and then set new rewPerSec
        if and_and(token == _reward_token_contract::read(), _reward_per_second::read() != 0) {
            update_pool();
            let timeleft = u128_to_u256(
                _last_distributed_time::read() - get_block_timestamp_u128()
            );
            let not_distributed = _reward_per_second::read() * timeleft;
            assert(amount <= not_distributed, 'too many rewardToken');
            _reward_per_second::write((not_distributed - amount) / timeleft);
        }

        token_.transfer(get_caller_address(), amount);
    }

    fn assert_only_gauge() {
        assert(get_caller_address() == _gauge_contract::read(), 'only gauge');
    }

    fn _gauge() -> IGaugeDispatcher {
        IGaugeDispatcher { contract_address: _gauge_contract::read() }
    }

    fn _reward_token() -> IERC20Dispatcher {
        IERC20Dispatcher { contract_address: _reward_token_contract::read() }
    }

    fn _pending_reward(user_: ContractAddress) -> u256 {
        let pool = _pool_info::read();
        let user = _user_info::read(user_);
        let mut acc_reward_per_share = pool.acc_reward_per_share;
        let lp_supply = IERC20Dispatcher {
            contract_address: _gauge().token()
        }.balance_of(_gauge_contract::read());
        let block_timestamp = get_block_timestamp_u128();

        if and_and(block_timestamp > pool.last_reward_time, lp_supply != 0) {
            // if we reach the end, look for the missing seconds up to LastDistributedTime ; else use block.timestamp
            let mut temp_timestamp_ = 0_u128;
            if block_timestamp >= _last_distributed_time::read() {
                // if lastRewardTime is > than LastDistributedTime then set tempTimestamp to 0 to avoid underflow
                temp_timestamp_ =
                    if pool.last_reward_time > _last_distributed_time::read() {
                        0
                    } else {
                        _last_distributed_time::read() - pool.last_reward_time
                    };
            } else {
                temp_timestamp_ = block_timestamp - pool.last_reward_time;
            }

            let time = u128_to_u256(temp_timestamp_);
            let reward = time * _reward_per_second::read();
            acc_reward_per_share = acc_reward_per_share
                + (reward * ACC_TOKEN_PRECISION) / lp_supply;
        }

        (user.amount * acc_reward_per_share / ACC_TOKEN_PRECISION) - user.reward_debt
    }
}
