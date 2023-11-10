use starknet::ContractAddress;
use serde::Serde;
use core::array::ArrayTrait;
use array::SpanTrait;
use openzeppelin::utils::serde::SpanSerde;

#[derive(Copy, Drop, Serde)]
struct Metadata {
    decimals_0: u256,
    decimals_1: u256,
    reserve_0: u256,
    reserve_1: u256,
    stable: bool,
    token_0: ContractAddress,
    token_1: ContractAddress
}

#[derive(Copy, Drop, Serde)]
struct Observation {
    timestamp: u128,
    reserve_0_cumulative: u256,
    reserve_1_cumulative: u256
}

#[abi]
trait IPair {
    #[view]
    fn tokens() -> (ContractAddress, ContractAddress);

    #[view]
    fn observation_length() -> u256;

    #[view]
    fn last_observation() -> Observation;

    #[view]
    fn metadata() -> Metadata;

    #[view]
    fn is_stable() -> bool;

    #[external]
    fn claim_fees() -> (u256, u256);

    #[external]
    fn claim_staking_fees();

    #[view]
    fn get_reserves() -> (u256, u256, u128);

    #[view]
    fn current_cumulative_prices() -> (u256, u256, u128);

    #[view]
    fn get_amount_out(amount_in: u256, token_in: ContractAddress) -> u256;

    fn current(token_in: ContractAddress, amount_in: u256) -> u256;

    #[view]
    fn sample(
        token_in: ContractAddress, amount_in: u256, points: u256, window: u256
    ) -> Array<u256>;

    #[view]
    fn quote(token_in: ContractAddress, amount_in: u256, granularity: u256) -> u256;

    #[view]
    fn prices(token_in: ContractAddress, amount_in: u256, points: u256) -> Array<u256>;

    #[external]
    fn mint(to: ContractAddress) -> u256;

    #[external]
    fn burn(to: ContractAddress) -> (u256, u256);

    #[external]
    fn swap(amount_0_out: u256, amount_1_out: u256, to: ContractAddress, data: Span<felt252>);

    #[external]
    fn skim(to: ContractAddress);

    #[external]
    fn sync();
}
