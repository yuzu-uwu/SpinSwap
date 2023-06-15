use array::ArrayTrait;
use traits::Into;
use integer::{u128_safe_divmod, u128_as_non_zero};
use spin_lib::array::reverse_array;

fn utoa(num: u256) -> Array<felt252> {
    // Libfunc u256_safe_divmod is not allowed 
    // have to transfer to u128 first
    let num_u128: u128 = num.low;
    let mut inverse = ArrayTrait::<felt252>::new();

    if (num_u128 <= 9) {
        // to u128 then to u8
        // all of number is less than 2, so it is safe
        inverse.append(num_u128.into() + 48);
        return inverse;
    }

    let mut dividend = num_u128;

    loop {
        if (dividend <= 0) {
            break ();
        }

        let (quotient, remainder) = u128_safe_divmod(dividend, u128_as_non_zero(10));

        dividend = quotient;
        inverse.append(remainder.into() + 48);
    };

    reverse_array(inverse)
}
