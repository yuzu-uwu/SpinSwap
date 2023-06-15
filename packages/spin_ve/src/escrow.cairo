use core::traits::Into;
use alexandria_math::signed_integers::{i129};

// 7 * 86400
const ONE_WEEK: u256 = 604800;
const WEEK: u256 = 604800;
// 2 * 365 * 86400
const MAXTIME: u256 = 63072000;
// 1e18
const MULTIPLIER: u256 = 1_000_000_000_000_000_000_u256;

fn get_interger_maxtime() -> i129 {
    i129 { inner: MAXTIME.low, sign: false }
}

#[contract]
mod Escrow {
    use super::{ONE_WEEK, WEEK, MAXTIME, MULTIPLIER, get_interger_maxtime};
    use alexandria_math::signed_integers::{i129};

    use spin_ve::types::Point;
    use spin_ve::types::LockedBalance;

    use spin_ve::storage_access::i129::I129StorageAccess;
    use spin_ve::serde::I129Serde;
    use spin_ve::utils::to_i129;
    use spin_lib::utils::{get_block_timestamp_u128, get_block_number_u128, and_and};


    #[storage]
    struct Storage {
        _epoch: u256,
        _point_history: LegacyMap<u256, Point>, // epoch -> unsigned point
        _user_point_epoch: LegacyMap<u256, u256>,
        _user_point_history: LegacyMap<(u256, u256), Point>, //user -> epoch -> point
        _locked: LegacyMap<u256, LockedBalance>,
        _slope_changes: LegacyMap<u128, i129>, // time(u128) -> signed slope change
    }

    /// @notice Get the most recently recorded rate of voting power decrease for `token_id_`
    /// @param token_id_ token of the NFT
    /// @return Value of the slope
    #[view]
    fn get_last_user_slope(token_id_: u256) -> i129 {
        let uepoch = _user_point_epoch::read(token_id_);
        let _point = _user_point_history::read((token_id_, uepoch));
        _point.slope
    }

    /// @notice Get the timestamp for checkpoint `_idx` for `token_id_`
    /// @param token_id_ token of the NFT
    /// @param _idx User epoch number
    /// @return Epoch time of the checkpoint
    #[view]
    fn user_point_history__ts(token_id_: u256, idx_: u256) -> u128 {
        let _point = _user_point_history::read((token_id_, idx_));
        _point.ts
    }


    /// @notice Get timestamp when `token_id_`'s lock finishes
    /// @param token_id_ User NFT
    /// @return Epoch time of the lock end
    #[view]
    fn locked_end(token_id_: u256) -> u128 {
        let locked = _locked::read(token_id_);

        locked.end
    }

