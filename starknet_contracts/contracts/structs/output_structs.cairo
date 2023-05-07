struct GlobalDexState {
    config_code: felt,  // why do we need this? (rename)
    init_state_root: felt,
    final_state_root: felt,
    init_perp_state_root: felt,
    final_perp_state_root: felt,
    state_tree_depth: felt,
    perp_tree_depth: felt,
    global_expiration_timestamp: felt,
    n_deposits: felt,
    n_withdrawals: felt,
    n_output_positions: felt,
    n_empty_positions: felt,
    n_output_notes: felt,
    n_zero_notes: felt,
}

// Represents the struct of data written to the program output for each Deposit.
struct DepositTransactionOutput {
    // & batched_note_info format: | deposit_id (64 bits) | token (64 bits) | amount (64 bits) |
    batched_deposit_info: felt,
    stark_key: felt,
}

// Represents the struct of data written to the program output for each Withdrawal.
struct WithdrawalTransactionOutput {
    // & batched_note_info format: | token (64 bits) | amount (64 bits) |
    batched_withdraw_info: felt,
    withdraw_address: felt,  // This should be the eth address to withdraw from
}

// Represents the struct of data written to the program output for each Note Modifictaion.
struct NoteDiffOutput {
    // & batched_note_info format: | token (64 bits) | hidden amount (64 bits) | idx (64 bits) |
    batched_note_info: felt,
    address: felt,
    commitment: felt,
}

// Represents the struct of data written to the program output for each perpetual position Modifictaion.
struct PerpPositionOutput {
    // & format: | position_id (64 bits) | synthetic_token (64 bits) | position_size (64 bits) | order_side (8 bit) |
    // & format: | entry_price (64 bits) | liquidation_price (64 bits) | last_funding_idx (32 bits) | index (64 bits) |
    // & format: | public key <-> position_address (251 bits) |
    batched_position_info_slot1: felt,
    batched_position_info_slot2: felt,
    public_key: felt,
}

// This is used to output the index of the note/position that has been spent/closed
// The class is only defined for clarity we could just use a felt instead
struct ZeroOutput {
    // & format: | index (64 bits) |
    index: felt,
}
