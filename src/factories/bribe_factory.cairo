#[contract]
mod BribeFactory {
    use core::array::ArrayTrait;
    use array::SpanTrait;
    use serde::Serde;
    use core::zeroable::Zeroable;
    use option::OptionTrait;
    use hash::LegacyHash;
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use starknet::class_hash::ClassHash;
    use starknet::syscalls::deploy_syscall;
    use openzeppelin::access::ownable::Ownable;
    use spinswap::interfaces::IPermissionsRegistry::{
        IPermissionsRegistryDispatcher, IPermissionsRegistryDispatcherTrait
    };
    use spinswap::interfaces::IBribe::{IBribeDispatcher, IBribeDispatcherTrait};

    #[storage]
    struct Storage {
        _last_bribe: ContractAddress,
        _all_bribes: LegacyMap<u256, ContractAddress>, // index, contract
        _all_bribe_index: u256,
        _all_default_reward_tokens: LegacyMap<u256, ContractAddress>,
        _all_default_reward_tokens_index: u256,
        _removed_defalut_reward_tokens: LegacyMap<ContractAddress, bool>,
        _voter: ContractAddress,
        _bribe_class_hash: ClassHash,
        _permissions_registry: ContractAddress
    }

    #[constructor]
    fn constructor(
        bribe_class_hash_: ClassHash, voter_: ContractAddress, permission_registry_: ContractAddress
    ) {
        _bribe_class_hash::write(bribe_class_hash_);
        Ownable::_transfer_ownership(get_caller_address());
        _voter::write(voter_);
        _permissions_registry::write(permission_registry_);
    // can append some default reward token
    }

    #[external]
    fn create_bribe(
        owner_: ContractAddress,
        token_0_: ContractAddress,
        token_1_: ContractAddress,
        type_: felt252
    ) -> ContractAddress {
        let caller = get_caller_address();
        assert(caller == _voter::read() | caller == Ownable::owner(), 'only voter');

        let mut output = ArrayTrait::<felt252>::new();
        Ownable::owner().serialize(ref output);
        _voter::read().serialize(ref output);
        get_contract_address().serialize(ref output);
        type_.serialize(ref output);

        let mut serialized = output.span();

        let salt = LegacyHash::hash(0, _all_bribe_index::read());

        let (bribe_address, create_result) = deploy_syscall(
            _bribe_class_hash::read(), salt, serialized, false
        )
            .unwrap_syscall();

        let bribe = IBribeDispatcher { contract_address: bribe_address };

        if token_0_.is_non_zero() {
            bribe.add_reward_token(token_0_);
        }
        if token_1_.is_non_zero() {
            bribe.add_reward_token(token_1_);
        }

        bribe.add_reward_tokens(default_reward_tokens());

        _last_bribe::write(bribe_address);
        append_bribe(bribe_address);

        bribe_address
    }


    //  -----------------------------------------------------------------------------
    // --------------------------------------------------------------------------------
    // --------------------------------------------------------------------------------
    //                                 ONLY OWNER
    // --------------------------------------------------------------------------------
    // --------------------------------------------------------------------------------
    // ----------------------------------------------------------------------------- 

    /// @notice set the bribe factory voter
    #[external]
    fn set_voter(voter_: ContractAddress) {
        assert_only_owner();
        assert(voter_.is_non_zero(), 'zero address');

        _voter::write(voter_);
    }


    /// @notice set the bribe factory permission registry
    #[external]
    fn set_permissions_registry(perm_reg_: ContractAddress) {
        assert_only_owner();
        assert(perm_reg_.is_non_zero(), 'zero address');

        _permissions_registry::write(perm_reg_);
    }

    /// @notice set the bribe factory permission registry
    #[external]
    fn push_default_reward_token(token_: ContractAddress) {
        assert_only_owner();
        assert(token_.is_non_zero(), 'zero address');

        append_reward_token(token_);
    }

    /// @notice set the bribe factory permission registry
    #[external]
    fn remove_default_reward_token(token_: ContractAddress) {
        assert_only_owner();
        assert(token_.is_non_zero(), 'zero address');

        _removed_defalut_reward_tokens::write(token_, true);
    }

    //  -----------------------------------------------------------------------------
    // --------------------------------------------------------------------------------
    // --------------------------------------------------------------------------------
    //                                 ONLY OWNER or BRIBE ADMIN
    // --------------------------------------------------------------------------------
    // --------------------------------------------------------------------------------
    // ----------------------------------------------------------------------------- 

    /// @notice Add a reward token to a given bribe
    #[external]
    fn add_reward_to_bribe(token_: ContractAddress, bribe_: ContractAddress) {
        assert_only_allowed();
        IBribeDispatcher { contract_address: bribe_ }.add_reward_token(token_);
    }

