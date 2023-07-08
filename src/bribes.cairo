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

#[derive(Copy, Drop, Serde)]
struct Reward {
    period_finish: u128,
    rewards_per_epoch: u256,
    last_updatetime: u128,
}

impl RewardStorageAccess of StorageAccess<Reward> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult::<Reward> {
        let period_finish = StorageAccess::read(address_domain, base)?;

        let rewards_per_epoch_base = storage_base_address_from_felt252(
            storage_address_from_base_and_offset(base, 1_u8).into()
        );
        let rewards_per_epoch = StorageAccess::read(address_domain, rewards_per_epoch_base)?;

        let last_updatetime_base = storage_base_address_from_felt252(
            storage_address_from_base_and_offset(base, 2_u8).into()
        );
        let last_updatetime = StorageAccess::read(address_domain, last_updatetime_base)?;

        Result::Ok(Reward { period_finish, rewards_per_epoch, last_updatetime })
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: Reward) -> SyscallResult::<()> {
        StorageAccess::write(address_domain, base, value.period_finish)?;

        let rewards_per_epoch_base = storage_base_address_from_felt252(
            storage_address_from_base_and_offset(base, 1_u8).into()
        );
        StorageAccess::write(address_domain, rewards_per_epoch_base, value.rewards_per_epoch)?;

        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 2_u8),
            value.last_updatetime.into()
        )
    }
}


#[contract]
mod Bribe {
    use core::array::ArrayTrait;
    use zeroable::Zeroable;
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use openzeppelin::security::reentrancyguard::ReentrancyGuard;
    use openzeppelin::access::ownable::Ownable;
    use openzeppelin::token::erc20::interface::{IERC20, IERC20DispatcherTrait, IERC20Dispatcher};
    use spin_lib::utils::{
        get_block_timestamp_u128, get_block_number_u128, and_and, or, u128_to_u256
    };
    use super::Reward;
    use spinswap::interfaces::IVoter::{IVoterDispatcher, IVoterDispatcherTrait};
    use spinswap::interfaces::IMinter::{IMinterDispatcher, IMinterDispatcherTrait};
    use spinswap::interfaces::IVotingEscrow::{
        IVotingEscrowDispatcher, IVotingEscrowDispatcherTrait
    };

    // 7 * 86400
    const WEEK: u128 = 604800;

    #[storage]
    struct Storage {
        _first_bribe_timestamp: u128,
        _reward_data: LegacyMap<(ContractAddress, u128),
        Reward>, // token -> startTimestamp -> Reward
        _is_reward_token: LegacyMap<ContractAddress, bool>,
        _reward_tokens_count: u256,
        _voter_contract: ContractAddress,
        _minter_contract: ContractAddress,
        _ve_contract: ContractAddress,
        _bribe_factory: ContractAddress,
        _type: felt252,
        _user_timestamp: LegacyMap<(ContractAddress, ContractAddress), u128>,
        _total_supply: LegacyMap<u128, u256>,
        //owner -> timestamp -> amount
        _balances: LegacyMap<(ContractAddress, u128), u256>
    }

    #[event]
    fn RewardAdded(reward_token: ContractAddress, reward: u256, start_timestamp: u128) {}

    #[event]
    fn Staked(token_id: u256, amount: u256) {}

    #[event]
    fn Withdrawn(token_id: u256, amount: u256) {}

    #[event]
    fn RewardPaid(user: ContractAddress, rewards_token: ContractAddress, reward: u256) {}

    #[event]
    fn Recovered(token: ContractAddress, amount: u256) {}

    #[constructor]
    fn cnstructor(
        owner_: ContractAddress,
        voter_: ContractAddress,
        bribe_factory_: ContractAddress,
        type_: felt252
    ) {
        // todo: _bribeFactory
        assert(voter_.is_non_zero(), 'voter can not zero');

        let voter = IVoterDispatcher { contract_address: voter_ };

        _voter_contract::write(voter_);
        _bribe_factory::write(bribe_factory_);
        _ve_contract::write(voter.ve());
        _minter_contract::write(voter.minter());

        _first_bribe_timestamp::write(0);

        assert(_minter_contract::read().is_non_zero(), 'minter can not zero');
        _type::write(type_);

        Ownable::_transfer_ownership(owner_);
    }

