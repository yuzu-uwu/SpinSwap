
use starknet::ContractAddress;

#[abi]
trait IPermissionsRegistry {
    #[view]
    fn emergency_council() -> ContractAddress;

    #[view]
    fn spin_team_multisig() -> ContractAddress;

    #[view]
    fn has_role(role: felt252, caller: ContractAddress) -> bool;
}