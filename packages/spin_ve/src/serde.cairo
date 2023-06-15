use array::ArrayTrait;
use array::SpanTrait;
use option::OptionTrait;
use serde::Serde;
use traits::TryInto;
use alexandria_math::signed_integers::{i129};

impl I129Serde of Serde<i129> {
    fn serialize(self: @i129, ref output: Array<felt252>) {
        self.inner.serialize(ref output);
        if *self.sign {
            1
        } else {
            0
        }.serialize(ref output)
    }
    fn deserialize(ref serialized: Span<felt252>) -> Option<i129> {
        let inner: u128 = ((*serialized.pop_front()?).try_into())?;
        let sign: bool = *serialized.pop_front()? != 0;

        Option::Some(i129 { inner, sign })
    }
}
