#[contract]
// Pair Fees contract is used as a 1:1 pair relationship to split out fees,
// this ensures that the curve does not need to be modified for LP shares
mod PairFees {
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use openzeppelin::token::erc20::interface::{IERC20, IERC20DispatcherTrait, IERC20Dispatcher};
    use spin_lib::utils::and_and;

    #[storage]
    struct Storage {
        _pair: ContractAddress, // The pair it is bonded to
        _token_0: ContractAddress, // token0 of pair, saved localy and statically for gas optimization
        _token_1: ContractAddress, // token1 of pair, saved localy and statically for gas optimization
        _to_stake_0: u256,
        _to_stake_1: u256,
    }

    #[constructor]
    fn cnstructor(token_0: ContractAddress, token_1: ContractAddress) {
        _pair::write(get_contract_address());
        _token_0::write(token_0);
        _token_1::write(token_1);
    }
    // Allow the pair to transfer fees to users

    #[external]
    fn claim_fees_for(recipient: ContractAddress, amount_0: u256, amount_1: u256) {
        assert_only_pair();
        if amount_0 > 0 {
            IERC20Dispatcher { contract_address: _token_0::read() }.transfer(recipient, amount_0);
        }
        if amount_1 > 0 {
            IERC20Dispatcher { contract_address: _token_1::read() }.transfer(recipient, amount_1);
        }
    }

    #[external]
    fn process_staking_fees(amount: u256, is_token_zero: bool) {
        assert_only_pair();
        if and_and(amount > 0, is_token_zero) {
            _to_stake_0::write(_to_stake_0::read() + amount);
        }

        if and_and(amount > 0, !is_token_zero) {
            _to_stake_1::write(_to_stake_1::read() + amount);
        }
    }

    #[external]
    fn withdraw_staking_fees(recipient: ContractAddress) {
        assert_only_pair();
        if _to_stake_0::read() > 0 {
            IERC20Dispatcher {
                contract_address: _token_0::read()
            }.transfer(recipient, _to_stake_0::read());
            _to_stake_0::write(0);
        }

        if _to_stake_1::read() > 0 {
            IERC20Dispatcher {
                contract_address: _token_1::read()
            }.transfer(recipient, _to_stake_0::read());
            _to_stake_1::write(0);
        }
    }

    fn assert_only_pair() {
        assert(get_caller_address() == _pair::read(), 'only pair')
    }
}
