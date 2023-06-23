use starknet::ContractAddress;

#[abi]
trait IMinter {
     #[view]
    fn update_period() -> u128;

    #[view]
    fn check() -> bool ;

    #[view]
    fn period() -> u128;

    #[view]
    fn active_period() -> u128;
}