    // ========== VIEWS ==========

    /// @notice get the current epoch 
    #[view]
    fn get_epoch_start() -> u128 {
        _minter().active_period()
    }


    /// @notice get next epoch (where bribes are saved)
    #[view]
    fn get_next_epoch_start() -> u128 {
        get_epoch_start() + WEEK
    }

    /// @notice get the length of the reward tokens
    #[view]
    fn rewards_list_length() -> u256 {
        _reward_tokens_count::read()
    }

    /// @notice get the last totalSupply (total votes for a pool)
    #[view]
    fn total_supply() -> u256 {
        let current_epoch_start = _minter().active_period();
        _total_supply::read(current_epoch_start)
    }

    /// @notice get a totalSupply given a timestamp
    #[view]
    fn balance_of_at(token_id: u256, timestamp_: u128) -> u256 {
        let _owner = _ve().owner_of(token_id);
        _balances::read((_owner, timestamp_))
    }

    /// @notice get last deposit available given a tokenID
    #[view]
    fn balance_of(token_id: u256) -> u256 {
        let timestamp = get_next_epoch_start();
        let owner = _ve().owner_of(token_id);
        _balances::read((owner, timestamp))
    }

    /// @notice get the balance of an owner in the current epoch
    #[view]
    fn balance_of_owner(owner_: ContractAddress) -> u256 {
        let timestamp = get_next_epoch_start();
        _balances::read((owner_, timestamp))
    }

    /// @notice get the balance of a owner given a timestamp
    #[view]
    fn balance_of_owner_at(owner_: ContractAddress, timestamp_: u128) -> u256 {
        _balances::read((owner_, timestamp_))
    }

    /// @notice get the rewards for token
    #[view]
    fn reward_per_token(rewards_token_: ContractAddress, timestamp_: u128) -> u256 {
        if _total_supply::read(timestamp_) == 0 {
            return _reward_data::read((rewards_token_, timestamp_)).rewards_per_epoch;
        }
        return _reward_data::read((rewards_token_, timestamp_)).rewards_per_epoch
            * 1_000_000_000_000_000_000_u256
            / _total_supply::read(timestamp_);
    }

    /// @notice read earned amounts given an address and the reward token
    #[view]
    fn earned(owner_: ContractAddress, reward_token_: ContractAddress) -> u256 {
        let (reward, user_last_time) = earned_with_timestamp(owner_, reward_token_);
        reward
    }

    /// @notice Read earned amount given a tokenID and _rewardToken
    #[view]
    fn earned_by_token_id(token_id: u256, reward_token_: ContractAddress) -> u256 {
        let owner = _ve().owner_of(token_id);
        let (reward, user_last_time) = earned_with_timestamp(owner, reward_token_);
        reward
    }


    fn _ve() -> IVotingEscrowDispatcher {
        IVotingEscrowDispatcher { contract_address: _ve_contract::read() }
    }

    fn _minter() -> IMinterDispatcher {
        IMinterDispatcher { contract_address: _minter_contract::read() }
    }


    /// @notice Read earned amount given address and reward token, returns the rewards and the last user timestamp (used in case user do not claim since 50+epochs)
    fn earned_with_timestamp(
        owner_: ContractAddress, reward_token_: ContractAddress
    ) -> (u256, u128) {
        let mut k = 0_usize;
        let mut reward = 0;
        let end_timestamp = _minter().active_period();
        let mut user_last_time = _user_timestamp::read((owner_, reward_token_));

        if end_timestamp == user_last_time {
            return (0, user_last_time);
        }

        // if user first time then set it to first bribe - week to avoid any timestamp problem
        if user_last_time < _first_bribe_timestamp::read() {
            user_last_time = _first_bribe_timestamp::read() - WEEK;
        }

        loop {
            if k >= 50 {
                break ();
            }

            if user_last_time == end_timestamp {
                // if we reach the current epoch, exit
                break ();
            }
            reward += _earned(owner_, reward_token_, user_last_time);
            user_last_time += WEEK;
            k += 1;
        };
        (reward, user_last_time)
    }

