use core::debug::PrintTrait;
use core::array::ArrayTrait;
use core::traits::TryInto;
use core::traits::Into;
use spinswap::spin::Token;
use starknet::contract_address_const;
use starknet::testing::set_caller_address;
use integer::u256_from_felt252;
use integer::{u128_safe_divmod, u128_as_non_zero};
use spin_lib::string::utoa;


// #[test]
// #[available_gas(2000000)]
// fn test_token_name() {
//     let caller_address = contract_address_const::<1>();
//     set_caller_address(caller_address);

//     let initial_supply: u256 = u256_from_felt252(1000);

//     Token::constructor();
//     assert(Token::name() == 'Spin', 'name shuold be Spin');

//     'Print token name and symbol'.print();
//     Token::name().print();
//     Token::symbol().print();
// }

fn fib(a: felt252, b: felt252, n: felt252) -> felt252 {
    match n {
        0 => a,
        _ => fib(b, a + b, n - 1),
    }
}

#[test]
#[available_gas(2000000)]
fn fib_test() {
    let fib5 = fib(0, 1, 5);
    assert(fib5 == 5, 'fib5 != 5')
}

#[test]
#[available_gas(2000000)]
fn test_string() {
    // let (quotient, remainder) = u128_safe_divmod(10, u128_as_non_zero(2));
    let uint: u256 = 102;
    let result = utoa(uint);

    assert(result.len() == 3, 'wrong length');
    assert(*result[0] == '1', 'wrong char');
    assert(*result[1] == '0', 'wrong char');
    assert(*result[2] == '2', 'wrong char');
}
