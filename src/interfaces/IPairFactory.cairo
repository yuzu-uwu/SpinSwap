use starknet::ContractAddress;
use core::array::ArrayTrait;
use starknet::class_hash::ClassHash;

#[abi]
trait IPairFactory {
    #[view]
    fn all_pairs_length() -> u256;

    #[view]
    fn is_pair(pair_: ContractAddress) -> bool;

    #[view]
    fn is_paused() -> bool;

    #[view]
    fn pairs() -> Array<ContractAddress>;

    #[view]
    fn dibs() -> ContractAddress;

    #[view]
    fn max_referral_fee() -> u256;

    #[view]
    fn staking_nft_fee() -> u256;

    #[view]
    fn pair_class_hash() -> ClassHash;

    #[view]
    fn pair_fees_class_hash() -> ClassHash;

    #[view]
    fn staking_fee_handler() -> ContractAddress;

    #[view]
    fn get_fee(stable_: bool) -> u256;

    #[view]
    fn get_initializable() -> (ContractAddress, ContractAddress, bool);

    #[view]
    fn get_pair(
        token_a: ContractAddress, token_b: ContractAddress, stable_: bool
    ) -> ContractAddress;

    #[external]
    fn create_pair(
        token_a: ContractAddress, token_b: ContractAddress, stable_: bool
    ) -> ContractAddress;
}
