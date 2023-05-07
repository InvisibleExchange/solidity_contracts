// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

struct GlobalDexState {
    uint64 txBatchId; // why do we need this? (cahnge to txBatchId)
    uint256 initStateRoot;
    uint256 finalStateRoot;
    uint256 initPerpStateRoot;
    uint256 finalPerpStateRoot;
    uint32 stateTreeDepth;
    uint32 perpTreeDepth;
    uint32 globalExpirationTimestamp;
    uint32 nDeposits;
    uint32 nWithdrawals;
    uint32 nOutputPositions;
    uint32 nEmptyPositions;
    uint32 nOutputNotes;
    uint32 nZeroNotes;
}

// Represents the struct of data written to the program output for each Deposit.
struct DepositTransactionOutput {
    // & batched_note_info format: | deposit_id (64 bits) | token (64 bits) | amount (64 bits) |
    uint256 batchedDepositInfo;
    uint256 pubKey;
}

// Represents the struct of data written to the program output for each Withdrawal.
struct WithdrawalTransactionOutput {
    // & batched_note_info format: | token (64 bits) | amount (64 bits) |
    uint256 batchedWithdrawalInfo;
    address recipient; // This should be the eth address to withdraw from
}

// Represents the struct of data written to the program output for each Note Modifictaion.
struct NoteDiffOutput {
    // & batched_note_info format: | token (64 bits) | hidden amount (64 bits) | idx (64 bits) |
    uint256 batched_note_info;
    uint256 noteAddress;
    uint256 commitment;
}

// Represents the struct of data written to the program output for each perpetual position Modifictaion.
struct PerpPositionOutput {
    // & format: | position_id (64 bits) | synthetic_token (64 bits) | position_size (64 bits) | order_side (8 bit) |
    // & format: | entry_price (64 bits) | liquidation_price (64 bits) | last_funding_idx (32 bits) | index (64 bits) |
    // & format: | public key <-> position_address (251 bits) |
    uint256 batched_position_info_slot1;
    uint256 batched_position_info_slot2;
    uint256 public_key;
}

// This is used to output the index of the note/position that has been spent/closed
struct ZeroOutput {
    // & format: | index (64 bits) |
    uint64 index;
}
