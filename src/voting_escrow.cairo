use core::zeroable::Zeroable;
#[contract]
mod VotingEscrow {
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use array::ArrayTrait;
    use zeroable::Zeroable;
    use openzeppelin::introspection::erc165::ERC165;
    use openzeppelin::tokens::erc721::{ERC721};
    use openzeppelin::tokens::erc20::{ERC20, IERC20};
    use openzeppelin::security::reentrancyguard::ReentrancyGuard;
    use openzeppelin::utils::constants::{IERC721_ID, IERC721_METADATA_ID};
    use alexandria_math::signed_integers::{i129};
    use spinswap::interfaces::ve_art_proxy::{IVeArtProxyDispatcher, IVeArtProxyDispatcherTrait};
    // use spinswap::ve_art_proxy::{IVeArtProxy, IVeArtProxyDispatcher};

    use spin_ve::ve::VE;
    use spin_ve::escrow::Escrow;
    use spin_ve::gauge::Gauge;
    use spin_ve::gauge_voting::GaugeVoting;
    use spin_ve::voting::Voting;
    use spin_ve::types::{LockedBalance, DepositType, Point};
    use spin_ve::utils::{to_i129};
    use spin_lib::string::u128_to_ascii;
    use spin_lib::utils::{u128_to_u256, get_block_timestamp_u128, get_block_number_u128};
    use spin_lib::erc721_enumerable::ERC721Enumerable;


    const NAME: felt252 = 'veSpin';
    const SYMBOL: felt252 = 'veSPIN';
    const VERSION: felt252 = '1.0.0';

    /// @notice Contract constructor
    /// @param token_addr `SPIN` token addresss
    #[constructor]
    fn cnstructor(token_addr: ContractAddress, art_proxy: ContractAddress) {
        let caller = get_caller_address();

        VE::_token::write(token_addr);
        VE::_voter::write(caller);
        VE::_team::write(caller);
        VE::_art_proxy::write(art_proxy);

        let mut point: Point = Default::default();
        point.blk = get_block_number_u128();
        point.ts = get_block_timestamp_u128();

        Escrow::_point_history::write(0, point);

        ERC165::register_interface(IERC721_ID);
        ERC165::register_interface(IERC721_METADATA_ID);

        // token 0: mint-ish
        ERC721::Transfer(Zeroable::zero(), get_contract_address(), 0);
        // token 0: burn-ish
        ERC721::Transfer(get_contract_address(), Zeroable::zero(), 0);
    }


    #[view]
    fn name() -> felt252 {
        NAME
    }

    #[view]
    fn symbol() -> felt252 {
        SYMBOL
    }

    #[view]
    fn version() -> felt252 {
        VERSION
    }

    #[view]
    fn decimals() -> u8 {
        IERC20::decimals()
    }

    #[external]
    fn set_team(team: ContractAddress) {
        VE::set_team(team);
    }

    #[external]
    fn set_art_proxy(art_proxy: ContractAddress) {
        VE::set_art_proxy(art_proxy);
    }
    //////////////////////////////////////////////////////////////
    // ERC721
    //////////////////////////////////////////////////////////////
    #[external]
    fn token_uri(token_id: u256) -> Array<felt252> {
        // check nonexistent token
        ERC721::owner_of(token_id);
        let locked = Escrow::_locked::read(token_id);

        IVeArtProxyDispatcher {
            contract_address: VE::_art_proxy::read()
        }
            .base_uri(
                token_id,
                Gauge::_balance_of_nft(token_id, get_block_timestamp_u128()),
                locked.end,
                u128_to_u256(locked.amount.inner)
            )
    }

    #[view]
    fn owner_of(token_id: u256) -> ContractAddress {
        ERC721::owner_of(token_id)
    }

    #[view]
    fn balance_of(account: ContractAddress) -> u256 {
        ERC721::balance_of(account)
    }

    #[view]
    fn get_approved(token_id: u256) -> ContractAddress {
        ERC721::get_approved(token_id)
    }

    #[view]
    fn is_approved_for_all(owner: ContractAddress, operator: ContractAddress) -> bool {
        ERC721::is_approved_for_all(owner, operator)
    }

    #[view]
    fn is_approved_or_owner(spender: ContractAddress, token_id: u256) -> bool {
        ERC721::_is_approved_or_owner(spender, token_id)
    }

    #[external]
    fn approve(to: ContractAddress, token_id: u256) {
        ERC721::approve(to, token_id)
    }

    #[external]
    fn set_approval_for_all(operator: ContractAddress, approved: bool) {
        ERC721::set_approval_for_all(operator, approved)
    }

    #[external]
    fn transfer_from(from: ContractAddress, to: ContractAddress, token_id: u256) {
        VE::transfer_from(from, to, token_id)
    }

    #[external]
    fn safe_transfer_from(
        from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>
    ) {
        VE::safe_transfer_from(from, to, token_id, data)
    }

    //////////////////////////////////////////////////////////////
    //     ERC721 Enumerable
    //////////////////////////////////////////////////////////////

    #[view]
    fn token_of_owner_by_index(owner: ContractAddress, index: u256) -> u256 {
        ERC721Enumerable::token_of_owner_by_index(owner, index)
    }

    #[view]
    fn token_by_index(index: u256) -> u256 {
        ERC721Enumerable::token_by_index(index)
    }

