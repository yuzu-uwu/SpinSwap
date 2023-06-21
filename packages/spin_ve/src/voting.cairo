#[contract]
mod Voting {
    use starknet::ContractAddress;
    use zeroable::Zeroable;
    use openzeppelin::tokens::erc721::{ERC721};
    use spin_lib::erc721_enumerable::{ERC721Enumerable};
    use spin_lib::utils::{get_block_timestamp_u128, and_and};
    use spin_ve::gauge::Gauge;
    use spin_ve::checkpoints::{Checkpoints};

    const MAX_DELEGATES: u256 = 1024; // avoid too much gas

    struct Storage {
        // The number of checkpoints for each account
        _num_checkpoints: LegacyMap::<ContractAddress, u32>,
        // A record of each accounts delegate
        _delegates: LegacyMap::<ContractAddress, ContractAddress>
    }

    #[event]
    fn DelegateChanged(
        delegator: ContractAddress, from_delegate: ContractAddress, to_delegate: ContractAddress
    ) {}

    //
    // @notice Overrides the standard `Comp.sol` delegates mapping to return
    // the delegator's own address if they haven't delegated.
    // This avoids having to delegate to oneself.
    //
    fn get_delegates(delegator: ContractAddress) -> ContractAddress {
        let current = _delegates::read(delegator);

        if current.is_zero() {
            return delegator;
        }

        current
    }

    //
    // @notice Gets the current votes balance for `account`
    // @param account The address to get votes balance
    // @return The number of current votes for `account`
    //
    fn get_votes(account: ContractAddress) -> u256 {
        let n_checkpoints = _num_checkpoints::read(account);
        if n_checkpoints == 0 {
            return 0;
        }

        let _len = Checkpoints::len(account, n_checkpoints - 1);
        let mut votes = 0_u256;
        let mut i = 0_u256;

        loop {
            if i >= _len {
                break ();
            }
            let t_id = Checkpoints::at(account, n_checkpoints - 1, i);
            votes = votes + Gauge::_balance_of_nft(t_id, get_block_timestamp_u128());
            i += 1;
        };

        votes
    }

    fn get_past_votes_index(account: ContractAddress, timestamp: u128) -> u32 {
        let n_checkpoints = _num_checkpoints::read(account);
        if n_checkpoints == 0 {
            return 0;
        }

        // First check most recent balance
        if Checkpoints::timestamp::read((account, n_checkpoints - 1)) <= timestamp {
            return n_checkpoints - 1;
        }

        // Next check implicit zero balance
        if Checkpoints::timestamp::read((account, 0)) > timestamp {
            return 0;
        }

        let mut lower = 0_u32;
        let mut upper = n_checkpoints - 1;
        let mut i = 0_u32;

        loop {
            if upper <= lower {
                break ();
            }

            let center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            let got_timestamp = Checkpoints::timestamp::read((account, center));
            if got_timestamp == timestamp {
                // return center;
                lower = center;
                break ();
            } else if got_timestamp < timestamp {
                lower = center
            } else {
                upper = center - 1;
            }

            i += 1; // just prevent tail expression 
        };

        lower
    }

    fn get_past_votes(account: ContractAddress, timestamp: u128) -> u256 {
        let _check_index = get_past_votes_index(account, timestamp);
        let token_ids_len = Checkpoints::len(account, _check_index);
        let mut votes = 0;
        let mut i = 0;

        loop {
            if i >= token_ids_len {
                break ();
            }
            let t_id = Checkpoints::at(account, _check_index, i);
            // Use the provided input timestamp here to get the right decay
            votes = votes + Gauge::_balance_of_nft(t_id, timestamp);

            i += 1;
        };

        votes
    }

