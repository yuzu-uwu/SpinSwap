#[contract]
mod Checkpoints {
    use starknet::ContractAddress;
    use array::ArrayTrait;
    // mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;
    /// @notice A checkpoint for marking delegated tokenIds from a given timestamp
    // struct Checkpoint {
    //     uint timestamp;
    //     uint[] tokenIds;
    // }

    #[storage]
    struct Storage {
        timestamp: LegacyMap::<(ContractAddress, u32), u128>,
        // (owner address, checkpoint number, index) => token id
        token_ids: LegacyMap::<(ContractAddress, u32, u256), u256>,
        token_count: LegacyMap::<(ContractAddress, u32), u256>
    }

    fn append(owner: ContractAddress, num_checkpoint: u32, token_id: u256) {
        let count = token_count::read((owner, num_checkpoint));

        token_ids::write((owner, num_checkpoint, count), token_id);
        token_count::write((owner, num_checkpoint), count + 1)
    }

    fn at(owner: ContractAddress, num_checkpoint: u32, index: u256) -> u256 {
        token_ids::read((owner, num_checkpoint, index))
    }

    fn len(owner: ContractAddress, num_checkpoint: u32) -> u256 {
        token_count::read((owner, num_checkpoint))
    }

    fn all_token_ids(owner: ContractAddress, num_checkpoint: u32) -> Array<u256> {
        let count = token_count::read((owner, num_checkpoint));
        let mut index = 0_u256;

        let mut ids = ArrayTrait::<u256>::new();
        loop {
            if index >= count {
                break ();
            }

            let token_id = token_ids::read((owner, num_checkpoint, index));
            ids.append(token_id);
            index += 1;
        };

        ids
    }
}
