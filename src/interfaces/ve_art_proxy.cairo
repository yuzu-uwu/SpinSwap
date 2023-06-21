#[abi]
trait IVeArtProxy {
    #[view]
    fn base_uri(
        _tokenId: u256, _balance_of: u256, _locked_end: u128, _value: u256
    ) -> Array<felt252>;
}
