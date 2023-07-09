#[contract]
mod GaugeFactory {
    use core::array::ArrayTrait;
    use array::SpanTrait;
    use serde::Serde;
    use option::OptionTrait;
    use hash::LegacyHash;
    use starknet::{ContractAddress, get_caller_address};
    use starknet::class_hash::ClassHash;
    use starknet::syscalls::deploy_syscall;
    use openzeppelin::access::ownable::Ownable;
    use spin_lib::utils::{or};
    use spinswap::interfaces::IPermissionsRegistry::{
        IPermissionsRegistryDispatcher, IPermissionsRegistryDispatcherTrait
    };
    use spinswap::interfaces::IGauge::{IGaugeDispatcher, IGaugeDispatcherTrait};


    #[storage]
    struct Storage {
        _last_gauge: ContractAddress,
        _permissions_registry: ContractAddress,
        _gauge_class_hash: ClassHash,
        _all_gauges: LegacyMap<u256, ContractAddress>, // index, contract
        _all_gauge_index: u256,
    }

    #[constructor]
    fn constructor(permission_registry_: ContractAddress, gauge_class_hash_: ClassHash) {
        Ownable::_transfer_ownership(get_caller_address()); //after deploy ownership to multisig
        _gauge_class_hash::write(gauge_class_hash_);
        _permissions_registry::write(permission_registry_);
    }

    #[external]
    fn set_registry(registry_: ContractAddress) {
        Ownable::assert_only_owner();
        _permissions_registry::write(registry_);
    }

    #[view]
    fn gauges() -> Array<ContractAddress> {
        let mut gauge_array = ArrayTrait::<ContractAddress>::new();
        let gauges_count = _all_gauge_index::read();
        let mut i = 0_u256;
        loop {
            if i >= gauges_count {
                break ();
            }
            gauge_array.append(_all_gauges::read(i));
            i = i + 1;
        };

        gauge_array
    }

    #[view]
    fn length() -> u256 {
        _all_gauge_index::read()
    }

    #[external]
    fn create_gauge(
        reward_token_: ContractAddress,
        ve_: ContractAddress,
        token_: ContractAddress,
        distribution_: ContractAddress,
        internal_bribe_: ContractAddress,
        is_pair_: bool
    ) -> ContractAddress {
        let mut output = ArrayTrait::<felt252>::new();
        reward_token_.serialize(ref output);
        ve_.serialize(ref output);
        token_.serialize(ref output);
        distribution_.serialize(ref output);
        internal_bribe_.serialize(ref output);
        is_pair_.serialize(ref output);

        let mut serialized = output.span();

        let salt = LegacyHash::hash(0, _all_gauge_index::read());

        let (gauge_address, create_result) = deploy_syscall(
            _gauge_class_hash::read(), salt, serialized, false
        )
            .unwrap_syscall();

        append_gauge(gauge_address);
        _last_gauge::write(gauge_address);

        gauge_address
    }

    #[external]
    fn activate_emergency_mode(gauges_: Array<ContractAddress>) {
        assert_only_emergency_council();

        let mut i = 0_usize;
        loop {
            if i >= gauges_.len() {
                break ();
            }

            IGaugeDispatcher { contract_address: *gauges_[i] }.activate_emergency_mode();

            i += 1;
        }
    }

    #[external]
    fn stop_emergency_mode(gauges_: Array<ContractAddress>) {
        assert_only_emergency_council();

        let mut i = 0_usize;
        loop {
            if i >= gauges_.len() {
                break ();
            }

            IGaugeDispatcher { contract_address: *gauges_[i] }.stop_emergency_mode();

            i += 1;
        }
    }

    #[external]
    fn set_rewarder_pid(gauges_: Array<ContractAddress>, pids_: Array<u256>) {
        assert_only_allowed();
        assert(gauges_.len() == pids_.len(), 'length not equal');

        let mut i = 0_usize;
        loop {
            if i >= gauges_.len() {
                break ();
            }

            IGaugeDispatcher { contract_address: *gauges_[i] }.set_rewarder_pid(*pids_[i]);

            i += 1;
        }
    }

    #[external]
    fn set_gauge_rewarder(gauges_: Array<ContractAddress>, rewarder_: Array<ContractAddress>) {
        assert_only_allowed();
        assert(gauges_.len() == rewarder_.len(), 'length not equal');

        let mut i = 0_usize;
        loop {
            if i >= gauges_.len() {
                break ();
            }

            IGaugeDispatcher { contract_address: *gauges_[i] }.set_gauge_rewarder(*rewarder_[i]);

            i += 1;
        }
    }

    #[external]
    fn set_distribution(gauges_: Array<ContractAddress>, distro: ContractAddress) {
        assert_only_allowed();
        let mut i = 0_usize;
        loop {
            if i >= gauges_.len() {
                break ();
            }

            IGaugeDispatcher { contract_address: *gauges_[i] }.set_distribution(distro);

            i += 1;
        }
    }

     #[external]
    fn set_internal_bribe(gauges_: Array<ContractAddress>, int_bribe: Array<ContractAddress>) {
        assert_only_allowed();
        assert(gauges_.len() == int_bribe.len(), 'length not equal');

        let mut i = 0_usize;
        loop {
            if i >= gauges_.len() {
                break ();
            }

            IGaugeDispatcher { contract_address: *gauges_[i] }.set_internal_bribe(*int_bribe[i]);

            i += 1;
        }
    }

    fn assert_only_allowed() {
        assert(
            or(
                Ownable::owner() == get_caller_address(),
                IPermissionsRegistryDispatcher {
                    contract_address: _permissions_registry::read()
                }.has_role('GAUGE_ADMIN', get_caller_address())
            ),
            'ERR: GAUGE_ADMIN'
        )
    }

    fn assert_only_emergency_council() {
        assert(
            get_caller_address() == IPermissionsRegistryDispatcher {
                contract_address: _permissions_registry::read()
            }.emergency_council(),
            'only emergency council'
        )
    }

    fn append_gauge(gauge_: ContractAddress) -> u256 {
        let gauge_index = _all_gauge_index::read();
        _all_gauges::write(gauge_index, gauge_);

        let new_index = gauge_index + 1;
        _all_gauge_index::write(new_index);

        new_index
    }
}