    /// @notice get the earned rewards
    fn _earned(owner_: ContractAddress, reward_token_: ContractAddress, timestamp_: u128) -> u256 {
        let balance = balance_of_owner_at(owner_, timestamp_);
        if balance == 0 {
            return 0;
        } else {
            let reward_per_token = reward_per_token(reward_token_, timestamp_);
            let rewards = reward_per_token * balance / 1_000_000_000_000_000_000_u256;
            return rewards;
        }
    }

    // ========== MUTATIVE FUNCTIONS ==========

    /// @notice User votes deposit
    /// @dev    called on voter.vote() or voter.poke()
    ///         we save into owner "address" and not "tokenID". 
    ///         Owner must reset before transferring token
    #[external]
    fn _deposit(amount: u256, token_id: u256) {
        ReentrancyGuard::start();

        assert(amount > 0, 'Cannot stake 0');
        _assert_only_voter();

        let start_timestamp = _minter().active_period() + WEEK;
        let old_supply = _total_supply::read(start_timestamp);
        let owner = _ve().owner_of(token_id);
        let last_balance = _balances::read((owner, start_timestamp));

        _total_supply::write(start_timestamp, old_supply + amount);
        _balances::write((owner, start_timestamp), last_balance + amount);

        Staked(token_id, amount);

        ReentrancyGuard::end();
    }

    /// @notice User votes withdrawal 
    /// @dev    called on voter.reset()
    #[external]
    fn _withdraw(amount: u256, token_id: u256) {
        ReentrancyGuard::start();

        assert(amount > 0, 'Cannot withdraw 0');
        _assert_only_voter();

        let start_timestamp = _minter().active_period() + WEEK;
        let owner = _ve().owner_of(token_id);

        // incase of bribe contract reset in gauge proxy
        if amount <= _balances::read((owner, start_timestamp)) {
            let old_supply = _total_supply::read(start_timestamp);
            let old_balance = _balances::read((owner, start_timestamp));

            _total_supply::write(start_timestamp, old_supply - amount);
            _balances::write((owner, start_timestamp), old_balance - amount);

            Withdrawn(token_id, amount);
        }

        ReentrancyGuard::end();
    }

    /// @notice Claim the TOKENID rewards
    #[external]
    fn get_reward(token_id: u256, tokens: Array<ContractAddress>) {
        ReentrancyGuard::start();

        assert(
            _ve().is_approved_or_owner(get_caller_address(), token_id),
            'caller have no token access'
        );
        let owner = _ve().owner_of(token_id);

        _get_reward(owner, tokens);

        ReentrancyGuard::end();
    }

    /// @notice Claim the rewards given msg.sender
    #[external]
    fn get_reward_by_caller(tokens: Array<ContractAddress>) {
        ReentrancyGuard::start();

        let owner = get_caller_address();
        _get_reward(owner, tokens);

        ReentrancyGuard::end();
    }


    /// @notice Claim rewards from voter
    #[external]
    fn get_reward_for_owner(token_id: u256, tokens: Array<ContractAddress>) {
        ReentrancyGuard::start();

        _assert_only_voter();
        let owner = _ve().owner_of(token_id);
        _get_reward(owner, tokens);

        ReentrancyGuard::end();
    }

    /// @notice Claim rewards from voter
    #[external]
    fn get_reward_for_address(owner_: ContractAddress, tokens: Array<ContractAddress>) {
        ReentrancyGuard::start();

        _assert_only_voter();
        _get_reward(owner_, tokens);

        ReentrancyGuard::end();
    }

    /// @notice Notify a bribe amount
    /// @dev    Rewards are saved into NEXT EPOCH mapping. 
    #[external]
    fn notify_reward_amount(rewards_token_: ContractAddress, reward: u256) {
        ReentrancyGuard::start();

        assert(_is_reward_token::read(rewards_token_), 'reward token not verified');
        IERC20Dispatcher {
            contract_address: rewards_token_
        }.transfer_from(get_caller_address(), get_contract_address(), reward);

        let start_timestamp = _minter().active_period()
            + WEEK; //period points to the current thursday. Bribes are distributed from next epoch (thursday)
        if _first_bribe_timestamp::read() == 0 {
            _first_bribe_timestamp::write(start_timestamp);
        }

        let last_reward = _reward_data::read((rewards_token_, start_timestamp)).rewards_per_epoch;

        let reward_data = Reward {
            rewards_per_epoch: last_reward + reward,
            last_updatetime: get_block_timestamp_u128(),
            period_finish: start_timestamp + WEEK
        };

        _reward_data::write((rewards_token_, start_timestamp), reward_data);

        RewardAdded(rewards_token_, reward, start_timestamp);
        ReentrancyGuard::end();
    }


