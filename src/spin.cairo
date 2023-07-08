#[contract]
mod Token {
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use openzeppelin::token::erc20::ERC20;
    use openzeppelin::token::erc20::interface::IERC20;

    const NAME: felt252 = 'Spin';
    const SYMBOL: felt252 = 'SPIN';

    #[storage]
    struct Storage {
        _minter: ContractAddress,
        _initial_minted: bool
    }

    #[constructor]
    fn constructor() {
        ERC20::initializer(NAME, SYMBOL);

        _minter::write(get_caller_address());
        ERC20::_mint(get_caller_address(), 0);
    }

    ///
    /// ERC20
    ///

    #[view]
    fn name() -> felt252 {
        ERC20::name()
    }

    #[view]
    fn symbol() -> felt252 {
        ERC20::symbol()
    }

    #[view]
    fn decimals() -> u8 {
        ERC20::decimals()
    }

    #[view]
    fn total_supply() -> u256 {
        ERC20::total_supply()
    }

    #[view]
    fn balance_of(account: ContractAddress) -> u256 {
        ERC20::balance_of(account)
    }

    #[view]
    fn allowance(owner: ContractAddress, spender: ContractAddress) -> u256 {
        ERC20::allowance(owner, spender)
    }

    #[external]
    fn transfer(recipient: ContractAddress, amount: u256) -> bool {
        ERC20::transfer(recipient, amount)
    }

    #[external]
    fn transfer_from(sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool {
        ERC20::transfer_from(sender, recipient, amount)
    }

    #[external]
    fn approve(spender: ContractAddress, amount: u256) -> bool {
        ERC20::approve(spender, amount)
    }

    #[external]
    fn increase_allowance(spender: ContractAddress, added_value: u256) -> bool {
        ERC20::increase_allowance(spender, added_value)
    }

    #[external]
    fn decrease_allowance(spender: ContractAddress, subtracted_value: u256) -> bool {
        ERC20::decrease_allowance(spender, subtracted_value)
    }

    ///
    /// Spin
    ///

    #[viewer]
    fn minter() -> ContractAddress {
        _minter::read()
    }

    // Initial mint: total 50M
    #[external]
    fn initial_mint(recipient: ContractAddress) {
        assert(_initial_minted::read(), 'Spin: initial minted');
        assert(get_caller_address() == _minter::read(), 'Spin: caller not allowed');

        _initial_minted::write(true);

        // 50 * 1e6 * 1e18
        ERC20::_mint(recipient, 50 * 1_000_000_u256 * 1_000_000_000_000_000_000_u256);
    }

    #[external]
    fn set_minter(minter_: ContractAddress) {
        assert(get_caller_address() != _minter::read(), 'Spin: caller not allowed');
        _minter::write(minter_);
    }

    #[external]
    fn mint(account: ContractAddress, amount: u256) -> bool {
        assert(get_caller_address() != _minter::read(), 'Spin: caller not allowed');
        ERC20::_mint(account, amount);
        true
    }
}
