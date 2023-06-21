#[contract]
mod VeArtProxy {
    use starknet::ContractAddress;
    use array::ArrayTrait;
    use array::SpanTrait;
    use spin_lib::string::{u128_to_ascii, utoa};
    use spin_lib::array::concat_array;

    #[view]
    fn base_uri(
        _tokenId: u256, _balance_of: u256, _locked_end: u128, _value: u256
    ) -> Array<felt252> {
        let tokenId_ascii: Array<felt252> = utoa(_tokenId);
        let balance_of_ascii: Array<felt252> = utoa(_balance_of);
        let locked_end_ascii: Array<felt252> = u128_to_ascii(_locked_end);
        let value_ascii: Array<felt252> = utoa(_value);

        let mut string_array = ArrayTrait::new();

        string_array.append('{"name": "lock #');

        concat_array(ref string_array, tokenId_ascii.span());

        string_array.append('",  "description":');
        string_array.append('"Spin locks, can be used ');
        string_array.append('to boost gauge yields,');
        string_array.append(' can be used to boost ');
        string_array.append('gauge yields,');
        string_array.append(' vote on token emission');
        string_array.append(', and receive bribes",');
        string_array.append(' "image": "');
        string_array.append('<svg xmlns="http://www.');
        string_array.append('w3.org/2000/svg" ');
        string_array.append('preserveAspectRatio=');
        string_array.append('"xMinYMin meet" ');
        string_array.append('viewBox="0 0 350 350">');
        string_array.append('<style>.base { fill: white; ');
        string_array.append('font-family: serif; ');
        string_array.append('font-size: 14px; }</style>');
        string_array.append('<rect width="100%" ');
        string_array.append('height="100%" fill="black" />');
        string_array.append('<text x="10" y="20" ');
        string_array.append('class="base">token ');

        concat_array(ref string_array, tokenId_ascii.span());

        string_array.append('</text><text x="10" ');
        string_array.append('y="40" class="base">balanceOf ');

        concat_array(ref string_array, balance_of_ascii.span());

        string_array.append('</text><text x="10" ');
        string_array.append('y="60" class="base">locked_end ');

        concat_array(ref string_array, locked_end_ascii.span());

        string_array.append('</text><text x="10" ');
        string_array.append('y="80" class="base">value ');

        concat_array(ref string_array, value_ascii.span());

        string_array.append('</text></svg>"}');

        string_array
    }
}
