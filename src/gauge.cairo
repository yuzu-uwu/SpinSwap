use starknet::ContractAddress;

#[abi]
trait IRewarder {
    #[external]
    fn on_reward(user: ContractAddress, recipient: ContractAddress, user_balance: u256);
}


#[contract]
mod Gauge {
    use core::array::ArrayTrait;
    use zeroable::Zeroable;
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use openzeppelin::security::reentrancyguard::ReentrancyGuard;
    use openzeppelin::access::ownable::Ownable;
    use openzeppelin::token::erc20::interface::{IERC20, IERC20DispatcherTrait, IERC20Dispatcher};
    use super::{IRewarderDispatcher, IRewarderDispatcherTrait};
    use spin_lib::utils::{
        get_block_timestamp_u128, get_block_number_u128, and_and, or, u128_to_u256
    };
    use spin_lib::math::Math;
    use spinswap::interfaces::IPair::{IPairDispatcher, IPairDispatcherTrait};
    use spinswap::interfaces::IBribe::{IBribeDispatcher, IBribeDispatcherTrait};

    #[storage]
    struct Storage {
        _is_for_pair: bool,
        _emergency: bool, // for safe
        _reward_token_contract: ContractAddress,
        _ve_contract: ContractAddress,
        _token_address: ContractAddress,
        _distribution: ContractAddress,
        _gauge_rewarder: ContractAddress,
        _internal_bribe: ContractAddress,
        _rewarder_pid: u256,
        _duration: u128,
        _period_finish: u128,
        _reward_rate: u256,
        _last_update_time: u128,
        _reward_per_token_stored: u256,
        _fees_0: u256,
        _fees_1: u256,
        _user_reward_per_token_paid: LegacyMap<ContractAddress, u256>,
        _rewards: LegacyMap<ContractAddress, u256>,
        _total_supply: u256,
        _balances: LegacyMap<ContractAddress, u256>,
    }

    #[event]
    fn RewardAdded(reward: u256) {}

    #[event]
    fn Deposit(user: ContractAddress, amount: u256) {}

    #[event]
    fn Withdraw(user: ContractAddress, amount: u256) {}

    #[event]
    fn Harvest(user: ContractAddress, reward: u256) {}

    #[event]
    fn ClaimFees(from: ContractAddress, claimed_0: u256, claimed_1: u256) {}

    #[event]
    fn EmergencyActivated(gauge: ContractAddress, timestamp: u128) {}

    #[event]
    fn EmergencyDeactivated(gauge: ContractAddress, timestamp: u128) {}

     #[constructor]
    fn constructor(reward_token_: ContractAddress, ve_: ContractAddress, token_: ContractAddress, distribution_: ContractAddress, internal_bribe_: ContractAddress, is_for_pair_: bool) {
        Ownable::transfer_ownership(get_caller_address());
        _reward_token_contract::write(reward_token_);
        _ve_contract:: write(ve_);
        _token_address::write(token_);
        _duration::write(7 * 86400); // 7 days

        _internal_bribe::write(internal_bribe_);

        _is_for_pair::write(is_for_pair_);

        _emergency::write(false);
    }

    fn _token() -> IERC20Dispatcher {
        IERC20Dispatcher { contract_address: _token_address::read() }
    }

    fn _reward_token() -> IERC20Dispatcher {
        IERC20Dispatcher { contract_address: _reward_token_contract::read() }
    }

    fn _update_reward(account: ContractAddress) {
        _reward_per_token_stored::write(reward_per_token());
        _last_update_time::write(last_time_reward_applicable().low);
        if account.is_non_zero() {
            _rewards::write(account, earned(account));
            _user_reward_per_token_paid::write(account, _reward_per_token_stored::read());
        }
    }

    fn assert_only_distribution() {
        assert(get_caller_address() == _distribution::read(), 'only rewards distribution');
    }

    fn assert_only_not_emergency() {
        assert(_emergency::read() == false, 'in emergency');
    }

