use starknet::StorageAccess;
use starknet::StorageBaseAddress;
use starknet::SyscallResult;
use starknet::storage_base_address_from_felt252;
use starknet::storage_address_from_base_and_offset;

use traits::Into;
use traits::TryInto;
use option::OptionTrait;

use alexandria_math::signed_integers::{i129};


// with the help of https://cairopractice.com/posts/storing-user-defined-types-pt-2/
// can use custom structure in storage
impl I129StorageAccess of StorageAccess<i129> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult::<i129> {
        let inner = StorageAccess::read(address_domain, base)?;
        let sign_base = storage_base_address_from_felt252(
            storage_address_from_base_and_offset(base, 1_u8).into()
        );
        let sign = StorageAccess::read(address_domain, sign_base)?;
        Result::Ok(i129 { inner, sign })
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: i129) -> SyscallResult::<()> {
        StorageAccess::write(address_domain, base, value.inner)?;

        let sign_base = storage_base_address_from_felt252(
            storage_address_from_base_and_offset(base, 1_u8).into()
        );
        StorageAccess::write(address_domain, sign_base, value.sign)
    }
}