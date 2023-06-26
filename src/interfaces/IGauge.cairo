use starknet::ContractAddress;

#[abi]
trait IGauge {
    #[external]
    fn notify_reward_amount(token: ContractAddress, amount: u256);

    #[external]
    fn get_reward_by_distribution(account: ContractAddress);

    #[external]
    fn get_reward();

    #[external]
    fn claim_Fees() -> (u256, u256);

    #[view]
    fn reward_rate(pair: ContractAddress) -> u256;

    #[view]
    fn balance_of(account: ContractAddress) -> u256;

    #[view]
    fn is_for_pair() -> bool;

    #[view]
    fn total_supply() -> u256;

    #[view]
    fn earned(token: ContractAddress, account: ContractAddress) -> u256;

    #[view]
    fn token() -> ContractAddress;
}