    /// @notice Add multiple reward token to a given bribe
    #[external]
    fn add_rewards_to_bribe(token_: Array<ContractAddress>, bribe_: ContractAddress) {
        assert_only_allowed();
        IBribeDispatcher { contract_address: bribe_ }.add_reward_tokens(token_);
    }

    /// @notice Add a reward token to given bribes
    #[external]
    fn add_reward_to_bribes(token_: ContractAddress, bribes_: Array<ContractAddress>) {
        assert_only_allowed();
        let mut i = 0_usize;
        loop {
            if i >= bribes_.len() {
                break ();
            }
            IBribeDispatcher { contract_address: *bribes_[i] }.add_reward_token(token_);
            i = i + 1;
        }
    }

    #[external]
    fn set_bribe_voter(bribes_: Array<ContractAddress>, voter_: ContractAddress) {
        assert_only_allowed();
        let mut i = 0_usize;
        loop {
            if i >= bribes_.len() {
                break ();
            }

            IBribeDispatcher { contract_address: *bribes_[i] }.set_voter(voter_);
            i = i + 1;
        }
    }

    /// @notice set a new minter in given bribes
    #[external]
    fn set_bribe_minter(bribes_: Array<ContractAddress>, minter_: ContractAddress) {
        assert_only_allowed();
        let mut i = 0_usize;
        loop {
            if i >= bribes_.len() {
                break ();
            }

            IBribeDispatcher { contract_address: *bribes_[i] }.set_minter(minter_);
            i = i + 1;
        }
    }

    #[external]
    fn set_bribe_owner(bribes_: Array<ContractAddress>, owner_: ContractAddress) {
        assert_only_allowed();
        let mut i = 0_usize;
        loop {
            if i >= bribes_.len() {
                break ();
            }

            IBribeDispatcher { contract_address: *bribes_[i] }.set_owner(owner_);
            i = i + 1;
        }
    }


    /// @notice recover an ERC20 from bribe contracts.
    #[external]
    fn recover_erc20_from(
        bribes_: Array<ContractAddress>, tokens_: Array<ContractAddress>, amounts_: Array<u256>
    ) {
        assert_only_allowed();
        assert(bribes_.len() == tokens_.len(), 'mismatch len');
        assert(tokens_.len() == amounts_.len(), 'mismatch len');

        let mut i = 0_usize;
        loop {
            if i >= bribes_.len() {
                break ();
            }

            IBribeDispatcher {
                contract_address: *bribes_[i]
            }.emergency_recover_erc20(*tokens_[i], *amounts_[i]);
            i = i + 1;
        }
    }

    /// @notice recover an ERC20 from bribe contracts and update. 
    #[external]
    fn recover_erc20_and_update_data(
        bribes_: Array<ContractAddress>, tokens_: Array<ContractAddress>, amounts_: Array<u256>
    ) {
        assert_only_allowed();
        assert(bribes_.len() == tokens_.len(), 'mismatch len');
        assert(tokens_.len() == amounts_.len(), 'mismatch len');

        let mut i = 0_usize;
        loop {
            if i >= bribes_.len() {
                break ();
            }

            IBribeDispatcher {
                contract_address: *bribes_[i]
            }.emergency_recover_erc20(*tokens_[i], *amounts_[i]);
            i = i + 1;
        }
    }

    fn permission_registry() -> IPermissionsRegistryDispatcher {
        IPermissionsRegistryDispatcher { contract_address: _permissions_registry::read() }
    }

    fn append_bribe(bribe_: ContractAddress) -> u256 {
        let bribe_index = _all_bribe_index::read();
        _all_bribes::write(bribe_index, bribe_);

        let new_index = bribe_index + 1;
        _all_bribe_index::write(new_index);

        new_index
    }

    fn append_reward_token(reward_token_: ContractAddress) {
        if _removed_defalut_reward_tokens::read(reward_token_) {
            _removed_defalut_reward_tokens::write(reward_token_, false);
        } else {
            let token_index = _all_default_reward_tokens_index::read();
            _all_default_reward_tokens::write(token_index, reward_token_);

            let new_index = token_index + 1;
            _all_default_reward_tokens_index::write(new_index);
        }
    }

    fn default_reward_tokens() -> Array<ContractAddress> {
        let index_ = _all_default_reward_tokens_index::read();
        let mut array_: Array<ContractAddress> = ArrayTrait::new();
        let mut i = 0_u256;
        loop {
            if i >= index_ {
                break ();
            }

            let reward_token_address = _all_default_reward_tokens::read(i);
            if !_removed_defalut_reward_tokens::read(reward_token_address) {
                array_.append(_all_default_reward_tokens::read(i));
            }

            i += 1;
        };
        array_
    }

    fn assert_only_owner() {
        Ownable::assert_only_owner()
    }

    fn assert_only_allowed() {
        let caller = get_caller_address();

        assert(
            Ownable::owner() == caller | permission_registry().has_role('BRIBE_ADMIN', caller),
            'ERR: BRIBE_ADMIN'
        )
    }
}
