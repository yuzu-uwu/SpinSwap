#[contract]
mod Token {
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use openzeppelin::tokens::erc20::{ERC20, IERC20};

    const NAME: felt252 = 'Spin';
    const SYMBOL: felt252 = 'SPIN';

    #[storage]
    struct Storage {
        _minter: ContractAddress,
        _initialMinted: bool
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
        IERC20::name()
    }

    #[view]
    fn symbol() -> felt252 {
        IERC20::symbol()
    }

    #[view]
    fn decimals() -> u8 {
        IERC20::decimals()
    }

    #[view]
    fn total_supply() -> u256 {
        IERC20::total_supply()
    }

    #[view]
    fn balance_of(account: ContractAddress) -> u256 {
        IERC20::balance_of(account)
    }

    #[view]
    fn allowance(owner: ContractAddress, spender: ContractAddress) -> u256 {
        IERC20::allowance(owner, spender)
    }

    #[external]
    fn transfer(recipient: ContractAddress, amount: u256) -> bool {
        IERC20::transfer(recipient, amount)
    }

    #[external]
    fn transfer_from(sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool {
        IERC20::transfer_from(sender, recipient, amount)
    }

    #[external]
    fn approve(spender: ContractAddress, amount: u256) -> bool {
        IERC20::approve(spender, amount)
    }

    #[external]
    fn increase_allowance(spender: ContractAddress, added_value: u256) -> bool {
        IERC20::increase_allowance(spender, added_value)
    }

    #[external]
    fn decrease_allowance(spender: ContractAddress, subtracted_value: u256) -> bool {
        IERC20::decrease_allowance(spender, subtracted_value)
    }

    ///
    /// Spin
    ///

    // Initial mint: total 50M
    #[external]
    fn initialMint(recipient: ContractAddress) {
        assert(!_initialMinted::read(), 'Spin: initial minted');
        assert(get_caller_address() == _minter::read(), 'Spin: caller not allowed');

        _initialMinted::write(true);

        // 50 * 1e6 * 1e18
        ERC20::_mint(recipient, 50 * 1_000_000_u256 * 1_000_000_000_000_000_000_u256);
    }

    #[external]
    fn setMinter(minter_: ContractAddress) {
        assert(get_caller_address() == _minter::read(), 'Spin: caller not allowed');
        _minter::write(minter_);
    }

    #[external]
    fn mint(account: ContractAddress, amount: u256) -> bool {
        assert(get_caller_address() == _minter::read(), 'Spin: caller not allowed');
        ERC20::_mint(account, amount);
        true
    }
}
