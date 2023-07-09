#[contract]
mod PermissionsRegistry {
    use core::array::ArrayTrait;
    use zeroable::Zeroable;
    use starknet::{ContractAddress, get_caller_address, get_contract_address};

    #[storage]
    struct Storage {
        /// @notice Control this contract. This is the main multisig 4/6
        _spin_multisig: ContractAddress,
        /// @notice This is the thena team multisig 2/2
        _spin_team_multisig: ContractAddress,
        /// @notice Control emergency functions (set to multisig)
        _emergency_council: ContractAddress,
        /// @notice Check if caller has a role active   (role -> caller -> true/false)
        // _has_role: LegacyMap<(felt252, ContractAddress), bool>,
        _roles_index: u256,
        _roles: LegacyMap<u256, felt252>, // index -> role
        _removed_roles: LegacyMap<felt252, bool>, // role, removed
        _address_to_roles: LegacyMap<(ContractAddress, u256), felt252>, //address, index ->  role
        _address_to_roles_index: LegacyMap<ContractAddress, u256>,
        _role_to_addresses: LegacyMap<(felt252, u256), ContractAddress>,
        _role_to_addresses_index: LegacyMap<felt252, u256>,
        _address_removed_from_role: LegacyMap<(ContractAddress, felt252),
        bool>, // same with has role
    }

    #[event]
    fn RoleAdded(role: felt252) {}
    #[event]
    fn RoleRemoved(role: felt252) {}
    #[event]
    fn RoleSetFor(user: ContractAddress, role: felt252) {}
    #[event]
    fn RoleRemovedFor(user: ContractAddress, role: felt252) {}
    #[event]
    fn SetEmergencyCouncil(council: ContractAddress) {}
    #[event]
    fn SetSpinTeamMultisig(multisig: ContractAddress) {}
    #[event]
    fn SetSpinMultisig(multisig: ContractAddress) {}

    #[constructor]
    fn constructor() {
        let caller = get_caller_address();
        _spin_team_multisig::write(caller);
        _spin_multisig::write(caller);
        _emergency_council::write(caller);

        append_role('GOVERNANCE');

        append_role('VOTER_ADMIN');

        append_role('GAUGE_ADMIN');

        append_role('BRIBE_ADMIN');

        append_role('FEE_MANAGER');
    }

    // -----------------------------------------------------------------------------
    // --------------------------------------------------------------------------------
    //                                 ROLES SETTINGS
    // --------------------------------------------------------------------------------
    // -----------------------------------------------------------------------------

    /// @notice add a new role
    /// @param  role    new role's string (eg role = "GAUGE_ADMIN")
    #[external]
    fn add_role(role_: felt252) {
        assert_only_spin_multisig();
        assert(!check_role(role_), 'is a role');
        append_role(role_);

        RoleAdded(role_);
    }

    #[external]
    fn remove_role(role_: felt252) {
        assert_only_spin_multisig();
        assert(check_role(role_), 'not a role');

        _remove_role(role_);

        RoleRemoved(role_);
    }

    /// @notice Set a role for an address
    #[external]
    fn set_role_for(c: ContractAddress, role_: felt252) {
        assert_only_spin_multisig();
        assert(check_role(role_), 'not a role');
        assert(!has_role(role_, c), 'assigned');

        append_address_to_role(role_, c);

        RoleSetFor(c, role_);
    }

    /// @notice remove a role from an address
    #[external]
    fn remove_role_from(c: ContractAddress, role_: felt252) {
        assert(check_role(role_), 'not a role');
        assert(has_role(role_, c), 'not assigned');

        remove_address_from_role(role_, c);

        RoleRemovedFor(c, role_);
    }

    // ************************************************************
    //                                 VIEW
    // *************************************************************

    #[view]
    fn check_role(role_: felt252) -> bool {
        return !role_removed(role_);
    }

    #[view]
    fn has_role(role_: felt252, user: ContractAddress) -> bool {
        if role_removed(role_) {
            return false;
        }

        return !address_removed_from_role(role_, user);
    }

    #[view]
    fn roles() -> Array<felt252> {
        let index = _roles_index::read();
        let mut array_: Array<felt252> = ArrayTrait::new();
        let mut i = 0_u256;
        loop {
            if i >= index {
                break ();
            }
            let role = _roles::read(i);
            if !role_removed(role) {
                array_.append(role);
            }

            i += 1;
        };
        array_
    }

