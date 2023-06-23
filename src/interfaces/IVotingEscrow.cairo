use starknet::ContractAddress;
use array::ArrayTrait;
use array::SpanTrait;
use alexandria_math::signed_integers::{i129};
use openzeppelin::utils::serde::SpanSerde;
use spin_ve::types::{Point, LockedBalance};
use spin_ve::serde::I129Serde;

#[abi]
trait IVotingEscrow {
    #[external]
    fn create_lock(value: u256, lock_duration: u128) -> u256;

    #[external]
    fn create_lock_for(value: u256, lock_duration: u128, to: ContractAddress) -> u256;

    #[view]
    fn locked(token_id: u256) -> LockedBalance;

    #[view]
    fn token_of_owner_by_index(owner: ContractAddress, index: u256) -> u256;

    #[view]
    fn token() -> ContractAddress;

    #[view]
    fn team() -> ContractAddress;

    #[view]
    fn epoch() -> u256;

    #[view]
    fn point_history(loc: u256) -> Point;

    #[view]
    fn user_point_history(token_id: u256, loc: u256) -> Point;

    #[view]
    fn user_point_epoch(token_id: u256) -> u256;

    #[external]
    fn set_team(team: ContractAddress);

    #[external]
    fn set_art_proxy(art_proxy: ContractAddress);


    #[view]
    fn name() -> felt252;

    #[view]
    fn symbol() -> felt252;

    #[view]
    fn version() -> felt252;

    #[view]
    fn decimals() -> u8;

    #[external]
    fn token_uri(token_id: u256) -> Array<felt252>;

    #[view]
    fn owner_of(token_id: u256) -> ContractAddress;

    #[view]
    fn balance_of(account: ContractAddress) -> u256;

    #[view]
    fn get_approved(token_id: u256) -> ContractAddress;

    #[view]
    fn is_approved_for_all(owner: ContractAddress, operator: ContractAddress) -> bool;

    #[view]
    fn is_approved_or_owner(spender: ContractAddress, token_id: u256) -> bool;

    #[external]
    fn approve(to: ContractAddress, token_id: u256);

    #[external]
    fn set_approval_for_all(operator: ContractAddress, approved: bool);

    #[external]
    fn transfer_from(from: ContractAddress, to: ContractAddress, token_id: u256);

    #[external]
    fn safe_transfer_from(
        from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>
    );

    #[view]
    fn token_by_index(index: u256) -> u256;

    #[view]
    fn supports_interface(interface_id: u32) -> bool;

    #[view]
    fn voted(token_id: u256) -> bool;
    #[view]
    fn attachments(token_id: u256) -> u256;


    #[view]
    fn get_last_user_slope(token_id: u256) -> i129;

    #[view]
    fn user_point_history_ts(token_id: u256, idx: u256) -> u128;

    #[view]
    fn locked_end(token_id: u256) -> u128;

    #[view]
    fn block_number() -> u128;

    #[external]
    fn checkpoint();

    #[external]
    fn deposit_for(token_id: u256, value: u256);

    #[external]
    fn increase_amount(token_id: u256, value: u256);

    #[external]
    fn increase_unlock_time(token_id: u256, lock_duration: u128);

    #[external]
    fn withdraw(token_id: u256);

    #[view]
    fn balance_of_nft(token_id: u256) -> u256;

    #[view]
    fn balance_of_nft_at(token_id: u256, t: u128) -> u256;

    #[view]
    fn balance_of_at_nft(token_id: u256, block_: u128) -> u256;

    #[view]
    fn total_supply_at_block(block_: u128) -> u256;

    #[view]
    fn total_supply_at_timestamp(t: u128) -> u256;

    #[view]
    fn total_supply() -> u256;

    #[external]
    fn set_voter(voter: ContractAddress);

    #[external]
    fn voting(token_id: u256);

    #[external]
    fn abstain(token_id: u256);

    #[external]
    fn attach(token_id: u256);

    #[external]
    fn detach(token_id: u256);

    #[external]
    fn merge(from: u256, to: u256);

    #[external]
    fn split(amounts: Array<u256>, token_id: u256);

    #[view]
    fn delegates(delegator: ContractAddress) -> ContractAddress;

    #[view]
    fn get_votes(account: ContractAddress) -> u256;

    #[view]
    fn get_past_votes_index(account: ContractAddress, timestamp: u128) -> u32;

    #[view]
    fn get_past_votes(account: ContractAddress, timestamp: u128) -> u256;

    #[view]
    fn get_past_total_supply(timestamp: u128) -> u256;

    #[external]
    fn delegate(delegatee: ContractAddress);
}
