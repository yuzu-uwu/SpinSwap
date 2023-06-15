use array::ArrayTrait;
use array::SpanTrait;

fn concat_array<T, impl Drop: Drop<T>, impl Copy: Copy<T>>(ref a: Array<T>, mut b: Span<T>) {
    loop {
        match b.pop_front() {
            Option::Some(item) => {
                a.append(*item)
            },
            Option::None(()) => {
                break ();
            }
        };
    };
}

fn reverse_array<T, impl Drop: Drop<T>, impl Copy: Copy<T>>(source: Array<T>) -> Array<T> {
    let mut result = ArrayTrait::<T>::new();
    let mut _source = source.span();
    let mut index = _source.len();

    loop {
        if (index <= 0) {
            break ();
        }
        index -= 1;

        result.append(*_source.at(index));
    };

    result
}
