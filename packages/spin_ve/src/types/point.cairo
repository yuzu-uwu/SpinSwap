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
use spin_ve::types::i129::I129StorageAccess;

// with the help of https://cairopractice.com/posts/storing-user-defined-types-pt-2/
// can use custom structure in storage

impl PointStorageAccess of StorageAccess<Point> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult::<Point> {
        let bias = StorageAccess::read(address_domain, base)?;

        let slope_base = storage_base_address_from_felt252(
            storage_address_from_base_and_offset(base, 2_u8).into()
        );
        let slope = StorageAccess::read(address_domain, slope_base)?;

        let ts_base = storage_base_address_from_felt252(
            storage_address_from_base_and_offset(base, 4_u8).into()
        );
        let ts = StorageAccess::read(address_domain, ts_base)?;

        // works both

        // let blk_base = storage_base_address_from_felt252(
        //     storage_address_from_base_and_offset(base, 5_u8).into()
        // );
        // let blk = StorageAccess::read(address_domain, blk_base)?;

        let blk = storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(base, 5_u8)
        )?
            .try_into()
            .unwrap();

        Result::Ok(Point { bias, slope, ts, blk })
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: Point) -> SyscallResult::<()> {
        StorageAccess::write(address_domain, base, value.bias)?;

        let slope_base = storage_base_address_from_felt252(
            storage_address_from_base_and_offset(base, 2_u8).into()
        );
        StorageAccess::write(address_domain, slope_base, value.slope)?;

        // works both, just try different way
        // let ts_base = storage_base_address_from_felt252(
        //     storage_address_from_base_and_offset(base, 4_u8).into()
        // );
        // StorageAccess::write(address_domain, ts_base, value.ts)?;

        // let blk_base = storage_base_address_from_felt252(
        //     storage_address_from_base_and_offset(base, 6_u8).into()
        // );
        // StorageAccess::write(address_domain, ts_base, value.blk)

        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 4_u8), value.ts.into()
        )?;
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 5_u8), value.blk.into()
        )
    }
}