    ///////////////////////////////////////////////////////////////
    //                        DAO VOTING LOGIC
    //////////////////////////////////////////////////////////////
    fn _move_token_delegates(src_rep: ContractAddress, dst_rep: ContractAddress, _token_id: u256) {
        if and_and(src_rep != dst_rep, _token_id > 0) {
            if src_rep != Zeroable::zero() {
                let src_rep_num = _num_checkpoints::read(src_rep);
                let mut old_src_rep_num = 0;

                if src_rep_num > 0 {
                    old_src_rep_num = src_rep_num - 1;
                }

                let next_src_rep_num = _find_what_checkpoint_to_write(src_rep);

                let mut i = 0_u256;

                loop {
                    if i >= Checkpoints::len(src_rep, old_src_rep_num) {
                        break ();
                    }

                    let t_id = Checkpoints::at(src_rep, old_src_rep_num, i);
                    if t_id != _token_id {
                        Checkpoints::append(src_rep, next_src_rep_num, t_id);
                    }

                    i += 1;
                };

                _num_checkpoints::write(src_rep, src_rep_num + 1);
            }

            if dst_rep != Zeroable::zero() {
                let dst_rep_num = _num_checkpoints::read(dst_rep);
                let mut old_dst_rep_num = 0;

                if dst_rep_num > 0 {
                    old_dst_rep_num = dst_rep_num - 1;
                }

                let next_dst_rep_num = _find_what_checkpoint_to_write(dst_rep);
                let old_dst_rep_len = Checkpoints::len(dst_rep, old_dst_rep_num);
                assert(old_dst_rep_len + 1 <= MAX_DELEGATES, 'dst would have too many tokens');

                let mut i = 0_u256;

                loop {
                    if i >= old_dst_rep_len {
                        break ();
                    }

                    let t_id = Checkpoints::at(dst_rep, old_dst_rep_num, i);

                    Checkpoints::append(dst_rep, next_dst_rep_num, t_id);

                    i += 1;
                };

                Checkpoints::append(dst_rep, next_dst_rep_num, _token_id);

                _num_checkpoints::write(dst_rep, dst_rep_num + 1);
            }
        }
    }

    fn _find_what_checkpoint_to_write(account: ContractAddress) -> u32 {
        let timestamp = get_block_timestamp_u128();
        let _n_checkpoints = _num_checkpoints::read(account);

        if _n_checkpoints > 0 {
            let checkpoint_timestamp = Checkpoints::timestamp::read((account, _n_checkpoints - 1));
            if checkpoint_timestamp == timestamp {
                return _n_checkpoints - 1;
            }
        }
        return _n_checkpoints;
    }

    fn _move_all_delegates(
        owner: ContractAddress, src_rep: ContractAddress, dst_rep: ContractAddress
    ) { // You can only redelegate what you own
        if src_rep != dst_rep {
            if src_rep != Zeroable::zero() {
                let src_rep_num = _num_checkpoints::read(src_rep);
                let mut old_src_rep_num = 0;

                if src_rep_num > 0 {
                    old_src_rep_num = src_rep_num - 1;
                }

                let next_src_rep_num = _find_what_checkpoint_to_write(src_rep);

                let mut i = 0;

                loop {
                    if i >= Checkpoints::len(src_rep, old_src_rep_num) {
                        break ();
                    }
                    let t_id = Checkpoints::at(src_rep, old_src_rep_num, i);

                    if ERC721::owner_of(t_id) != owner {
                        Checkpoints::append(src_rep, next_src_rep_num, t_id);
                    }

                    i += 1;
                };

                _num_checkpoints::write(src_rep, src_rep_num + 1);
            }

            if dst_rep != Zeroable::zero() {
                let dst_rep_num = _num_checkpoints::read(dst_rep);
                let mut old_dst_rep_num = 0;

                if dst_rep_num > 0 {
                    old_dst_rep_num = dst_rep_num - 1;
                }
                let next_dst_rep_num = _find_what_checkpoint_to_write(dst_rep);
                let old_dst_rep_len = Checkpoints::len(dst_rep, old_dst_rep_num);

                let owner_token_count = ERC721::balance_of(owner);
                assert(
                    old_dst_rep_len + owner_token_count <= MAX_DELEGATES,
                    'dst would have too many tokens'
                );

                // All the same
                let mut i = 0_u256;
                loop {
                    if i >= old_dst_rep_len {
                        break ();
                    }

                    let t_id = Checkpoints::at(dst_rep, old_dst_rep_num, i);
                    Checkpoints::append(dst_rep, next_dst_rep_num, t_id);

                    i += 1;
                };
                // Plus all that's owned
                let mut i = 0_u256;
                loop {
                    if i >= owner_token_count {
                        break ();
                    }
                    let t_id = ERC721Enumerable::token_of_owner_by_index(owner, i);
                    Checkpoints::append(dst_rep, next_dst_rep_num, t_id);
                    i += 1;
                };

                _num_checkpoints::write(dst_rep, dst_rep_num + 1);
            }
        }
    }

    fn _delegate(delegator: ContractAddress, delegatee: ContractAddress) {
        /// @notice differs from `_delegate()` in `Comp.sol` to use `delegates` override method to simulate auto-delegation
        let current_delegate = get_delegates(delegator);

        _delegates::write(delegator, delegatee);

        DelegateChanged(delegator, current_delegate, delegatee);
        _move_all_delegates(delegator, current_delegate, delegatee);
    }
}