    fn assert_only_emergency() {
        assert(_emergency::read() == true, 'only in emergency');
    }

    //-----------------------------------------------------------------------------
    //--------------------------------------------------------------------------------
    //--------------------------------------------------------------------------------
    //                               ONLY OWNER
    //--------------------------------------------------------------------------------
    //--------------------------------------------------------------------------------
    //----------------------------------------------------------------------------- 

    ///@notice set distribution address (should be GaugeProxyL2)
    #[external]
    fn set_distribution(distribution_: ContractAddress) {
        Ownable::assert_only_owner();
        assert(distribution_.is_non_zero(), 'zero addr');
        assert(distribution_ != _distribution::read(), 'same addr');
        _distribution::write(distribution_);
    }

    ///@notice set gauge rewarder address
    #[external]
    fn set_gauge_rewarder(gauge_rewarder_: ContractAddress) {
        Ownable::assert_only_owner();
        assert(gauge_rewarder_.is_non_zero(), 'zero addr');
        assert(gauge_rewarder_ != _gauge_rewarder::read(), 'same addr');
        _gauge_rewarder::write(gauge_rewarder_);
    }

    ///@notice set extra rewarder pid
    #[external]
    fn set_rewarder_pid(pid_: u256) {
        Ownable::assert_only_owner();
        assert(pid_ >= 0, 'zero');
        assert(pid_ != _rewarder_pid::read(), 'same pid');
        _rewarder_pid::write(pid_);
    }

    ///@notice set new internal bribe contract (where to send fees)
    #[external]
    fn set_internal_bribe(internal_bribe_: ContractAddress) {
        Ownable::assert_only_owner();

        assert(internal_bribe_.is_non_zero(), 'zero addr');
        _internal_bribe::write(internal_bribe_);
    }

    #[external]
    fn activate_emergency_mode() {
        Ownable::assert_only_owner();
        assert(_emergency::read() == false, 'shuold not in emergency');
        _emergency::write(true);

        EmergencyActivated(get_contract_address(), get_block_timestamp_u128());
    }

    #[external]
    fn stop_emergency_mode() {
        Ownable::assert_only_owner();

        assert(_emergency::read() == true, 'emergency');
        _emergency::write(false);

        EmergencyDeactivated(get_contract_address(), get_block_timestamp_u128());
    }

    // -----------------------------------------------------------------------------
    // --------------------------------------------------------------------------------
    // --------------------------------------------------------------------------------
    //                                 VIEW FUNCTIONS
    // --------------------------------------------------------------------------------
    // --------------------------------------------------------------------------------
    // ----------------------------------------------------------------------------- 

    ///@notice total supply held
    #[view]
    fn totaly_supply() -> u256 {
        _total_supply::read()
    }

    ///@notice balance of a user
    #[view]
    fn balance_of(account: ContractAddress) -> u256 {
        _balances::read(account)
    }

    #[view]
    fn reward_rate() -> u256 {
        _reward_rate::read()
    }

    #[view]
    fn is_for_pair() -> bool {
        _is_for_pair::read()
    }

    #[view]
    fn token() -> ContractAddress {
        _token_address::read()
    }

    ///@notice last time reward
    #[view]
    fn last_time_reward_applicable() -> u256 {
        Math::min(u128_to_u256(get_block_number_u128()), u128_to_u256(_period_finish::read()))
    }

    ///@notice  reward for a sinle token
    #[view]
    fn reward_per_token() -> u256 {
        let reward_per_token_stored = _reward_per_token_stored::read();
        if _total_supply::read() == 0 {
            return reward_per_token_stored;
        }
        reward_per_token_stored
            + (last_time_reward_applicable() - u128_to_u256(_last_update_time::read()))
                * _reward_rate::read()
                * 1_000_000_000_000_000_000_u256 // 1e18
                / _total_supply::read()
    }

