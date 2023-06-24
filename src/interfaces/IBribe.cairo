use starknet::ContractAddress;

#[abi]
trait IBribe {
    #[external]
    fn _deposit(amount: u256, token_id: u256);

    #[external]
    fn _withdraw(amount: u256, token_id: u256);

    #[external]
    fn get_reward_for_owner(token_id: u256, tokens: Array<ContractAddress>);

    #[external]
    fn get_reward_for_address(owner_: ContractAddress, tokens: Array<ContractAddress>);

    #[external]
    fn notify_reward_amount(rewards_token_: ContractAddress, reward: u256);
}
