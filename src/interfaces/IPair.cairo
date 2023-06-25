use starknet::ContractAddress;

#[abi]
trait IPair {
    #[external]
    fn claim_fees() -> (u256, u256);

    #[view]
    fn tokens() -> (ContractAddress, ContractAddress);
}