    ///@notice see earned rewards for user
    #[view]
    fn earned(account: ContractAddress) -> u256 {
        let account_balance = _balances::read(account);
        let user_reward_per_token_paid = _user_reward_per_token_paid::read(account);
        let account_rewards = _rewards::read(account);

        account_rewards
            + account_balance
                * (reward_per_token() - user_reward_per_token_paid)
                / 1_000_000_000_000_000_000_u256
    }

    ///@notice get total reward for the duration
    #[view]
    fn reward_for_duration() -> u256 {
        _reward_rate::read() * u128_to_u256(_duration::read())
    }

    #[view]
    fn period_finish() -> u128 {
        _period_finish::read()
    }
    // -----------------------------------------------------------------------------
    // --------------------------------------------------------------------------------
    // --------------------------------------------------------------------------------
    //                                 USER INTERACTION
    // --------------------------------------------------------------------------------
    // --------------------------------------------------------------------------------
    // -----------------------------------------------------------------------------

    ///@notice deposit all TOKEN of msg.sender
    #[external]
    fn deposit_all() {
        _deposit(_token().balance_of(get_caller_address()), get_caller_address());
    }

    ///@notice withdraw a certain amount of TOKEN
    #[external]
    fn withdraw(amount: u256) {
        _withdraw(amount);
    }

    #[external]
    fn emergency_withdraw() {
        ReentrancyGuard::start();

        assert_only_emergency();

        let caller = get_caller_address();
        let amount = _balances::read(caller);

        assert(amount > 0, 'no balances');

        _total_supply::write(_total_supply::read() - amount);
        _balances::write(caller, 0);

        _token().transfer(caller, amount);

        Withdraw(caller, amount);

        ReentrancyGuard::end();
    }

    #[external]
    fn emergency_withdraw_amount(amount: u256) {
        ReentrancyGuard::start();

        assert_only_emergency();
        _total_supply::write(_total_supply::read() - amount);

        let caller = get_caller_address();
        _balances::write(caller, _balances::read(caller) - amount);

        _token().transfer(caller, amount);

        Withdraw(caller, amount);

        ReentrancyGuard::end();
    }

    ///@notice User harvest function called from distribution (voter allows harvest on multiple gauges)
    #[external]
    fn get_reward_by_distribution(user_: ContractAddress) {
        ReentrancyGuard::start();
        assert_only_distribution();
        _update_reward(user_);
        let reward = _rewards::read(user_);
        if reward > 0 {
            _rewards::write(user_, 0);
            _reward_token().transfer(user_, reward);

            Harvest(user_, reward);
        }

        if _gauge_rewarder::read().is_non_zero() {
            IRewarderDispatcher {
                contract_address: _gauge_rewarder::read()
            }.on_reward(user_, user_, _balances::read(user_));
        }

        ReentrancyGuard::end();
    }

    ///@notice User harvest function
    #[external]
    fn get_reward() {
        ReentrancyGuard::start();
        let caller = get_caller_address();
        _update_reward(caller);

        let reward = _rewards::read(caller);
        if reward > 0 {
            _rewards::write(caller, 0);
            _reward_token().transfer(caller, reward);

            Harvest(caller, reward);
        }

        if _gauge_rewarder::read().is_non_zero() {
            IRewarderDispatcher {
                contract_address: _gauge_rewarder::read()
            }.on_reward(caller, caller, _balances::read(caller));
        }

        ReentrancyGuard::end();
    }

    // -----------------------------------------------------------------------------
    // --------------------------------------------------------------------------------
    // --------------------------------------------------------------------------------
    //                                 DISTRIBUTION
    // --------------------------------------------------------------------------------
    // --------------------------------------------------------------------------------
    // ----------------------------------------------------------------------------- 

