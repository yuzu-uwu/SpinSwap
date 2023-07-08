#[contract]
mod BribeFactory {
    use core::array::ArrayTrait;
    use array::SpanTrait;
    use serde::Serde;
    use option::OptionTrait;
    use hash::LegacyHash;
    use starknet::{ContractAddress, get_caller_address};
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
        _voter: ContractAddress,
        _bribe_class_hash: ClassHash,
        _permissions_registry: ContractAddress
    }

      #[constructor]
    fn cnstructor(bribe_class_hash_: ClassHash, voter_: ContractAddress, permission_registry_: ContractAddress) {
        _bribe_class_hash::write(bribe_class_hash_);
        Ownable::_transfer_ownership(get_caller_address());
        _voter::write(voter_);
        _permissions_registry::write(permission_registry_);

        // can append some default reward token
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

    fn append_reward_token(reward_token_: ContractAddress) -> u256 {
        let token_index = _all_default_reward_tokens_index::read();
        _all_default_reward_tokens::write(token_index, reward_token_);

        let new_index = token_index + 1;
        _all_default_reward_tokens_index::write(new_index);

        new_index
    }
}
