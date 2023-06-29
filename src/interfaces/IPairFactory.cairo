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
    fn pairs() -> Array<ContractAddress>;

    #[view]
    fn pair_class_hash() -> ClassHash;

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
