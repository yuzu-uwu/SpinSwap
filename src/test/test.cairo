use core::debug::PrintTrait;
use core::array::ArrayTrait;
use core::traits::TryInto;
use core::traits::Into;
use starknet::contract_address_const;
use starknet::testing::set_caller_address;
use integer::u256_from_felt252;
use integer::{u128_safe_divmod, u128_as_non_zero};
use option::OptionTrait;


#[test]
#[available_gas(2000000)]
fn test_felt() {
     gas::withdraw_gas_all(get_builtin_costs()).expect('Out of gas');
    let a:felt252 = '1222h';
    let b = u256_from_felt252(a);
    b.print();
}
