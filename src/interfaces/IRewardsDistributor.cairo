use starknet::ContractAddress;

#[abi]
trait IRewardsDistributor {
    #[external]
    fn checkpoint_token();

    #[external]
    fn checkpoint_total_supply();

    #[view]
    fn voting_escrow() -> ContractAddress;

    #[view]
    fn claimable(token_id: u256) -> u256;
}
