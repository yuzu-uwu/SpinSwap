use core::array::ArrayTrait;
// @title Curve Fee Distribution modified for ve(3,3) emissions
// @author Curve Finance, andrecronje
// @license MIT
#[contract]
mod rewards_distributor {
    use starknet::{ContractAddress, get_contract_address, get_caller_address};
    use array::ArrayTrait;
    use integer::{u256, BoundedInt};
    use zeroable::Zeroable;
    use spin_lib::utils::{get_block_timestamp_u128, get_block_number_u128, and_and, u128_to_u256, };
    use spin_lib::math::Math;
    use spin_ve::utils::to_i129;
    use spin_ve::types::{Point};
    use openzeppelin::token::erc20::ERC20;
    use openzeppelin::token::erc20::interface::{IERC20, IERC20DispatcherTrait, IERC20Dispatcher};
    use openzeppelin::access::ownable::Ownable;
    use spinswap::interfaces::IVotingEscrow::{
        IVotingEscrowDispatcher, IVotingEscrowDispatcherTrait
    };

    const WEEK: u128 = 604800; // 7 * 86400

    #[storage]
    struct Storage {
        _start_time: u128,
        _time_cursor: u128,
        _time_cursor_of: LegacyMap<u256, u128>, //token id => time
        _user_epoch_of: LegacyMap<u256, u256>, // token id => u256
        _last_token_time: u128,
        _tokens_per_week: LegacyMap<u128, u256>, // week => tokens
        _token_last_balance: u256,
        _ve_supply: LegacyMap<u128, u256>, // week => supply
        _owner: ContractAddress,
        _voting_escrow: ContractAddress,
        _token: ContractAddress,
        _depositor: ContractAddress
    }

    #[constructor]
    fn constructor(voting_escrow_: ContractAddress) {
        let caller = get_caller_address();

        let t = get_block_timestamp_u128() / WEEK * WEEK;
        _start_time::write(t);
        _last_token_time::write(t);
        _time_cursor::write(t);

        let token = IVotingEscrowDispatcher { contract_address: voting_escrow_ }.token();
        _token::write(token);
        _voting_escrow::write(voting_escrow_);
        _depositor::write(caller);
        Ownable::_transfer_ownership(caller);

        IERC20Dispatcher { contract_address: token }.approve(voting_escrow_, BoundedInt::max());
    }

    #[event]
    fn CheckpointToken(time: u128, tokens: u256) {}
    #[event]
    fn Claimed(token_id: u256, amount: u256, claim_epoch: u256, max_epoch: u256) {}

    #[view]
    fn timestamp() -> u128 {
        get_block_timestamp_u128() / WEEK * WEEK
    }

    #[view]
    fn voting_escrow() -> ContractAddress {
        _voting_escrow::read()
    }

    #[external]
    fn checkpoint_token() {
        assert(get_caller_address() == _depositor::read(), 'only depositor');
        _checkpoint_token()
    }

    #[view]
    fn ve_for_at(token_id: u256, timestamp_: u128) -> u256 {
        let ve = _voting_escrow::read();
        let voting_escrow = IVotingEscrowDispatcher { contract_address: ve };

        let max_user_epoch = voting_escrow.user_point_epoch(token_id);
        let epoch = _find_timestamp_user_epoch(ve, token_id, timestamp_, max_user_epoch);
        let pt = voting_escrow.user_point_history(token_id, epoch);

        let _t = pt.bias - pt.slope * (to_i129(timestamp_) - to_i129(pt.ts));

        Math::max(u128_to_u256(_t.inner), 0_u256)
    }

    #[external]
    fn checkpoint_total_supply() {
        _checkpoint_total_supply()
    }

    #[view]
    fn claimable(token_id: u256) -> u256 {
        let last_token_time_ = _last_token_time::read() / WEEK * WEEK;

        _claimable(token_id, _voting_escrow::read(), last_token_time_)
    }

    #[external]
    fn claim(token_id: u256) -> u256 {
        let ve = _voting_escrow::read();
        let voting_escrow = IVotingEscrowDispatcher { contract_address: ve };
        let block_timestamp = get_block_timestamp_u128();
        if block_timestamp >= _time_cursor::read() {
            _checkpoint_total_supply();
        }
        let mut last_token_time = _last_token_time::read();
        last_token_time = last_token_time / WEEK * WEEK;
        let amount = _claim(token_id, ve, last_token_time);

        if amount != 0 {
            // if locked.end then send directly
            let locked = voting_escrow.locked(token_id);
            if locked.end < block_timestamp {
                let nft_owner = voting_escrow.owner_of(token_id);
                IERC20Dispatcher { contract_address: _token::read() }.transfer(nft_owner, amount);
            } else {
                voting_escrow.deposit_for(token_id, amount);
            }

            _token_last_balance::write(_token_last_balance::read() - amount);
        }

        amount
    }

