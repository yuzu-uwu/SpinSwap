#[contract]
mod Gauge {
    use spin_ve::escrow::{Escrow, WEEK};
    use spin_ve::utils::{to_i129};
    use spin_ve::types::Point;
    use spin_lib::utils::{get_block_timestamp_u128, get_block_number_u128, u128_to_u256};

    // The following ERC20/minime-compatible methods are not real balanceOf and supply!
    // They measure the weights for the purpose of voting, so they don't represent
    // real coins.

    /// @notice Binary search to estimate timestamp for block number
    /// @param _block Block to find
    /// @param max_epoch Don't go beyond this epoch
    /// @return Approximate timestamp for block

    fn _find_block_epoch(_block: u128, max_epoch: u256) -> u256 {
        // Binary search
        let mut _min = 0_u256;
        let mut _max = max_epoch;

        let mut i = 0_u128;
        loop {
            // Will be always enough for 128-bit numbers
            if i >= 128 {
                break ();
            }

            if _min >= _max {
                break ();
            }

            let _mid = (_min + _max + 1) / 2;
            let blk = Escrow::_point_history::read(_mid).blk;
            if blk <= _block {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }

            i += 1;
        };

        _min
    }

    /// @notice Get the current voting power for `_tokenId`
    /// @dev Adheres to the ERC20 `balanceOf` interface for Aragon compatibility
    /// @param _tokenId NFT for lock
    /// @param _t Epoch time to return voting power at
    /// @return User voting power
    fn _balance_of_nft(_token_id: u256, _t: u128) -> u256 {
        let epoch = Escrow::_user_point_epoch::read(_token_id);
        if epoch == 0 {
            return 0;
        } else {
            let mut last_point = Escrow::_user_point_history::read((_token_id, epoch));

            last_point.bias -= last_point.slope * (to_i129(_t) - to_i129(last_point.ts));
            if last_point.bias < to_i129(0) {
                return 0;
            }

            return u128_to_u256(last_point.bias.inner);
        }
    }

    /// @notice Measure voting power of `_tokenId` at block height `_block`
    /// @dev Adheres to MiniMe `balanceOfAt` interface: https://github.com/Giveth/minime
    /// @param _tokenId User's wallet NFT
    /// @param _block Block to calculate the voting power at
    /// @return Voting power
    fn _balance_of_at_nft(_token_id: u256, _block: u128) -> u256 {
        // Copying and pasting totalSupply code because Vyper cannot pass by
        // reference yet
        assert(_block <= get_block_number_u128(), '_block less than now');

        // same with _find_block_epoch, but it use user_point_history
        // Binary search
        let mut _min = 0_u256;
        let mut _max = Escrow::_user_point_epoch::read(_token_id);

        let mut i = 0_u128;
        loop {
            // Will be always enough for 128-bit numbers
            if i >= 128 {
                break ();
            }

            if _min >= _max {
                break ();
            }

            let _mid = (_min + _max + 1) / 2;
            let blk = Escrow::_user_point_history::read((_token_id, _mid)).blk;
            if blk <= _block {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }

            i += 1;
        };

        let mut upoint = Escrow::_user_point_history::read((_token_id, _min));
        let max_epoch = Escrow::_epoch::read();
        let epoch = _find_block_epoch(_block, max_epoch);
        let point_0 = Escrow::_point_history::read(epoch);
        let mut d_block = 0_u128;
        let mut d_t = 0_u128;

        if epoch < max_epoch {
            let point_1 = Escrow::_point_history::read(epoch + 1);
            d_block = point_1.blk - point_0.blk;
            d_t = point_1.ts - point_0.ts;
        } else {
            d_block = get_block_number_u128() - point_0.blk;
            d_t = get_block_timestamp_u128() - point_0.ts;
        }

        let mut block_time = point_0.ts;
        if d_block != 0 {
            block_time += (d_t * (_block - point_0.blk)) / d_block;
        }

        upoint.bias -= upoint.slope * (to_i129(block_time - upoint.ts));
        if upoint.bias >= to_i129(0) {
            return u128_to_u256(upoint.bias.inner);
        } else {
            return 0;
        }
    }

    /// @notice Calculate total voting power at some point in the past
    /// @param _block Block to calculate the total voting power at
    /// @return Total voting power at `_block`
    fn total_supply_at_block(_block: u128) -> u256 {
        assert(_block <= get_block_number_u128(), '_block less than now');
        let epoch = Escrow::_epoch::read();
        let target_epoch = _find_block_epoch(_block, epoch);

        let point = Escrow::_point_history::read(target_epoch);
        let mut dt = 0_u128;
        if target_epoch < epoch {
            let mut point_next = Escrow::_point_history::read(target_epoch + 1);
            if point.blk != point_next.blk {
                dt = ((_block - point.blk) * (point_next.ts - point.ts))
                    / (point_next.blk - point.blk);
            }
        } else {
            if point.blk != get_block_number_u128() {
                dt = ((_block - point.blk) * (get_block_number_u128() - point.ts))
                    / (get_block_number_u128() - point.blk);
            }
        }
        // Now dt contains info on how far are we beyond point
        return _supply_at(point, point.ts + dt);
    }

    /// @notice Calculate total voting power at some point in the past
    /// @param point The point (bias/slope) to start search from
    /// @param t Time to calculate the total voting power at
    /// @return Total voting power at that time
    fn _supply_at(point: Point, t: u128) -> u256 {
        let mut last_point = point;
        let mut t_i = (last_point.ts / WEEK.low) * WEEK.low;
        let mut i = 0_usize;
        loop {
            if i >= 255_usize {
                break ();
            }

            t_i += WEEK.low;
            let mut d_slope = to_i129(0);
            if t_i > t {
                t_i = t;
            } else {
                d_slope = Escrow::_slope_changes::read(t_i);
            }
            last_point.bias -= last_point.slope * to_i129(t_i - last_point.ts);
            if t_i == t {
                break ();
            }
            last_point.slope += d_slope;
            last_point.ts = t_i;

            i += 1;
        };

        if last_point.bias < to_i129(0) {
            return 0;
        }

        return u128_to_u256(last_point.bias.inner);
    }
}
