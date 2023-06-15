use alexandria_math::signed_integers::{i129};

fn to_i129(num: u128) -> i129 {
    i129 {inner: num, sign: false}
}