    /// @dev Receive rewards from distribution
    #[external]
    fn notify_reward_amount(token: ContractAddress, reward: u256) {
        ReentrancyGuard::start();
        assert_only_not_emergency();
        assert_only_distribution();
        _update_reward(Zeroable::zero());

        assert(token == _reward_token_contract::read(), 'not rew token');
        _reward_token().transfer_from(_distribution::read(), get_contract_address(), reward);

        let block_timestamp = get_block_timestamp_u128();
        if block_timestamp >= _period_finish::read() {
            _reward_rate::write(reward / u128_to_u256(_duration::read()));
        } else {
            let remaining = _period_finish::read() - block_timestamp;
            let leftover = u128_to_u256(remaining) * _reward_rate::read();
            _reward_rate::write((reward + leftover) / u128_to_u256(_duration::read()));
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        let balance = _reward_token().balance_of(get_contract_address());
        assert(
            _reward_rate::read() <= balance / u128_to_u256(_duration::read()),
            'Provided reward too high'
        );

        _last_update_time::write(block_timestamp);
        _period_finish::write(block_timestamp + _duration::read());

        RewardAdded(reward);

        ReentrancyGuard::end();
    }

    #[external]
    fn claim_fees() -> (u256, u256) {
        ReentrancyGuard::start();
        let (claimed_0, claimed_1) = _claim_fees();
        ReentrancyGuard::end();

        (claimed_0, claimed_1)
    }

    // return claimed_0, claimed_1
    fn _claim_fees() -> (u256, u256) {
        if !_is_for_pair::read() {
            return (0, 0);
        }

        let pair = IPairDispatcher { contract_address: _token_address::read() };
        let (claimed_0, claimed_1) = pair.claim_fees();
        if or(claimed_0 > 0, claimed_1 > 0) {
            let fees_0 = claimed_0;
            let fees_1 = claimed_1;

            let (token_0, token_1) = pair.tokens();
            let bribe = IBribeDispatcher { contract_address: _internal_bribe::read() };

            if fees_0 > 0 {
                let token_0_ = IERC20Dispatcher { contract_address: token_0 };
                token_0_.approve(_internal_bribe::read(), 0);
                token_0_.approve(_internal_bribe::read(), fees_0);
                bribe.notify_reward_amount(token_0, fees_0);
            }

            if fees_1 > 0 {
                let token_1_ = IERC20Dispatcher { contract_address: token_1 };
                token_1_.approve(_internal_bribe::read(), 0);
                token_1_.approve(_internal_bribe::read(), fees_1);
                bribe.notify_reward_amount(token_1, fees_1);
            }

            ClaimFees(get_caller_address(), claimed_0, claimed_1);
        }

        (claimed_0, claimed_1)
    }

    ///@notice deposit internal
    fn _deposit(amount: u256, account: ContractAddress) {
        ReentrancyGuard::start();
        assert_only_not_emergency();
        _update_reward(account);

        assert(amount > 0, 'Gauge: cannot stake 0');
        _balances::write(account, _balances::read(account) + amount);
        _total_supply::write(_total_supply::read() + amount);

        if _gauge_rewarder::read().is_non_zero() {
            IRewarderDispatcher {
                contract_address: _gauge_rewarder::read()
            }.on_reward(account, account, _balances::read(account));
        }

        _token().transfer_from(account, get_contract_address(), amount);

        Deposit(account, amount);

        ReentrancyGuard::end();
    }

    ///@notice withdraw internal
    fn _withdraw(amount: u256) {
        ReentrancyGuard::start();
        assert_only_not_emergency();

        let caller = get_caller_address();
        _update_reward(caller);

        assert(amount > 0, 'Gauge: cannot withdraw 0');
        let caller_balance = _balances::read(caller);
        assert(caller_balance > 0, 'no balances');

        _total_supply::write(_total_supply::read() - amount);
        _balances::write(caller, caller_balance - amount);

        if _gauge_rewarder::read().is_non_zero() {
            IRewarderDispatcher {
                contract_address: _gauge_rewarder::read()
            }.on_reward(caller, caller, _balances::read(caller));
        }
        _token().transfer(caller, amount);

        Withdraw(caller, amount);

        ReentrancyGuard::end();
    }
}

