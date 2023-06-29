use core::traits::Into;
#[contract]
mod PairFactory {
    use core::array::ArrayTrait;
    use core::zeroable::Zeroable;
    use traits::Into;
    use starknet::{
        ContractAddress, contract_address_to_felt252, get_caller_address, get_contract_address
    };
    use starknet::class_hash::ClassHash;
        use starknet::syscalls::deploy_syscall;
    use integer::u256_from_felt252;
    use hash::LegacyHash;

    struct Storage {
        _is_paused: bool,
        _pauser: ContractAddress,
        _pending_pauser: ContractAddress,
        _stable_fee: u256,
        _volatile_fee: u256,
        _staking_nft_fee: u256,
        _max_referral_fee: u256, // 1200, 12%
        _max_fee: u256, // 25, 0.25
        _fee_manager: ContractAddress,
        _pending_fee_manager: ContractAddress,
        _dibs: ContractAddress, // referral fee handler
        _staking_fee_handler: ContractAddress, //  // staking fee handler
        _get_pair: LegacyMap<(ContractAddress, ContractAddress, bool), ContractAddress>,
        _all_pairs: LegacyMap<u256, ContractAddress>, // index, contract
        _all_pair_index: u256,
        _is_pair: LegacyMap<ContractAddress,
        bool>, // // simplified check if its a pair, given that `stable` flag might not be available in peripherals
        _pair_class_hash: ClassHash,
        _temp0: ContractAddress, // temp for create pair contract
        _temp1: ContractAddress,
        _temp: bool,
    }

    #[event]
    fn PairCreated(
        token0: ContractAddress,
        token1: ContractAddress,
        stable: bool,
        pair: ContractAddress,
        pair_index: u256
    ) {}

    #[constructor]
    fn cnstructor(pair_class_hash_: ClassHash) {
        let caller = get_caller_address();

        _pauser::write(caller);
        _is_paused::write(false);
        _fee_manager::write(caller);
        _stable_fee::write(4); // 0.04%
        _volatile_fee::write(18); // 0.18%
        _staking_nft_fee::write(3000); // 30% of stable/volatileFee

        _max_referral_fee::write(1200); //12%
        _max_fee::write(25); // 0.25%

        _pair_class_hash::write(pair_class_hash_);
    }

    #[view]
    fn all_pairs_length() -> u256 {
        _all_pair_index::read()
    }

    #[view]
    fn is_pair(pair_: ContractAddress) -> bool {
        _is_pair::read(pair_)
    }

    #[view]
    fn pairs() -> Array<ContractAddress> {
        let pair_index = _all_pair_index::read();
        let mut pairs_array: Array<ContractAddress> = ArrayTrait::new();
        let mut i = 0_u256;
        loop {
            if i >= pair_index {
                break ();
            }
            pairs_array.append(_all_pairs::read(i));
            i += 1;
        };
        pairs_array
    }

    #[view]
    fn pair_by_index(pair_index_: u256) -> ContractAddress {
        _all_pairs::read(pair_index_)
    }

    #[external]
    fn set_pauser(pauser_: ContractAddress) {
        assert_only_pauser();
        _pending_pauser::write(pauser_);
    }

    #[external]
    fn accept_pauser() {
        assert(get_caller_address() == _pending_pauser::read(), 'only pending pauser');
        _pauser::write(_pending_pauser::read());
    }

    #[external]
    fn set_pause(state: bool) {
        assert_only_pauser();
        _is_paused::write(state);
    }

    #[external]
    fn set_fee_manager(fee_manager_: ContractAddress) {
        assert_only_fee_manager();
        _pending_fee_manager::write(fee_manager_);
    }

    #[external]
    fn accept_fee_manager() {
        assert(get_caller_address() == _pending_fee_manager::read(), 'only pending fee manager');
        _fee_manager::write(_pending_fee_manager::read());
    }

