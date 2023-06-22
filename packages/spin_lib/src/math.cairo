trait Math<T> {
    fn max(a: T, b: T) -> T;
    fn min(a:T, b: T) -> T;
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
