use core::traits::Into;
use core::traits::TryInto;
use integer::u256_from_felt252;
use box::BoxTrait;
use starknet::{ContractAddress, contract_address_to_felt252, get_block_info, get_block_timestamp};


fn get_block_number() -> u64 {
    let info = get_block_info().unbox();
    info.block_number
}

fn get_block_number_u128() -> u128 {
    let info = get_block_info().unbox();
    info.block_number.into()
}


fn u64_to_u128(num: u64) -> u128 {
    num.into()
}

fn u64_to_u256(num: u64) -> u256 {
    u256 { low: num.into(), high: 0 }
}

fn u128_to_u256(num: u128) -> u256 {
    u256 { low: num, high: 0 }
}

fn get_block_timestamp_u128() -> u128 {
    get_block_number().into()
}

fn and_and(a: bool, b: bool) -> bool {
    // logical_and
    let a_bit = if a {
        1
    } else {
        0
    };
    let b_bit = if b {
        1
    } else {
        0
    };
    let result = a_bit * b_bit;
    result != 0
}

fn or(a: bool, b: bool) -> bool {
    if a {
        return true;
    }

    if b {
        return true;
    }

    return false;
}

fn sort_token(
    token_a: ContractAddress, token_b: ContractAddress
) -> (ContractAddress, ContractAddress) {
    if u256_from_felt252(
        contract_address_to_felt252(token_a)
    ) < u256_from_felt252(contract_address_to_felt252(token_b)) {
        return (token_a, token_b);
    }
    (token_b, token_a)
}
