use alexandria_math::signed_integers::{i129};
use spin_ve::storage_access::locked_balance::LockedBalanceStorageAccess;
use spin_ve::storage_access::point::PointStorageAccess;
use spin_ve::utils::{to_i129};
use serde::Serde;

// We cannot really do block numbers per se b/c slope is per time, not per block
// and per block could be fairly bad b/c Ethereum changes blocktimes.
// What we can do is to extrapolate ***At functions
#[derive(Copy, Drop)]
struct Point {
    bias: i129,
    slope: i129, // -dweight / dt
    ts: u128,
    blk: u128
}

#[derive(Copy, Drop)]
struct LockedBalance {
    amount: i129,
    end: u128
}


#[derive(Copy, Drop, Serde)]
enum DepositType {
    DEPOSIT_FOR_TYPE: (),
    CREATE_LOCK_TYPE: (),
    INCREASE_LOCK_AMOUNT: (),
    INCREASE_UNLOCK_TIME: (),
    MERGE_TYPE: (),
    SPLIT_TYPE: ()
}


impl PointDefault of Default<Point> {
    fn default() -> Point {
        Point { bias: to_i129(0), slope: to_i129(0), ts: 0, blk: 0 }
    }
}

impl LockedBalanceDefault of Default<LockedBalance> {
    fn default() -> LockedBalance {
        LockedBalance { amount: to_i129(0), end: 0 }
    }
}
