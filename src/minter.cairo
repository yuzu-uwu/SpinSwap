#[contract]
mod Minter {
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use zeroable::Zeroable;
    use array::ArrayTrait;
    use array::SpanTrait;
    use integer::{BoundedInt};
    use openzeppelin::access::ownable::Ownable;
    use spinswap::interfaces::ISpin::{ISpinDispatcher, ISpinDispatcherTrait};
    use spinswap::interfaces::IVoter::{IVoterDispatcher, IVoterDispatcherTrait};
    use spinswap::interfaces::IVotingEscrow::{
        IVotingEscrowDispatcher, IVotingEscrowDispatcherTrait
    };
    use spinswap::interfaces::IRewardsDistributor::{
        IRewardsDistributorDispatcher, IRewardsDistributorDispatcherTrait
    };
    use spin_lib::utils::{get_block_timestamp_u128, get_block_number_u128, and_and, u128_to_u256};
    use spin_lib::math::Math;

    // use spinswap::interfaces::

    const WEEK: u128 = 604800; // 7 * 86400
    const PRECISION: u256 = 1000;
    const MAX_TEAM_RATE: u256 = 50; // 5%
    const LOCK: u256 = 62899200; //86400 * 7 * 52 * 2;


    struct Storage {
        _is_first_mint: bool,
        _emission: u256,
        _tail_emission: u256,
        _rebase_max: u256,
        _team_rate: u256,
        _weekly: u256, //represents a starting weekly emission of SPIN (SPIN has 18 decimals)
        _active_period: u128,
        // account
        _initializer: ContractAddress,
        _team: ContractAddress,
        _pending_team: ContractAddress,
        // contracts
        _spin_address: ContractAddress,
        _voter_address: ContractAddress,
        _ve_address: ContractAddress,
        _rewards_distributor_address: ContractAddress
    }

    #[event]
    fn Mint(
        sender: ContractAddress, weekly: u256, circulating_supply: u256, circulating_emission: u256
    ) {}

    #[constructor]
    fn cnstructor(
        voter_: ContractAddress, // the voting & distribution system
        ve_: ContractAddress, // the ve(3,3) system that will be locked into
        rewards_distributor_: ContractAddress // the distribution system that ensures users aren't diluted
    ) {
        let caller = get_caller_address();

        Ownable::_transfer_ownership(caller);
        _initializer::write(caller);
        _team::write(caller);

        _team_rate::write(40); // 4%

        _emission::write(990);
        _tail_emission::write(2);
        _rebase_max::write(300);

        _spin_address::write(IVotingEscrowDispatcher { contract_address: ve_ }.token());
        _voter_address::write(voter_);
        _ve_address::write(ve_);
        _rewards_distributor_address::write(rewards_distributor_);

        let block_timestamp = get_block_timestamp_u128();

        _active_period::write(((block_timestamp + (2 * WEEK)) / WEEK) * WEEK);
        _weekly::write(
            2_600_000_u256 * 1_000_000_000_000_000_000_u256
        ); // represents a starting weekly emission of 2.6M SPIN (SPIN has 18 decimals)
        _is_first_mint::write(true);
    }

    #[external]
    // sum amounts / max = % ownership of top protocols, 
    // so if initial 20m is distributed, 
    // and target is 25% protocol ownership, then max - 4 x 20m = 80m
    fn initialize(claimants: Array<ContractAddress>, amounts: Array<u256>, max: u256) {
        assert(_initializer::read() == get_caller_address(), 'have no access');
        if max > 0 {
            _spin().mint(get_contract_address(), max);
            _spin().approve(_ve_address::read(), BoundedInt::max());

            let mut i = 0_usize;
            loop {
                if i >= claimants.len() {
                    break ();
                }
                _ve().create_lock_for(*amounts[i], LOCK.low, *claimants[i]);

                i += 1;
            };
        }

        _initializer::write(Zeroable::zero());
        _active_period::write((get_block_timestamp_u128() / WEEK) * WEEK);
    }

    #[external]
    fn set_team(team_: ContractAddress) {
        _assert_only_team();
        _pending_team::write(team_);
    }

    #[external]
    fn accept_team() {
        assert(get_caller_address() == _pending_team::read(), 'not pending team');
        _team::write(_pending_team::read());
    }

    #[external]
    fn set_voter(voter_: ContractAddress) {
        assert(voter_.is_non_zero(), 'zero address will not accepted');
        _assert_only_team();

        _voter_address::write(voter_);
    }

    #[external]
    fn set_team_rate(team_rate_: u256) {
        _assert_only_team();
        assert(team_rate_ <= MAX_TEAM_RATE, 'rate too high');
        _team_rate::write(team_rate_);
    }