    fn _get_reward(owner_: ContractAddress, tokens: Array<ContractAddress>) {
        let mut user_last_time = 0_u128;
        let mut reward = 0_u256;
        let owner = owner_;

        let mut i = 0_usize;
        loop {
            if i >= tokens.len() {
                break ();
            }

            let reward_token = *tokens[i];
            let (reward_, user_last_time_) = earned_with_timestamp(owner, reward_token);

            reward = reward_;
            user_last_time = user_last_time_;

            if reward > 0 {
                IERC20Dispatcher { contract_address: reward_token }.transfer(owner, reward);
                RewardPaid(owner, reward_token, reward);
            }
            _user_timestamp::write((owner, reward_token), user_last_time);

            i += 1;
        };
    }

    // ========== RESTRICTED FUNCTIONS ==========
    /// @notice add rewards tokens
    #[external]
    fn add_rewards_tokens(rewards_token_: Array<ContractAddress>) {
        _assert_only_allowed();
        let mut i = 0_usize;
        loop {
            if i >= rewards_token_.len() {
                break ();
            }
            _add_reward(*rewards_token_[i]);
            i += 1;
        }
    }

    /// @notice add a single reward token
    #[external]
    fn add_reward_token(rewards_token_: ContractAddress) {
        _assert_only_allowed();
        _add_reward(rewards_token_);
    }

    /// @notice Recover some ERC20 from the contract and updated given bribe
    #[external]
    fn recover_erc20_and_update_data(token_address: ContractAddress, token_amount: u256) {
        _assert_only_allowed();

        let start_timestamp = _minter().active_period() + WEEK;
        let last_reward = _reward_data::read((token_address, start_timestamp)).rewards_per_epoch;

        let mut last_reward_data = _reward_data::read((token_address, start_timestamp));

        last_reward_data.rewards_per_epoch = last_reward - token_amount;
        last_reward_data.last_updatetime = get_block_timestamp_u128();

        _reward_data::write((token_address, start_timestamp), last_reward_data);

        IERC20Dispatcher {
            contract_address: token_address
        }.transfer(Ownable::owner(), token_amount);
        Recovered(token_address, token_amount);
    }

    /// @notice Recover some ERC20 from the contract.
    /// @dev    Be careful --> if called then getReward() at last epoch will fail because some reward are missing! 
    ///         Think about calling recoverERC20AndUpdateData()
    #[external]
    fn emergency_recover_erc20(token_address: ContractAddress, token_amount: u256) {
        _assert_only_allowed();

        let token = IERC20Dispatcher { contract_address: token_address };
        assert(token_amount <= token.balance_of(get_contract_address()), 'out of balance');
        token.transfer(Ownable::owner(), token_amount);

        Recovered(token_address, token_amount);
    }

    /// @notice Set a new voter
    #[external]
    fn set_voter(voter_: ContractAddress) {
        _assert_only_allowed();

        _voter_contract::write(voter_);
    }

    /// @notice Set a new minter
    #[external]
    fn set_minter(minter_: ContractAddress) {
        _assert_only_allowed();

        _minter_contract::write(minter_);
    }

    /// @notice Set a new owner
    #[external]
    fn set_owner(owner_: ContractAddress) {
        _assert_only_allowed();
        assert(owner_.is_non_zero(), 'cannot set a zero address');
        Ownable::_transfer_ownership(owner_);
    }

    fn _add_reward(rewards_token_: ContractAddress) {
        if !_is_reward_token::read(rewards_token_) {
            _is_reward_token::write(rewards_token_, true);
            _reward_tokens_count::write(_reward_tokens_count::read() + 1);
        }
    }

    //  ========== assert ========== 
    fn _assert_only_voter() {
        assert(get_caller_address() == _voter_contract::read(), 'only voter');
    }

    fn _assert_only_allowed() {
        let caller = get_caller_address();

        assert(
            or(caller == Ownable::owner(), caller == _bribe_factory::read()),
            'permission is denied!'
        );
    }
}
