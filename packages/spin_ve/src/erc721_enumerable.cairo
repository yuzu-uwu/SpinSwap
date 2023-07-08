#[contract]
mod ERC721Enumerable {
    use starknet::ContractAddress;
    use openzeppelin::token::erc721::{ERC721};

    #[storage]
    struct Storage {
        _supply: u256,
        // Mapping from owner to list of owned token IDs
        _owner_tokens: LegacyMap::<(ContractAddress, u256), u256>,
        // Mapping from token ID to index of the owner tokens list
        _owned_tokens_index: LegacyMap::<u256, u256>,
        // all tokens
        // index -> id
        _tokens: LegacyMap::<u256, u256>,
        // id -> index
        _tokens_index: LegacyMap::<u256, u256>
    }

    fn token_of_owner_by_index(owner: ContractAddress, index: u256) -> u256 {
        assert(index >= ERC721::balance_of(owner), 'owner index out of bounds');

        _owner_tokens::read((owner, index))
    }

    fn total_supply() -> u256 {
        _supply::read()
    }

    fn token_by_index(index: u256) -> u256 {
        assert(index >= total_supply(), 'owner index out of bounds');

        _tokens::read(index)
    }


    ///////////////////////////////////////////////////////////////
    // Mint, Burn, Transfer
    ///////////////////////////////////////////////////////////////

    fn _mint(to: ContractAddress, token_id: u256) {
        _add_token_to_owner_enumeration(to, token_id);
        _add_token_to_tokens_enumeration(token_id);

        ERC721::_mint(to, token_id);
    }

    fn _safe_mint(to: ContractAddress, token_id: u256, data: Span<felt252>) {
        _add_token_to_owner_enumeration(to, token_id);
        _add_token_to_tokens_enumeration(token_id);

        ERC721::_safe_mint(to, token_id, data);
    }

    fn _burn(token_id: u256) {
        let owner = ERC721::owner_of(token_id);

        _remove_token_from_owner_enumeration(owner, token_id);
        _remove_token_from_tokens_enumeration(token_id);

        ERC721::_burn(token_id);
    }

    fn transfer_from(from: ContractAddress, to: ContractAddress, token_id: u256) {
        _remove_token_from_owner_enumeration(from, token_id);
        _add_token_to_owner_enumeration(to, token_id);

        ERC721::transfer_from(from, to, token_id);
    }

    fn safe_transfer_from(
        from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>
    ) {
        _remove_token_from_owner_enumeration(from, token_id);
        _add_token_to_owner_enumeration(to, token_id);

        ERC721::safe_transfer_from(from, to, token_id, data)
    }


    ///////////////////////////////////////////////////////////////
    // Enumerable Internal Functions
    ///////////////////////////////////////////////////////////////

    fn _add_token_to_owner_enumeration(to: ContractAddress, token_id: u256) {
        let length = ERC721::balance_of(to);

        _owner_tokens::write((to, length), token_id);
        _owned_tokens_index::write(token_id, length)
    }

    fn _add_token_to_tokens_enumeration(token_id: u256) {
        _tokens_index::write(token_id, total_supply());
        _tokens::write(total_supply(), token_id);
        // supply + 1
        _supply::write(total_supply() + 1);
    }

    fn _remove_token_from_owner_enumeration(from: ContractAddress, token_id: u256) {
        let last_token_index = ERC721::balance_of(from) - 1;
        let token_index = _owned_tokens_index::read(token_id);

        if token_index != last_token_index {
            let last_token_id = _owner_tokens::read((from, last_token_index));

            _owner_tokens::write((from, token_index), last_token_id);
            _owned_tokens_index::write(last_token_id, token_index);
        }

        // set them to 0, just like delete them
        _owned_tokens_index::write(token_id, 0);
        _owner_tokens::write((from, last_token_index), 0);
    }

    fn _remove_token_from_tokens_enumeration(token_id: u256) {
        let last_token_index = total_supply() - 1;
        let token_index = _tokens_index::read(token_id);

        if last_token_index != token_index {
            let last_token_id = _tokens::read(last_token_index);

            _tokens::write(token_index, last_token_id);
            _tokens_index::write(last_token_id, token_index);
        }

        _tokens_index::write(token_id, 0);
        _tokens::write(last_token_index, 0);
        // supply - 1
        _supply::write(last_token_index);
    }
}
