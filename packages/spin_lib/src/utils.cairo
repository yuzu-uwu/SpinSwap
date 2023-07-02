use core::traits::Into;
use core::traits::TryInto;
use starknet::{get_block_info, get_block_timestamp};
use box::BoxTrait;


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
