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

    #[external]
    fn add_reward_token(rewards_token_: ContractAddress);

     #[external]
    fn add_reward_tokens(rewards_token_: Array<ContractAddress>);

    #[external]
    fn set_voter(voter_: ContractAddress);

    #[external]
    fn set_minter(minter_: ContractAddress);

    #[external]
    fn set_owner(owner_: ContractAddress);

    #[external]
    fn emergency_recover_erc20(token_address: ContractAddress, token_amount: u256);

    #[external]
    fn recover_erc20_and_update_data(token_address: ContractAddress, token_amount: u256);
}