    #[external]
    fn claim_many(token_ids: Array<u256>) -> bool {
        let ve = _voting_escrow::read();
        let voting_escrow = IVotingEscrowDispatcher { contract_address: ve };
        let block_timestamp = get_block_timestamp_u128();
        if block_timestamp >= _time_cursor::read() {
            _checkpoint_total_supply();
        }
        let mut last_token_time = _last_token_time::read();
        last_token_time = last_token_time / WEEK * WEEK;
        let mut total = 0_u256;
        let mut i = 0_usize;

        loop {
            if i >= token_ids.len() {
                break ();
            }
            let token_id = *token_ids[i];
            if token_id == 0 {
                break ();
            }
            let amount = _claim(token_id, ve, last_token_time);
            if amount != 0 {
                let locked = voting_escrow.locked(token_id);
                if locked.end < block_timestamp {
                    let nft_owner = voting_escrow.owner_of(token_id);
                    IERC20Dispatcher {
                        contract_address: _token::read()
                    }.transfer(nft_owner, amount);
                } else {
                    voting_escrow.deposit_for(token_id, amount);
                }
                total += amount;
            }

            i += 1;
        };

        if total != 0 {
            _token_last_balance::write(_token_last_balance::read() - total);
        }

        return true;
    }

    #[external]
    fn set_depositor(depositor_: ContractAddress) {
        Ownable::assert_only_owner();

        _depositor::write(depositor_);
    }

    #[external]
    fn set_owner(owner_: ContractAddress) {
        Ownable::transfer_ownership(owner_);
    }

    fn _checkpoint_token() {
        let token_balance = IERC20Dispatcher {
            contract_address: _token::read()
        }.balance_of(get_contract_address());
        let to_distribute = token_balance - _token_last_balance::read();
        _token_last_balance::write(token_balance);

        let mut t = _last_token_time::read();
        let since_last = get_block_timestamp_u128() - t;
        _last_token_time::write(get_block_timestamp_u128());
        let mut this_week = t / WEEK * WEEK;
        let mut next_week = 0;

        let mut i: usize = 0;
        let block_timestamp = get_block_timestamp_u128();

        loop {
            if i >= 20 {
                break ();
            }
            next_week = this_week + WEEK;
            if block_timestamp < next_week {
                if and_and(since_last == 0, block_timestamp == t) {
                    _tokens_per_week::write(
                        this_week, _tokens_per_week::read(this_week) + to_distribute
                    );
                } else {
                    let _new_week_tokens = _tokens_per_week::read(this_week)
                        + u128_to_u256(to_distribute.low * (block_timestamp - t) / since_last);
                    _tokens_per_week::write(this_week, _new_week_tokens);
                }
                break ();
            } else {
                if and_and(since_last == 0, next_week == t) {
                    _tokens_per_week::write(
                        this_week, _tokens_per_week::read(this_week) + to_distribute
                    );
                } else {
                    let _new_week_tokens = _tokens_per_week::read(this_week)
                        + u128_to_u256(to_distribute.low * (next_week - t) / since_last);
                    _tokens_per_week::write(this_week, _new_week_tokens);
                }
            }

            t = next_week;
            this_week = next_week;
            i += 1;
        };

        CheckpointToken(block_timestamp, to_distribute)
    }

    fn _find_timestamp_epoch(ve: ContractAddress, timestamp_: u128) -> u256 {
        let voting_escrow = IVotingEscrowDispatcher { contract_address: ve };
        let mut _min = 0_u256;
        let mut _max = voting_escrow.epoch();
        let mut i = 0_usize;

        loop {
            if i >= 128 {
                break ();
            }

            if _min >= _max {
                break ();
            }

            let _mid = (_min + _max + 2) / 2;
            let pt = voting_escrow.point_history(_mid);

            if pt.ts <= timestamp_ {
                _min = _mid
            } else {
                _max = _mid - 1;
            }

            i += 1;
        };

        _min
    }

    fn _find_timestamp_user_epoch(
        ve: ContractAddress, token_id: u256, timestamp_: u128, max_user_epoch: u256
    ) -> u256 {
        let voting_escrow = IVotingEscrowDispatcher { contract_address: ve };
        let mut _min = 0_u256;
        let mut _max = max_user_epoch;
        let mut i = 0_usize;

        loop {
            if i >= 128 {
                break ();
            }
            if _min >= _max {
                break ();
            }

            let _mid = (_min + _max + 2) / 2;
            let pt = voting_escrow.user_point_history(token_id, _mid);
            if pt.ts <= timestamp_ {
                _min = _mid
            } else {
                _max = _mid - 1;
            }

            i = i + 1;
        };

        _min
    }

    fn _checkpoint_total_supply() {
        let ve = _voting_escrow::read();
        let voting_escrow = IVotingEscrowDispatcher { contract_address: ve };

        let mut t = _time_cursor::read();
        let rounded_timestamp = get_block_timestamp_u128() / WEEK * WEEK;
        voting_escrow.checkpoint();

        let mut i = 0_usize;
        loop {
            if i >= 20 {
                break ();
            }
            if t > rounded_timestamp {
                break ();
            } else {
                let epoch = _find_timestamp_epoch(ve, t);
                let pt = voting_escrow.point_history(epoch);
                let mut dt = to_i129(0);
                if t > pt.ts {
                    dt = to_i129(t) - to_i129(pt.ts);
                }

                let _t = pt.bias - pt.slope * dt;
                _ve_supply::write(t, Math::max(u128_to_u256(_t.inner), 0));
            }

            t += WEEK;
            i += 1;
        };

        _time_cursor::write(t)
    }

