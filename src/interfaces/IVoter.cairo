use starknet::ContractAddress;

#[abi]
trait IVoter {
    #[view]
    fn ve() -> ContractAddress;

    #[view]
    fn minter() -> ContractAddress;

    #[external]
    fn notify_reward_Amount(amount: u256);
}