    /// @notice Record global and per-user data to checkpoint
    /// @param _token_id NFT token ID. No user checkpoint if 0
    /// @param _old_locked Pevious locked amount / end lock time for the user
    /// @param _new_locked New locked amount / end lock time for the user
    fn _checkpoint(_token_id: u256, _old_locked: LockedBalance, _new_locked: LockedBalance) {
        let mut old_dslope = to_i129(0);
        let mut new_dslope = to_i129(0);
        let mut epoch = _epoch::read();

        let mut u_old: Point = Default::default();
        let mut u_new: Point = Default::default();

        if _token_id != 0 {
            // Calculate slopes and biases
            // Kept at zero when they have to
            if (and_and(
                _old_locked.end > get_block_timestamp_u128(), _old_locked.amount > to_i129(0)
            )) {
                let time_diff: i129 = to_i129(_old_locked.end)
                    - to_i129(get_block_timestamp_u128());

                u_old.slope = _old_locked.amount / get_interger_maxtime();
                u_old.bias = u_old.slope * time_diff;
            }
            if (and_and(
                _new_locked.end > get_block_timestamp_u128(), _new_locked.amount > to_i129(0)
            )) {
                let time_diff: i129 = to_i129(_new_locked.end)
                    - to_i129(get_block_timestamp_u128());

                u_new.slope = _new_locked.amount / get_interger_maxtime();
                u_new.bias = u_new.slope * time_diff;
            }

            // Read values of scheduled changes in the slope
            // _old_locked.end can be in the past and in the future
            // _new_locked.end can ONLY by in the FUTURE unless everything expired: than zeros
            old_dslope = _slope_changes::read(_old_locked.end);
            if _new_locked.end != 0 {
                if _new_locked.end == _old_locked.end {
                    new_dslope = old_dslope;
                } else {
                    new_dslope = _slope_changes::read(_new_locked.end);
                }
            }
        }

        let mut last_point = Point {
            bias: to_i129(0),
            slope: to_i129(0),
            ts: get_block_timestamp_u128(),
            blk: get_block_number_u128()
        };
        if (epoch > 0) {
            last_point = _point_history::read(epoch);
        }
        let mut last_checkpoint = last_point.ts;

        // initial_last_point is used for extrapolation to calculate block number
        // (approximately, for *At methods) and save them
        // as we cannot figure that out exactly from inside the contract
        let mut initial_last_point = last_point;
        let mut block_slope: u128 = 0;
        if get_block_timestamp_u128() > last_point.ts {
            block_slope = (MULTIPLIER.low * (get_block_number_u128() - last_point.blk))
                / (get_block_timestamp_u128() - last_point.ts);
        }
        // If last point is already recorded in this block, slope=0
        // But that's ok b/c we know the block in such case

        // Go over weeks to fill history and calculate what the current point is
        {
            let mut t_i: u128 = (last_checkpoint / WEEK.low) * WEEK.low;
            let mut i: usize = 0;

            loop {
                i += 1;
                if (i >= 255) {
                    break ();
                }
                // Hopefully it won't happen that this won't get used in 5 years!
                // If it does, users will be able to withdraw but vote weight will be broken
                t_i += WEEK.low;
                let mut d_slope = to_i129(0);

                if t_i > get_block_timestamp_u128() {
                    t_i = get_block_timestamp_u128();
                } else {
                    d_slope = _slope_changes::read(t_i);
                }
                last_point.bias -= last_point.slope * (to_i129(t_i) - to_i129(last_checkpoint));
                last_point.slope += d_slope;
                if last_point.bias < to_i129(0) {
                    // This can happen
                    last_point.bias = to_i129(0);
                }
                if last_point.slope < to_i129(0) {
                    // This cannot happen - just in case
                    last_point.slope = to_i129(0);
                }
                last_checkpoint = t_i;
                last_point.ts = t_i;
                last_point.blk = initial_last_point.blk
                    + (block_slope * (t_i - initial_last_point.ts)) / MULTIPLIER.low;
                epoch += 1;
                if (t_i == get_block_timestamp_u128()) {
                    last_point.blk = get_block_number_u128();
                    break ();
                } else {
                    _point_history::write(epoch, last_point);
                }

                // _cache_value is useless, just prevent "Tail expression not allow in a `loop` block"
                let _cache_value = 0;
            };
        }

        _epoch::write(epoch);
        // Now point_history is filled until t=now

        if _token_id != 0 {
            // Schedule the slope changes (slope is going down)
            // We subtract new_user_slope from [_new_locked.end]
            // and add old_user_slope to [_old_locked.end]
            if _old_locked.end > get_block_timestamp_u128() {
                // old_dslope was <something> - u_old.slope, so we cancel that
                old_dslope += u_old.slope;
                if _new_locked.end == _old_locked.end {
                    old_dslope -= u_new.slope; // It was a new deposit, not extension
                }
                _slope_changes::write(_old_locked.end, old_dslope);
            }

            if _new_locked.end > get_block_timestamp_u128() {
                if _new_locked.end > _old_locked.end {
                    new_dslope -= u_new.slope; // old slope disappeared at this point
                    _slope_changes::write(_new_locked.end, new_dslope);
                }
            // else: we recorded it already in old_dslope
            }
            // Now handle user history
            let user_epoch = _user_point_epoch::read(_token_id) + 1;

            _user_point_epoch::write(_token_id, user_epoch);
            u_new.ts = get_block_timestamp_u128();
            u_new.blk = get_block_number_u128();
            _user_point_history::write((_token_id, user_epoch), u_new);
        }
    }
}
