use starknet::StorageAccess;
use starknet::StorageBaseAddress;
use starknet::SyscallResult;
use starknet::storage_read_syscall;
use starknet::storage_write_syscall;
use starknet::storage_base_address_from_felt252;
use starknet::storage_address_from_base_and_offset;

use traits::Into;
use traits::TryInto;
use option::OptionTrait;

use alexandria_math::signed_integers::{i129};

use spin_ve::types::LockedBalance;
use spin_ve::storage_access::i129::I129StorageAccess;

impl LockedBalanceStorageAccess of StorageAccess<LockedBalance> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult::<LockedBalance> {
        let amount = StorageAccess::read(address_domain, base)?;

        let end_base = storage_base_address_from_felt252(
            storage_address_from_base_and_offset(base, 2_u8).into()
        );
        let end = StorageAccess::read(address_domain, end_base)?;

        Result::Ok(LockedBalance { amount, end })
    }

    fn write(
        address_domain: u32, base: StorageBaseAddress, value: LockedBalance
    ) -> SyscallResult::<()> {
        StorageAccess::write(address_domain, base, value.amount)?;

        let end_base = storage_base_address_from_felt252(
            storage_address_from_base_and_offset(base, 2_u8).into()
        );
        StorageAccess::write(address_domain, end_base, value.end)
    }
}