    #[view]
    fn roles_length() -> u256 {
        _roles_index::read()
    }

    /// @notice Return addresses for a given role
    #[view]
    fn role_to_addresses(role_: felt252) -> Array<ContractAddress> {
        let mut array_ = ArrayTrait::<ContractAddress>::new();
        if role_removed(role_) {
            return array_;
        }

        let index = _role_to_addresses_index::read(role_);
        let mut i = 0_u256;

        loop {
            if i >= index {
                break ();
            }

            let address_ = _role_to_addresses::read((role_, i));
            array_.append(address_);

            i = i + 1;
        };

        array_
    }

    /// @notice Return roles for a given address
    #[view]
    fn address_to_role(user_: ContractAddress) -> Array<felt252> {
        let mut array_ = ArrayTrait::<felt252>::new();
        let index = _address_to_roles_index::read(user_);
        let mut i = 0_u256;

        loop {
            if i >= index {
                break ();
            }

            let role_ = _address_to_roles::read((user_, i));
            if !role_removed(role_) {
                array_.append(role_);
            }

            i = i + 1;
        };

        array_
    }

    //  -----------------------------------------------------------------------------
    // --------------------------------------------------------------------------------
    //                             EMERGENCY AND MULTISIG
    // --------------------------------------------------------------------------------
    // -----------------------------------------------------------------------------

    /// @notice set emergency counsil
    /// @param _new new address  
    #[external]
    fn set_emergency_council(new_: ContractAddress) {
        let caller = get_caller_address();
        assert(caller == _emergency_council::read() | caller == _spin_multisig::read(), 'not allowed');
        assert(new_.is_non_zero(), 'zero address');
        assert(new_ != _emergency_council::read(), 'same addr');

        _emergency_council::write(new_);

        SetEmergencyCouncil(new_);
    }

        /// @notice set thena team multisig
    /// @param _new new address
    #[external]
    fn set_spin_team_multisig(new_: ContractAddress)  {
        let spin_team_multisig = _spin_team_multisig::read();
        assert(get_caller_address() == spin_team_multisig, 'not allowed');
        assert(new_.is_non_zero(), 'zero address');
        assert(new_ != spin_team_multisig, 'same address');

        _spin_team_multisig::write(new_);

        SetSpinTeamMultisig(new_);
    }

     #[external]
    fn set_spin_multisig(new_: ContractAddress)  {
        let spin_multisig = _spin_multisig::read();
        assert(get_caller_address() == spin_multisig, 'not allowed');
        assert(new_.is_non_zero(), 'zero address');
        assert(new_ != spin_multisig, 'same address');

        _spin_multisig::write(new_);

        SetSpinMultisig(new_);
    }

    fn assert_only_spin_multisig() {
        assert(get_caller_address() == _spin_multisig::read(), 'only spin multisig');
    }

    fn append_role(role_: felt252) {
        if role_removed(role_) {
            readd_role(role_);
        } else {
            let roles_index = _roles_index::read();
            _roles::write(roles_index, role_);

            let new_index = roles_index + 1;
            _roles_index::write(new_index);
        }
    }

    fn role_removed(role_: felt252) -> bool {
        _removed_roles::read(role_)
    }

    fn _remove_role(role_: felt252) {
        _removed_roles::write(role_, true);
    }

    fn readd_role(role_: felt252) {
        _removed_roles::write(role_, false);
    }

    fn append_address_to_role(role_: felt252, address_: ContractAddress) {
        if address_removed_from_role(role_, address_) {
            readd_address_to_role(role_, address_);
        } else {
            let role_index = _role_to_addresses_index::read(role_);
            _role_to_addresses::write((role_, role_index), address_);
            let address_index = _address_to_roles_index::read(address_);
            _address_to_roles::write((address_, address_index), role_);

            let new_role_index = role_index + 1;
            _role_to_addresses_index::write(role_, new_role_index);
            let new_address_index = address_index + 1;
            _address_to_roles_index::write(address_, new_address_index);
        }
    }

    fn remove_address_from_role(role_: felt252, address_: ContractAddress) {
        _address_removed_from_role::write((address_, role_), true);
    }

    fn readd_address_to_role(role_: felt252, address_: ContractAddress) {
        _address_removed_from_role::write((address_, role_), false);
    }

    fn address_removed_from_role(role_: felt252, address_: ContractAddress) -> bool {
        _address_removed_from_role::read((address_, role_))
    }
}
