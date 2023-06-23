use starknet::ContractAddress;

#[abi]
trait ISpin {
    #[view]
    fn total_supply() -> u256;
    
    #[view]
    fn balance_of(account: ContractAddress) -> u256;

    #[external]
    fn approve(spender: ContractAddress, amount: u256) -> bool;

    #[external]
    fn transfer(recipient: ContractAddress, amount: u256) -> bool;

    #[external]
    fn transfer_from(sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;

    #[external]
    fn mint(account: ContractAddress, amount: u256) -> bool;

    #[viewer]
    fn minter() -> ContractAddress;
}