    fn _claim(token_id: u256, ve: ContractAddress, last_token_time_: u128) -> u256 {
        let voting_escrow = IVotingEscrowDispatcher { contract_address: ve };

        let mut user_epoch = 0_u256;
        let mut to_distribute = 0_u256;

        let max_user_epoch = voting_escrow.user_point_epoch(token_id);
        let start_time = _start_time::read();

        if max_user_epoch == 0 {
            return 0;
        }

        let mut week_cursor = _time_cursor_of::read(token_id);
        if week_cursor == 0 {
            user_epoch = _find_timestamp_user_epoch(ve, token_id, start_time, max_user_epoch);
        } else {
            user_epoch = _user_epoch_of::read(token_id);
        }

        if user_epoch == 0 {
            user_epoch = 1;
        }

        let mut user_point = voting_escrow.user_point_history(token_id, user_epoch);

        if week_cursor == 0 {
            week_cursor = (user_point.ts + WEEK - 1) / WEEK * WEEK;
        }
        if week_cursor >= _last_token_time::read() {
            return 0;
        }
        if week_cursor < start_time {
            week_cursor = start_time;
        }

        let mut old_user_point: Point = Default::default();
        let mut i = 0_usize;

        loop {
            if i >= 50 {
                break ();
            }
            if week_cursor >= last_token_time_ {
                break ();
            }

            if and_and(week_cursor >= user_point.ts, user_epoch <= max_user_epoch) {
                user_epoch += 1;
                old_user_point = user_point;
                if user_epoch > max_user_epoch {
                    user_point = Default::default();
                } else {
                    user_point = voting_escrow.user_point_history(token_id, user_epoch);
                }
            } else {
                let dt = to_i129(week_cursor) - to_i129(old_user_point.ts);
                let _balance_of = old_user_point.bias - dt * old_user_point.slope;
                let balance_of = Math::max(u128_to_u256(_balance_of.inner), 0);
                if and_and(balance_of == 0, user_epoch > max_user_epoch) {
                    break ();
                }
                if balance_of != 0 {
                    to_distribute += balance_of
                        * _tokens_per_week::read(week_cursor)
                        / _ve_supply::read(week_cursor);
                }
                week_cursor += WEEK;
            }

            i += 1;
        };

        user_epoch = Math::min(max_user_epoch, user_epoch - 1);
        _user_epoch_of::write(token_id, user_epoch);
        _time_cursor_of::write(token_id, week_cursor);

        Claimed(token_id, to_distribute, user_epoch, max_user_epoch);

        to_distribute
    }

    fn _claimable(token_id: u256, ve: ContractAddress, last_token_time_: u128) -> u256 {
        let voting_escrow = IVotingEscrowDispatcher { contract_address: ve };

        let mut user_epoch = 0_u256;
        let mut to_distribute = 0_u256;

        let max_user_epoch = voting_escrow.user_point_epoch(token_id);
        let start_time = _start_time::read();

        if max_user_epoch == 0 {
            return 0;
        }

        let mut week_cursor = _time_cursor_of::read(token_id);
        if week_cursor == 0 {
            user_epoch = _find_timestamp_user_epoch(ve, token_id, start_time, max_user_epoch);
        } else {
            user_epoch = _user_epoch_of::read(token_id);
        }

        if user_epoch == 0 {
            user_epoch = 1;
        }

        let mut user_point = voting_escrow.user_point_history(token_id, user_epoch);

        if week_cursor == 0 {
            week_cursor = (user_point.ts + WEEK - 1) / WEEK * WEEK;
        }
        if week_cursor >= _last_token_time::read() {
            return 0;
        }
        if week_cursor < start_time {
            week_cursor = start_time;
        }

        let mut old_user_point: Point = Default::default();
        let mut i = 0_usize;

        loop {
            if i >= 50 {
                break ();
            }
            if week_cursor >= last_token_time_ {
                break ();
            }

            if and_and(week_cursor >= user_point.ts, user_epoch <= max_user_epoch) {
                user_epoch += 1;
                old_user_point = user_point;
                if user_epoch > max_user_epoch {
                    user_point = Default::default();
                } else {
                    user_point = voting_escrow.user_point_history(token_id, user_epoch);
                }
            } else {
                let dt = to_i129(week_cursor) - to_i129(old_user_point.ts);
                let _balance_of = old_user_point.bias - dt * old_user_point.slope;
                let balance_of = Math::max(u128_to_u256(_balance_of.inner), 0);
                if and_and(balance_of == 0, user_epoch > max_user_epoch) {
                    break ();
                }
                if balance_of != 0 {
                    to_distribute += balance_of
                        * _tokens_per_week::read(week_cursor)
                        / _ve_supply::read(week_cursor);
                }
                week_cursor += WEEK;
            }

            i += 1;
        };

        to_distribute
    }
}
