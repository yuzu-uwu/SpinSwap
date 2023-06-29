use array::SpanTrait;
use starknet::ContractAddress;
use openzeppelin::utils::serde::SpanSerde;

#[abi]
trait IPairCallee {
    #[external]
    fn hook(sender: ContractAddress, amount_0: u256, amount_1: u256, data: Span<felt252>);
}