    #[view]
    fn supports_interface(interface_id: u32) -> bool {
        ERC165::supports_interface(interface_id)
    }

    //////////////////////////////////////////////////////////////
    //ESCROW
    //////////////////////////////////////////////////////////////
    #[view]
    fn get_last_user_slope(token_id: u256) -> i129 {
        Escrow::get_last_user_slope(token_id)
    }

    #[view]
    fn user_point_history_ts(token_id: u256, idx: u256) -> u128 {
        Escrow::user_point_history_ts(token_id, idx)
    }

    #[view]
    fn locked_end(token_id: u256) -> u128 {
        Escrow::locked_end(token_id)
    }

    #[view]
    fn block_number() -> u128 {
        get_block_number_u128()
    }

    #[external]
    fn checkpoint() {
        Escrow::checkpoint(0, Default::default(), Default::default())
    }

    #[external]
    fn deposit_for(token_id: u256, value: u256) {
        ReentrancyGuard::start();
        let locked = Escrow::_locked::read(token_id);

        assert(value > 0, 'need non-zero value');
        assert(locked.amount > to_i129(0), 'No existing lock found');
        assert(locked.end > get_block_timestamp_u128(), 'expired, Withdraw');
        Escrow::_deposit_for(token_id, value, 0, locked, DepositType::DEPOSIT_FOR_TYPE(()));

        ReentrancyGuard::end();
    }

    #[external]
    fn create_lock(value: u256, lock_duration: u128) -> u256 {
        ReentrancyGuard::start();
        let token_id = Escrow::_create_lock(value, lock_duration, get_caller_address());
        ReentrancyGuard::end();

        token_id
    }

    #[external]
    fn increase_amount(token_id: u256, value: u256) {
        ReentrancyGuard::start();
        Escrow::increase_amount(token_id, value);
        ReentrancyGuard::end();
    }

    #[external]
    fn increase_unlock_time(token_id: u256, lock_duration: u128) {
        ReentrancyGuard::start();
        Escrow::increase_unlock_time(token_id, lock_duration);
        ReentrancyGuard::end();
    }

    #[external]
    fn withdraw(token_id: u256) {
        ReentrancyGuard::start();
        Escrow::withdraw(token_id);
        ReentrancyGuard::end();
    }

    ///////////////////////////////////////////////////////////////
    // Gauge
    ///////////////////////////////////////////////////////////////

    #[view]
    fn balance_of_nft(token_id: u256) -> u256 {
        if VE::_ownership_change::read(token_id) == get_block_number_u128() {
            return 0;
        }
        Gauge::_balance_of_nft(token_id, get_block_timestamp_u128())
    }

    #[view]
    fn balance_of_nft_at(token_id: u256, t: u128) -> u256 {
        Gauge::_balance_of_nft(token_id, t)
    }

    #[view]
    fn balance_of_at_nft(token_id: u256, block_: u128) -> u256 {
        Gauge::_balance_of_at_nft(token_id, block_)
    }

    #[view]
    fn total_supply_at_block(block_: u128) -> u256 {
        Gauge::total_supply_at_block(block_)
    }

    #[view]
    fn total_supply_at_timestamp(t: u128) -> u256 {
        let epoch = Escrow::_epoch::read();
        let last_point = Escrow::_point_history::read(epoch);
        Gauge::_supply_at(last_point, t)
    }

    #[view]
    fn total_supply() -> u256 {
        total_supply_at_timestamp(get_block_timestamp_u128())
    }

    #[external]
    fn set_voter(voter: ContractAddress) {
        GaugeVoting::set_voter(voter)
    }

    #[external]
    fn voting(token_id: u256) {
        GaugeVoting::voting(token_id)
    }

    #[external]
    fn abstain(token_id: u256) {
        GaugeVoting::abstain(token_id)
    }

    #[external]
    fn attach(token_id: u256) {
        GaugeVoting::attach(token_id)
    }

    #[external]
    fn detach(token_id: u256) {
        GaugeVoting::detach(token_id)
    }

    #[external]
    fn merge(from: u256, to: u256) {
        GaugeVoting::merge(from, to)
    }

    #[external]
    fn split(amounts: Array<u256>, token_id: u256) {
        GaugeVoting::split(amounts.span(), token_id)
    }
    ///////////////////////////////////////////////////////////////
    // DAO Voting
    ///////////////////////////////////////////////////////////////

    #[view]
    fn delegates(delegator: ContractAddress) -> ContractAddress {
        Voting::get_delegates(delegator)
    }

    #[view]
    fn get_votes(account: ContractAddress) -> u256 {
        Voting::get_votes(account)
    }

    #[view]
    fn get_past_votes_index(account: ContractAddress, timestamp: u128) -> u32 {
        Voting::get_past_votes_index(account, timestamp)
    }

    #[view]
    fn get_past_votes(account: ContractAddress, timestamp: u128) -> u256 {
        Voting::get_past_votes(account, timestamp)
    }

    #[view]
    fn get_past_total_supply(timestamp: u128) -> u256 {
        total_supply_at_timestamp(timestamp)
    }

    #[external]
    fn delegate(delegatee: ContractAddress) {
        let mut delegatee = delegatee;
        if delegatee.is_zero() {
            delegatee = get_caller_address()
        }

        Voting::_delegate(get_caller_address(), delegatee)
    }
}

