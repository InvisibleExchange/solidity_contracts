struct DepositInfoNote {
    deposit_id: felt,
    token_id: felt,
    deposit_amount: felt,
    stark_key: felt,
    deposit_timestamp: felt,
}

struct WithdrawalNote {
    withdrawal_id: felt,
    token_id: felt,
    withdrawal_amount: felt,
    withdrawal_address: felt,
}
