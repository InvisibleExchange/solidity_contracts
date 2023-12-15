// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct GlobalDexState {
    uint64 txBatchId;
    uint256 initStateRoot;
    uint256 finalStateRoot;
    uint32 stateTreeDepth;
    uint32 globalExpirationTimestamp;
    uint16 nDeposits;
    uint16 nWithdrawals;
    uint16 nOnchainMMActions;
    uint16 nNoteEscapes;
    uint16 nPositionEscapes;
    uint16 nTabEscapes;
    // uint32 nOutputPositions;
    // uint32 nEmptyPositions;
    // uint32 nOutputNotes;
    // uint32 nZeroIndexes;
}

struct GlobalConfig {
    uint32 collateralToken;
    uint8 leverageDecimals;
    uint32 assetsLen;
    uint32 syntheticAssetsLen;
    uint32 observersLen;
    uint32 chainIdsLen;
}

// Represents the struct of data written to the program output for each Deposit.
struct DepositTransactionOutput {
    // & batched_note_info format: | deposit_id (64 bits) | token (32 bits) | amount (64 bits) |
    // & --------------------------  deposit_id => chain id (32 bits) | identifier (32 bits) |
    uint256 batchedDepositInfo;
    uint256 pubKey;
}

// Represents the struct of data written to the program output for each Withdrawal.
struct WithdrawalTransactionOutput {
    // & batched_note_info format: | withdrawal_chain_id (32 bits) | token (32 bits) | amount (64 bits) |
    uint256 batchedWithdrawalInfo;
    address recipient;
}

struct OnChainMMActionOutput {
    // & batched_registration_info format: | vlp_token (32 bits) | max_vlp_supply (64 bits) | vlp_amount (64 bits) | action_type (8 bits) |
    // & batched_add_liq_info format:  usdcAmount (64 bits) | vlp_amount (64 bits) | action_type (8 bits) |
    // & batched_remove_liq_info format:  | initialValue (64 bits) | vlpAmount (64 bits) | returnAmount (64 bits) | action_type (8 bits) |
    // & batched_close_mm_info format:  | initialValueSum (64 bits) | vlpAmountSum (64 bits) | returnAmount (64 bits) | action_type (8 bits) |
    uint256 mmPositionAddress;
    uint256 depositor;
    uint256 batchedActionInfo;
}

struct AccumulatedHashesOutput {
    uint32 chainId;
    uint256 depositHash;
    uint256 withdrawalHash;
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

struct EscapeOutput {
    // & | escape_id (32 bits) | is_valid (8 bits) | escape_type (8 bits) |
    uint256 batched_escape_info;
    uint256 escape_message_hash;
    uint256 signature_r;
    uint256 signature_s;
}

struct PositionEscapeOutput {
    // & escape_value (64 bits) | escape_id (32 bits) | is_valid (8 bits) |
    uint256 batched_escape_info;
    address recipient;
    uint256 escape_message_hash;
    uint256 signature_a_r;
    uint256 signature_a_s;
    uint256 signature_b_r;
    uint256 signature_b_s;
}

enum EscapeType {
    Note,
    OrderTab
}
