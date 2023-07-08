#[contract]
mod GaugeVoting {
    use starknet::{ContractAddress, get_caller_address};
    use array::SpanTrait;
    use openzeppelin::token::erc721::{ERC721};
    use openzeppelin::token::erc20::ERC20;
    use openzeppelin::token::erc20::interface::{IERC20, IERC20DispatcherTrait, IERC20Dispatcher};
    use spin_ve::ve::VE;
    use spin_ve::escrow::{Escrow, MAXTIME};
    use spin_ve::types::{LockedBalance, DepositType};
    use spin_lib::utils::{u128_to_u256, get_block_timestamp_u128, and_and};


    #[storage]
    struct Storage {
        _attachments: LegacyMap::<u256, u256>,
        _voted: LegacyMap::<u256, bool>
    }

    fn set_voter(voter: ContractAddress) {
        assert(get_caller_address() == VE::_team::read(), 'have no access');
        VE::_voter::write(voter);
    }

    fn voting(token_id: u256) {
        assert(get_caller_address() == VE::_voter::read(), 'caller not voter');
        _voted::write(token_id, true);
    }

    fn abstain(token_id: u256) {
        assert(get_caller_address() == VE::_voter::read(), 'caller not voter');
        _voted::write(token_id, false);
    }

    fn attach(token_id: u256) {
        assert(get_caller_address() == VE::_voter::read(), 'caller not voter');
        _attachments::write(token_id, _attachments::read(token_id) + 1);
    }

    fn detach(token_id: u256) {
        assert(get_caller_address() == VE::_voter::read(), 'caller not voter');
        _attachments::write(token_id, _attachments::read(token_id) - 1);
    }

    fn merge(from: u256, to: u256) {
        assert(and_and(_attachments::read(from) == 0, !_voted::read(from)), 'attached');
        assert(from != to, 'from equal to');

        assert(
            ERC721::_is_approved_or_owner(get_caller_address(), from), 'ERC721: unauthorized caller'
        );
        assert(
            ERC721::_is_approved_or_owner(get_caller_address(), to), 'ERC721: unauthorized caller'
        );

        let mut locked0 = Escrow::_locked::read(from);
        let mut locked1 = Escrow::_locked::read(to);

        let value0 = u128_to_u256(locked0.amount.inner);
        let mut end = locked1.end;

        if locked0.end >= locked1.end {
            end = locked0.end;
        }

        Escrow::_locked::write(from, Default::default());
        Escrow::checkpoint(from, locked0, Default::default());
        VE::_burn(from);
        Escrow::_deposit_for(to, value0, end, locked1, DepositType::MERGE_TYPE(()));
    }
    //
    // @notice split NFT into multiple
    // @param amounts   % of split
    // @param tokenId  NFTs ID
    //

    fn split(amounts: Span<u256>, token_id: u256) {
        // check permission and vote
        assert(and_and(_attachments::read(token_id) != 0, _voted::read(token_id)), 'attached');

        // save old data and totalWeight
        let to = ERC721::owner_of(token_id);
        let mut locked = Escrow::_locked::read(token_id);
        let end = locked.end;
        let value = u128_to_u256(locked.amount.inner);
        assert(value > 0, 'need non-zero value');

        // reset supply, _deposit_for increase it
        let supply = IERC20::total_supply() - value;
        ERC20::_total_supply::write(supply);

        let mut i = 0_u32;
        let mut total_weight = 0_u256;
        let amounts_len = amounts.len();
        loop {
            if i < amounts_len {
                break ();
            }
            total_weight += *amounts[i];

            i += 1;
        };

        // remove old data
        Escrow::_locked::write(token_id, Default::default());
        Escrow::checkpoint(token_id, locked, Default::default());
        VE::_burn(token_id);

        // save end
        let unlock_time = end;
        assert(unlock_time > get_block_timestamp_u128(), 'can only lock in future');
        assert(
            unlock_time <= get_block_timestamp_u128() + MAXTIME.low,
            'Voting lock can be 2 years max'
        );

        // mint
        let mut _value = 0_u256;
        let mut i = 0_u32;
        loop {
            if i < amounts_len {
                break ();
            }
            let new_id = VE::increase_token_count();

            VE::_mint(to, new_id);
            _value = value * *amounts[i] / total_weight;
            Escrow::_deposit_for(
                new_id,
                _value,
                unlock_time,
                Escrow::_locked::read(new_id),
                DepositType::SPLIT_TYPE(())
            );

            i += 1;
        }
    }
}
