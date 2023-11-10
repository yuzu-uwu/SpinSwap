#[contract]
mod Router {
    use serde::Serde;
    use core::array::ArrayTrait;
    use array::SpanTrait;
    use integer::u256_sqrt;
    use zeroable::Zeroable;
    use starknet::class_hash::ClassHash;
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp};
    use spinswap::interfaces::IPairFactory::{IPairFactoryDispatcher, IPairFactoryDispatcherTrait};
    use spinswap::interfaces::IPair::{IPairDispatcher, IPairDispatcherTrait};
    use openzeppelin::token::erc20::interface::{IERC20, IERC20DispatcherTrait, IERC20Dispatcher};
    use spin_lib::math::Math;
    use spin_lib::utils::sort_token;

    const MINIMUM_LIQUIDITY: u256 = 1000; // 10 ** 3

    #[derive(Copy, Drop, Serde)]
    struct route {
        from: ContractAddress,
        to: ContractAddress,
        stable: bool
    }

    #[storage]
    struct Storage {
        _factory: ContractAddress,
        _pair_class_hash: ClassHash
    }

    #[event]
    fn Swap(
        sender: ContractAddress,
        amount_0_in: u256,
        token_in_: ContractAddress,
        to: ContractAddress,
        stable: bool
    ) {}

    #[constructor]
    fn constructor(factory_: ContractAddress) {
        _factory::write(factory_);
        let pair_class_hash = IPairFactoryDispatcher {
            contract_address: factory_
        }.pair_class_hash();
        _pair_class_hash::write(pair_class_hash);
    }


    #[view]
    fn pair_for(
        token_a: ContractAddress, token_b: ContractAddress, stable: bool
    ) -> ContractAddress {
        let (token_0, token_1) = sort_token(token_a, token_b);
        pair_factory().get_pair(token_0, token_1, stable)
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    // return amount b
    #[view]
    fn quote_liquidity(amount_a: u256, reserve_a: u256, reserve_b: u256) -> u256 {
        assert(amount_a > 0, 'Router: INSUFFICIENT_AMOUNT');
        assert(reserve_a > 0 & reserve_b > 0, 'Router: INSUFFICIENT_LIQUIDITY');
        amount_a * reserve_b / reserve_a
    }

    // fetches and sorts the reserves for a pair
    // return reserve a, reserve b
    #[view]
    fn get_reserves(
        token_a: ContractAddress, token_b: ContractAddress, stable: bool
    ) -> (u256, u256) {
        let (token_0, token_1) = sort_token(token_a, token_b);
        let (reserve_0, reserve_1, _) = IPairDispatcher {
            contract_address: pair_for(token_a, token_b, stable)
        }.get_reserves();
        let (reserve_a, reserve_b) = if (token_a == token_0) {
            (reserve_0, reserve_1)
        } else {
            (reserve_1, reserve_0)
        };

        (reserve_0, reserve_1)
    }

    // performs chained getAmountOut calculations on any number of pairs
    // (amount, stable)
    #[view]
    fn get_amount_out(
        amount_in: u256, token_in: ContractAddress, token_out: ContractAddress
    ) -> (u256, bool) {
        let pair = pair_for(token_in, token_out, true);
        let mut amount_stable = 0_u256;
        let mut amount_volatile = 0_u256;
        if pair_factory().is_pair(pair) {
            amount_stable = IPairDispatcher {
                contract_address: pair
            }.get_amount_out(amount_in, token_in);
        }

        let pair = pair_for(token_in, token_out, false);
        if pair_factory().is_pair(pair) {
            amount_volatile = IPairDispatcher {
                contract_address: pair
            }.get_amount_out(amount_in, token_in);
        }

        let (amount, stable) = if amount_stable > amount_volatile {
            (amount_stable, true)
        } else {
            (amount_volatile, false)
        };

        (amount, stable)
    }

    #[view]
    fn get_amounts_out(amount_in: u256, routes: Array<route>) -> Array<u256> {
        assert(routes.len() >= 1, 'Router: INVALID_PATH');
        let mut amounts = ArrayTrait::<u256>::new();
        let mut i = 0_usize;

        amounts.append(amount_in);

        loop {
            if i >= routes.len() {
                break ();
            }

            let route_ = *routes[i];
            let pair = pair_for(route_.from, route_.to, route_.stable);
            if pair_factory().is_pair(pair) {
                let amounts_snapshot = @amounts;

                let amount = IPairDispatcher {
                    contract_address: pair
                }.get_amount_out(*amounts_snapshot[i], route_.from);
                amounts.append(amount);
            }

            i = i + 1;
        };

        amounts
    }

    #[view]
    fn is_pair(pair: ContractAddress) -> bool {
        pair_factory().is_pair(pair)
    }

    #[view]
    // return amount_a, amount_b, liquidity
    fn quote_add_liquidity(
        token_a: ContractAddress,
        token_b: ContractAddress,
        stable: bool,
        amount_a_desired: u256,
        amount_b_desired: u256
    ) -> (u256, u256, u256) {
        //  create the pair if it doesn't exist yet
        let pair_ = pair_for(token_a, token_b, stable);
        let mut reserve_a = 0_u256;
        let mut reserve_b = 0_u256;
        let mut total_supply_ = 0_u256;
        let mut amount_a = 0_u256;
        let mut amount_b = 0_u256;
        let mut liquidity = 0_u256;

        if pair_.is_non_zero() {
            total_supply_ = IERC20Dispatcher { contract_address: pair_ }.total_supply();
            let (reserve_a_, reserve_b_) = get_reserves(token_a, token_b, stable);
            reserve_b = reserve_a_;
            reserve_b = reserve_b_;
        }
        if reserve_a == 0 & reserve_b == 0 {
            amount_a = amount_a_desired;
            amount_b = amount_b_desired;
            liquidity = u256 { low: u256_sqrt(amount_a * amount_b), high: 0 } - MINIMUM_LIQUIDITY;
        } else {
            let amount_b_optimal = quote_liquidity(amount_a_desired, reserve_a, reserve_b);
            if amount_b_optimal <= amount_b_desired {
                amount_a = amount_a_desired;
                amount_b = amount_b_optimal;
            } else {
                let amount_a_optimal = quote_liquidity(amount_b_desired, reserve_b, reserve_a);
                amount_a = amount_a_optimal;
                amount_b = amount_b_desired;
            }
            liquidity =
                Math::<u256>::min(
                    amount_a * total_supply_ / reserve_a, amount_b * total_supply_ / reserve_b
                );
        }

        (amount_a, amount_b, liquidity)
    }

    #[view]
    fn quote_remove_liquidity(
        token_a: ContractAddress, token_b: ContractAddress, stable: bool, liquidity: u256
    ) -> (u256, u256) {
        //  create the pair if it doesn't exist yet
        let pair_ = pair_for(token_a, token_b, stable);
        if pair_.is_zero() {
            return (0, 0);
        }
        let (reserve_a, reserve_b) = get_reserves(token_a, token_b, stable);
        let total_supply_ = IERC20Dispatcher { contract_address: pair_ }.total_supply();

        let amount_a = liquidity
            * reserve_a
            / total_supply_; // using balances ensures pro-rata distribution
        let amount_b = liquidity * reserve_b / total_supply_;

        (amount_a, amount_b)
    }

    fn _add_liquidity(
        token_a: ContractAddress,
        token_b: ContractAddress,
        stable: bool,
        amount_a_desired: u256,
        amount_b_desired: u256,
        amount_a_min: u256,
        amount_b_min: u256
    ) -> (u256, u256) //return amount a, amount b
    {
        assert(amount_a_desired >= amount_a_min, 'wrong a amount');
        assert(amount_b_desired >= amount_b_min, 'wrong b amount');
        // create the pair if it doesn't exist yet
        let mut pair_ = pair_for(token_a, token_b, stable);
        if pair_.is_zero() {
            pair_ = pair_factory().create_pair(token_a, token_b, stable);
        }
        let mut amount_a = 0_u256;
        let mut amount_b = 0_u256;

        let (reserve_a, reserve_b) = get_reserves(token_a, token_b, stable);
        if reserve_a == 0 & reserve_b == 0 {
            amount_a = amount_a_desired;
            amount_b = amount_b_desired;
        } else {
            let amount_b_optimal = quote_liquidity(amount_a_desired, reserve_a, reserve_b);
            if amount_b_optimal <= amount_b_desired {
                assert(amount_b_optimal >= amount_b_min, 'Router: INSUFFICIENT_B_AMOUNT');
                amount_a = amount_a_desired;
                amount_b = amount_b_desired;
            } else {
                let amount_a_optimal = quote_liquidity(amount_b_desired, reserve_b, reserve_a);
                assert(amount_a_optimal <= amount_a_desired, 'amount a desired too large');
                assert(amount_a_optimal >= amount_a_min, 'Router: INSUFFICIENT_A_AMOUNT');
                amount_a = amount_a_optimal;
                amount_b = amount_b_desired;
            }
        }

        (amount_a, amount_b)
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    fn _swap(amounts: Array<u256>, routes: Array<route>, to_: ContractAddress) {
        let mut i = 0;
        let empty_array = ArrayTrait::<felt252>::new();
        let empty_span = empty_array.span();
        loop {
            if i >= routes.len() {
                break ();
            }
            let route_ = *routes[i];
            let (token_0, _) = sort_token(route_.from, route_.to);
            let amount_out = *amounts[i + 1];
            let (amount_0_out, amount_1_out) = if route_.from == token_0 {
                (0_u256, amount_out)
            } else {
                (amount_out, 0_u256)
            };
            let to = if i < routes.len() - 1 {
                pair_for(*routes[i + 1].from, *routes[i + 1].to, *routes[i + 1].stable)
            } else {
                to_
            };
            IPairDispatcher {
                contract_address: pair_for(route_.from, route_.to, route_.stable)
            }.swap(amount_0_out, amount_1_out, to, empty_span);

            Swap(get_caller_address(), *amounts[i], route_.from, to_, route_.stable);

            i = i + 1;
        }
    }

    fn ensure(deadline: u64) {
        assert(deadline >= get_block_timestamp(), 'Router: EXPIRED');
    }

    fn pair_factory() -> IPairFactoryDispatcher {
        IPairFactoryDispatcher { contract_address: _factory::read() }
    }
}