    #[external]
    fn set_emission(emission_: u256) {
        _assert_only_team();
        assert(emission_ <= PRECISION, 'rate too high');
        _emission::write(emission_);
    }

    #[external]
    fn set_rebase(rebase_: u256) {
        _assert_only_team();
        assert(rebase_ <= PRECISION, 'rate too high');
        _rebase_max::write(rebase_);
    }

    #[external]
    fn set_reward_distributor(reward_distributor_: ContractAddress) {
        _assert_only_team();
        _rewards_distributor_address::write(reward_distributor_);
    }

    #[view]
    fn active_period() -> u128 {
        _active_period::read()
    }

    // calculate circulating supply as total token supply - locked supply
    #[view]
    fn circulating_supply() -> u256 {
        _spin().total_supply() - _spin().balance_of(_ve_address::read())
    }

    // emission calculation is 1% of available supply to mint adjusted by circulating / total supply
    #[view]
    fn calculate_emission() -> u256 {
        _weekly::read() * _emission::read() / PRECISION
    }

    // calculates tail end (infinity) emissions as 0.2% of total supply
    #[view]
    fn circulating_emission() -> u256 {
        (circulating_supply() * _tail_emission::read()) / PRECISION
    }

    // weekly emission takes the max of calculated (aka target) emission versus circulating tail end emission
    #[view]
    fn weekly_emission() -> u256 {
        Math::max(calculate_emission(), circulating_emission())
    }

    // calculate inflation and adjust ve balances accordingly
    #[view]
    fn calculate_rebate(weekly_mint_: u256) -> u256 {
        let ve_total = _spin().balance_of(_ve_address::read());
        let spin_total = _spin().total_supply();

        let locked_share = ve_total * PRECISION / spin_total;
        if locked_share >= _rebase_max::read() {
            return weekly_mint_ * _rebase_max::read() / PRECISION;
        } else {
            return weekly_mint_ * locked_share / PRECISION;
        }
    }

    //update period can only be called once per cycle (1 week)
    #[view]
    fn update_period() -> u128 {
        let mut period = _active_period::read();

        let block_timestamp = get_block_timestamp_u128();
        let initializer = _initializer::read();

        if and_and(block_timestamp >= period + WEEK, initializer.is_zero()) {
            period = (block_timestamp / WEEK) * WEEK;
            _active_period::write(period);

            if _is_first_mint::read() {
                _weekly::write(weekly_emission());
            } else {
                _is_first_mint::write(false);
            }

            let rebase = calculate_rebate(_weekly::read());
            let team_emissions = _weekly::read() * _team_rate::read() / PRECISION;
            let required = _weekly::read();

            let gauge = _weekly::read() - rebase - team_emissions;

            let balance_of = _spin().balance_of(get_contract_address());
            if balance_of < required {
                _spin().mint(get_contract_address(), required - balance_of);
            }

            assert(_spin().transfer(_team::read(), team_emissions), 'can not transfer to team');
            assert(
                _spin().transfer(_rewards_distributor_address::read(), rebase),
                'can not transfer to reward'
            );

            _rewards_distributor()
                .checkpoint_token(); // checkpoint token balance that was just minted in rewards distributor
            _rewards_distributor().checkpoint_total_supply(); // checkpoint supply

            _spin().approve(_voter_address::read(), gauge);
            _voter().notify_reward_Amount(gauge);

            Mint(
                get_caller_address(), _weekly::read(), circulating_supply(), circulating_emission()
            );
        }

        period
    }

    #[view]
    fn check() -> bool {
        let period = _active_period::read();
        let block_timestamp = get_block_timestamp_u128();
        let initializer = _initializer::read();

        and_and(block_timestamp >= period + WEEK, initializer.is_zero())
    }

    #[view]
    fn period() -> u128 {
        get_block_timestamp_u128() / WEEK * WEEK
    }

    fn _assert_only_team() {
        let team: ContractAddress = _team::read();
        let caller: ContractAddress = get_caller_address();
        assert(!caller.is_zero(), 'Caller is the zero address');
        assert(caller == team, 'Caller is not the team');
    }

    fn _spin() -> ISpinDispatcher {
        ISpinDispatcher { contract_address: _spin_address::read() }
    }

    fn _voter() -> IVoterDispatcher {
        IVoterDispatcher { contract_address: _voter_address::read() }
    }

    fn _ve() -> IVotingEscrowDispatcher {
        IVotingEscrowDispatcher { contract_address: _ve_address::read() }
    }

    fn _rewards_distributor() -> IRewardsDistributorDispatcher {
        IRewardsDistributorDispatcher { contract_address: _rewards_distributor_address::read() }
    }
}
