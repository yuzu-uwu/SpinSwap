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
    use starknet::{get_caller_address, ContractAddress, get_contract_address};
    use super::{ONE_WEEK, WEEK, MAXTIME, MULTIPLIER, get_interger_maxtime};
    use alexandria_math::signed_integers::{i129};

    use spin_ve::types::{Point, DepositType, LockedBalance};

    use spin_ve::storage_access::i129::I129StorageAccess;
    use spin_ve::serde::I129Serde;
    use spin_ve::utils::to_i129;
    use spin_ve::ve::VE;
    use spin_ve::gauge_voting::GaugeVoting;
    use spin_lib::utils::{get_block_timestamp_u128, get_block_number_u128, and_and, u128_to_u256};
    use openzeppelin::tokens::erc20::{ERC20, IERC20, IERC20DispatcherTrait, IERC20Dispatcher};
    use openzeppelin::tokens::erc721::{ERC721};
    use openzeppelin::security::reentrancyguard::ReentrancyGuard;


    #[storage]
    struct Storage {
        _epoch: u256,
        _point_history: LegacyMap<u256, Point>, // epoch -> unsigned point
        _user_point_epoch: LegacyMap<u256, u256>,
        _user_point_history: LegacyMap<(u256, u256), Point>, //user -> epoch -> point
        _locked: LegacyMap<u256, LockedBalance>,
        _slope_changes: LegacyMap<u128, i129>, // time(u128) -> signed slope change
    }

    #[event]
    fn Deposit(
        provider: ContractAddress,
        token_id: u256,
        value: u256,
        lock_time: u128,
        deposit_type: DepositType,
        ts: u128
    ) {}

    #[event]
    fn Withdraw(provider: ContractAddress, token_id: u256, value: u256, ts: u128) {}

    #[event]
    fn Supply(prev_supply: u256, supply: u256) {}

    /// @notice Get the most recently recorded rate of voting power decrease for `token_id_`
    /// @param token_id_ token of the NFT
    /// @return Value of the slope
    fn get_last_user_slope(token_id_: u256) -> i129 {
        let uepoch = _user_point_epoch::read(token_id_);
        let _point = _user_point_history::read((token_id_, uepoch));
        _point.slope
    }

    /// @notice Get the timestamp for checkpoint `_idx` for `token_id_`
    /// @param token_id_ token of the NFT
    /// @param _idx User epoch number
    /// @return Epoch time of the checkpoint
    fn user_point_history_ts(token_id_: u256, idx_: u256) -> u128 {
        let _point = _user_point_history::read((token_id_, idx_));
        _point.ts
    }


    /// @notice Get timestamp when `token_id_`'s lock finishes
    /// @param token_id_ User NFT
    /// @return Epoch time of the lock end
    fn locked_end(token_id_: u256) -> u128 {
        let locked = _locked::read(token_id_);

        locked.end
    }

    /// @notice Record global and per-user data to checkpoint
    /// @param _token_id NFT token ID. No user checkpoint if 0
    /// @param _old_locked Pevious locked amount / end lock time for the user
    /// @param _new_locked New locked amount / end lock time for the user
    fn checkpoint(_token_id: u256, _old_locked: LockedBalance, _new_locked: LockedBalance) {
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
                i += 1;
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

    /// @notice Deposit and lock tokens for a user
    /// @param _token_id NFT that holds lock
    /// @param _value Amount to deposit
    /// @param unlock_time New time when to unlock the tokens, or 0 if unchanged
    /// @param locked_balance Previous locked amount / timestamp
    /// @param deposit_type The type of deposit
    fn _deposit_for(
        _token_id: u256,
        _value: u256,
        unlock_time: u128,
        locked_balance: LockedBalance,
        deposit_type: DepositType
    ) {
        let mut _locked = locked_balance;
        let supply_before = IERC20::total_supply();
        let supply_after = supply_before + _value;
        ERC20::_total_supply::write(supply_after);

        let old_locked = LockedBalance { amount: _locked.amount, end: _locked.end };
        if (unlock_time != 0) {
            _locked.end = unlock_time;
        }
        _locked::write(_token_id, _locked);

        // Possibilities:
        // Both old_locked.end could be current or expired (>/< block.timestamp)
        // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
        // _locked.end > block.timestamp (always)
        checkpoint(_token_id, old_locked, _locked);

        let from = get_caller_address();
        assert(
            IERC20Dispatcher {
                contract_address: VE::_token::read()
            }.transfer_from(from, get_contract_address(), _value),
            'Transfer token failed'
        );

        Deposit(from, _token_id, _value, _locked.end, deposit_type, get_block_timestamp_u128());
        Supply(supply_before, supply_after);
    }

    /// @notice Deposit `_value` tokens for `_to` and lock for `_lock_duration`
    /// @param _value Amount to deposit
    /// @param _lock_duration Number of seconds to lock tokens for (rounded down to nearest week)
    /// @param _to Address to deposit

    fn _create_lock(value_: u256, lock_duration_: u128, to_: ContractAddress) -> u256 {
        // Locktime is rounded down to weeks
        let unlock_time = (get_block_timestamp_u128() + lock_duration_) / WEEK.low / WEEK.low;

        assert(value_ > 0, 'need non-zero value');
        assert(unlock_time > get_block_timestamp_u128(), 'can only lock in future time');
        assert(
            unlock_time <= get_block_timestamp_u128() + MAXTIME.low,
            'Voting lock can be 2 years max'
        );

        let token_id = VE::increase_token_count();
        VE::_mint(to_, token_id);

        _deposit_for(
            token_id,
            value_,
            unlock_time,
            _locked::read(token_id),
            DepositType::CREATE_LOCK_TYPE(())
        );

        return token_id;
    }

    /// @notice Deposit `_value` additional tokens for `_tokenId` without modifying the unlock time
    /// @param _value Amount of tokens to deposit and add to the lock
    fn increase_amount(token_id_: u256, value_: u256) {
        assert(
            ERC721::_is_approved_or_owner(get_caller_address(), token_id_),
            'ERC721: unauthorized caller'
        );

        let mut locked = _locked::read(token_id_);

        assert(value_ > 0, 'need non-zero value');
        assert(locked.amount > to_i129(0), 'No existing lock found');
        assert(locked.end > get_block_timestamp_u128(), 'lock expired. Withdraw');

        _deposit_for(token_id_, value_, 0, locked, DepositType::INCREASE_LOCK_AMOUNT(()));
    }

    /// @notice Extend the unlock time for `_tokenId`
    /// @param _lock_duration New number of seconds until tokens unlock
    fn increase_unlock_time(token_id_: u256, lock_duration_: u128) {
        assert(
            ERC721::_is_approved_or_owner(get_caller_address(), token_id_),
            'ERC721: unauthorized caller'
        );
        let mut locked = _locked::read(token_id_);
        let unlock_time = (get_block_timestamp_u128() + lock_duration_)
            / WEEK.low
            * WEEK.low; // Locktime is rounded down to weeks

        assert(locked.end > get_block_timestamp_u128(), 'Lock expired');
        assert(locked.amount > to_i129(0), 'Nothing is locked');
        assert(unlock_time > locked.end, 'Can only increase lock duration');
        assert(
            unlock_time <= get_block_timestamp_u128() + MAXTIME.low,
            'Voting lock can be 2 years max'
        );

        _deposit_for(token_id_, 0, unlock_time, locked, DepositType::INCREASE_UNLOCK_TIME(()));
    }

    /// @notice Withdraw all tokens for `_tokenId`
    /// @dev Only possible if the lock has expired
    fn withdraw(token_id_: u256) {
        assert(
            ERC721::_is_approved_or_owner(get_caller_address(), token_id_),
            'ERC721: unauthorized caller'
        );

        assert(
            and_and(
                GaugeVoting::_attachments::read(token_id_) == 0,
                !GaugeVoting::_voted::read(token_id_)
            ),
            'attached'
        );

        let mut locked = _locked::read(token_id_);
        assert(get_block_timestamp_u128() >= locked.end, 'lock did not expire');
        let value = u128_to_u256(locked.amount.inner);

        _locked::write(token_id_, LockedBalance { amount: to_i129(0), end: 0 });
        let supply_before = IERC20::total_supply();
        let supply_after = supply_before - value;
        ERC20::_total_supply::write(supply_after);

        // old_locked can have either expired <= timestamp or zero end
        // _locked has only 0 end
        // Both can have >= 0 amount
        checkpoint(token_id_, locked, LockedBalance { amount: to_i129(0), end: 0 });

        assert(
            IERC20Dispatcher {
                contract_address: VE::_token::read()
            }.transfer(get_caller_address(), value),
            'Transfer token failed'
        );

        VE::_burn(token_id_);

        Withdraw(get_caller_address(), token_id_, value, get_block_timestamp_u128());
        Supply(supply_before, supply_after);
    }
}