    #[external]
    fn set_staking_fees(new_fee_: u256) {
        assert_only_fee_manager();
        assert(new_fee_ <= 3000, 'cannot large than 3000');
        _staking_nft_fee::write(new_fee_);
    }

    #[external]
    fn set_staking_fee_address(fee_handler: ContractAddress) {
        assert_only_fee_manager();
        assert(fee_handler.is_non_zero(), 'zero addr');
        _staking_fee_handler::write(fee_handler)
    }

    #[external]
    fn set_dibs(dibs_: ContractAddress) {
        assert_only_fee_manager();
        assert(dibs_.is_non_zero(), 'zero address');
        _dibs::write(dibs_);
    }

    #[external]
    fn set_referral_fee(ref_fee: u256) {
        assert_only_fee_manager();
        _max_referral_fee::write(ref_fee);
    }

    #[external]
    fn set_fee(stable_: bool, fee_: u256) {
        assert_only_fee_manager();
        assert(fee_ <= _max_fee::read(), 'fee too high');
        assert(fee_ != 0, 'fee must be nonzero');
        if stable_ {
            _stable_fee::write(fee_);
        } else {
            _volatile_fee::write(fee_);
        }
    }

    #[view]
    fn get_fee(stable_: bool) -> u256 {
        if stable_ {
            return _stable_fee::read();
        }
        _volatile_fee::read()
    }

    #[view]
    fn pair_class_hash() -> ClassHash {
        _pair_class_hash::read()
    }

    #[view]
    fn get_initializable() -> (ContractAddress, ContractAddress, bool) {
        (_temp0::read(), _temp1::read(), _temp::read())
    }

    #[view]
    fn get_pair(token_a: ContractAddress, token_b: ContractAddress, stable_: bool) -> ContractAddress {
        _get_pair::read((token_a, token_b, stable_))
    }

    #[external]
    fn create_pair(
        token_a: ContractAddress, token_b: ContractAddress, stable_: bool
    ) -> ContractAddress {
        assert(token_a != token_b, 'Pair: IDENTICAL_ADDRESSES');
        let (token_0, token_1) = sort_token(token_a, token_b);
        assert(token_0.is_non_zero(), 'zero address');
        assert(
            _get_pair::read((token_0, token_1, stable_)).is_zero(), 'Pair: PAIR_EXISTS'
        ); // Pair: PAIR_EXISTS - single check is sufficient
        let salt = LegacyHash::hash(token_0.into(), token_1);
        let salt = LegacyHash::hash(salt, stable_);

        _temp0::write(token_0);
        _temp1::write(token_1);
        _temp::write(stable_);


        let empyt_array = ArrayTrait::<felt252>::new().span();

        let (pair_address, deploy_data) = deploy_syscall(_pair_class_hash::read(), salt, empyt_array, false).unwrap_syscall();
        _get_pair::write((token_0, token_1, stable_), pair_address);
        _get_pair::write((token_1, token_0, stable_), pair_address); // populate mapping in the reverse direction
        let new_index = append_pair(pair_address);
        _is_pair::write(pair_address, true);
        
        PairCreated(token_0, token_1, stable_, pair_address, new_index);
        pair_address
    }

    fn append_pair(pair_: ContractAddress) -> u256 {
        let pair_index = _all_pair_index::read();
        _all_pairs::write(pair_index, pair_);

        let new_index = pair_index + 1;
        _all_pair_index::write(new_index);

        new_index
    }

    fn sort_token(
        token_a: ContractAddress, token_b: ContractAddress
    ) -> (ContractAddress, ContractAddress) {
        if u256_from_felt252(
            contract_address_to_felt252(token_a)
        ) < u256_from_felt252(contract_address_to_felt252(token_b)) {
            return (token_a, token_b);
        }
        (token_b, token_a)
    }


    fn assert_only_pauser() {
        assert(get_caller_address() == _pauser::read(), 'only pauser');
    }

    fn assert_only_fee_manager() {
        assert(get_caller_address() == _fee_manager::read(), 'only fee manager');
    }
}
