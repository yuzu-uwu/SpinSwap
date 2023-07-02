trait Math<T> {
    fn max(a: T, b: T) -> T;
    fn min(a: T, b: T) -> T;
}

impl MaxU256 of Math<u256> {
    fn max(a: u256, b: u256) -> u256 {
        if a >= b {
            return a;
        }
        b
    }

    fn min(a: u256, b: u256) -> u256 {
        if a <= b {
            return a;
        }
        b
    }
}


// from Dustin.Ray
fn exp_by_squares(base: u256, exponent: u256) -> u256 {
    if exponent == 0 {
        return 1;
    } else if exponent == 1 {
        return base;
    } else if exponent % 2 == 0 {
        let result = exp_by_squares(base, exponent / 2);
        return result * result;
    } else {
        let result = exp_by_squares(base, (exponent - 1) / 2);
        return result * result * base;
    }
}
