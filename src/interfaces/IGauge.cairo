use starknet::ContractAddress;

#[abi]
trait IGauge {
    #[external]
    fn notify_reward_amount(token: ContractAddress, amount: u256);

    #[external]
    fn get_reward_by_distribution(account: ContractAddress);

    #[external]
    fn get_reward();

    #[external]
    fn claim_Fees() -> (u256, u256);

    #[external]
    fn set_distribution(distro_: ContractAddress);

    #[external]
    fn activate_emergency_mode();

    #[external]
    fn stop_emergency_mode();

    #[external]
    fn set_internal_bribe(intbribe: ContractAddress);

    #[external]
    fn set_rewarder_pid(pid: u256);

    #[external]
    fn set_gauge_rewarder(gr_: ContractAddress);

    #[external]
    fn set_fee_vault(fee_vault: ContractAddress);

    #[view]
    fn reward_rate(pair: ContractAddress) -> u256;

    #[view]
    fn balance_of(account: ContractAddress) -> u256;

    #[view]
    fn is_for_pair() -> bool;

    #[view]
    fn total_supply() -> u256;

    #[view]
    fn earned(token: ContractAddress, account: ContractAddress) -> u256;

    #[view]
    fn token() -> ContractAddress;
}
