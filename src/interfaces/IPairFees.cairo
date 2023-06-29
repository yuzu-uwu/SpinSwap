use starknet::ContractAddress;

#[abi]
trait IPairFees {
    #[external]
    fn claim_fees_for(recipient: ContractAddress, amount_0: u256, amount_1: u256);

    #[external]
    fn process_staking_fees(amount: u256, is_token_zero: bool);

    #[external]
    fn withdraw_staking_fees(recipient: ContractAddress);
}
