#[contract]
mod VE {
    use starknet::{ContractAddress, get_caller_address};
    use openzeppelin::token::erc721::{ERC721};
    use spin_ve::voting::Voting;
    use spin_ve::gauge_voting::GaugeVoting;
    use spin_lib::erc721_enumerable::{ERC721Enumerable};
    use spin_lib::utils::{and_and, get_block_number_u128};


    struct Storage {
        _token: ContractAddress,
        _token_counter: u256, // use as nft id, shuold increase from 1 (can't use 0 as id)
        _voter: ContractAddress,
        _team: ContractAddress,
        _art_proxy: ContractAddress,
        _ownership_change: LegacyMap::<u256,
        u128> // Set the block of ownership transfer (for Flash NFT protection)
    }


    fn set_team(team_: ContractAddress) {
        assert(get_caller_address() == _team::read(), 'veSpin: caller not allowed');

        _team::write(team_);
    }

    fn set_art_proxy(art_proxy_: ContractAddress) {
        assert(get_caller_address() == _team::read(), 'veSpin: caller not allowed');

        _art_proxy::write(art_proxy_);
    }

    fn increase_token_count() -> u256 {
        let old_count = _token_counter::read();
        let new_count = old_count + 1;

        _token_counter::write(new_count);

        return new_count;
    }

    fn _mint(to: ContractAddress, token_id: u256) {
        Voting::_move_token_delegates(Zeroable::zero(), Voting::get_delegates(to), token_id);
        ERC721Enumerable::_mint(to, token_id);
    }

    fn _burn(token_id: u256) {
        let owner = ERC721::_owner_of(token_id);

        Voting::_move_token_delegates(Voting::get_delegates(owner), Zeroable::zero(), token_id);
        ERC721Enumerable::_burn(token_id);
    }

    fn transfer_from(from: ContractAddress, to: ContractAddress, token_id: u256) {
        assert(
            and_and(
                GaugeVoting::_attachments::read(token_id) == 0, !GaugeVoting::_voted::read(token_id)
            ),
            'attached'
        );
        Voting::_move_token_delegates(
            Voting::get_delegates(from), Voting::get_delegates(to), token_id
        );
        // Set the block of ownership transfer (for Flash NFT protection)
        _ownership_change::write(token_id, get_block_number_u128());

        ERC721::transfer_from(from, to, token_id);
    }

    fn safe_transfer_from(
        from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>
    ) {
        assert(
            and_and(
                GaugeVoting::_attachments::read(token_id) == 0, !GaugeVoting::_voted::read(token_id)
            ),
            'attached'
        );
        Voting::_move_token_delegates(
            Voting::get_delegates(from), Voting::get_delegates(to), token_id
        );
        // Set the block of ownership transfer (for Flash NFT protection)
        _ownership_change::write(token_id, get_block_number_u128());

        ERC721::safe_transfer_from(from, to, token_id, data);
    }
}

