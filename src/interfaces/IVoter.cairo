#[abi]
trait IVoter {
    #[external]
    fn notify_reward_Amount(amount: u256);
}