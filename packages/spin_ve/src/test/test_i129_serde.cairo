use core::traits::Into;
use core::debug::PrintTrait;
use spin_ve::types::{Point, i129};
use spin_ve::escrow::Escrow;

#[test]
#[available_gas(2000000)]
fn test_read_write() {
    let bias = i129 { inner: 12, sign: false };
    let slope = i129 { inner: 13, sign: true };
    let point = Point { bias, slope, ts: 1234, blk: 4321 };
    let epoch: u256 = 2;
    let token_id: u256 = 3;

    Escrow::_user_point_epoch::write(token_id, epoch);
    Escrow::_user_point_history::write((token_id, epoch), point);

    let slope = Escrow::get_last_user_slope(token_id);


    assert(slope.inner == 13, 'inner shuold be 13');
    assert(slope.sign == true, 'inner shuold be true');
}

