%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero, unsigned_div_rem, split_felt
from starkware.cairo.common.pow import pow
from starkware.cairo.common.alloc import alloc

from contracts.structs.output_structs import (
    GlobalDexState,
    NoteDiffOutput,
    ZeroOutput,
    DepositTransactionOutput,
    WithdrawalTransactionOutput,
    PerpPositionOutput,
)

const TREE_DEPTH = 5;
const PERP_TREE_DEPTH = 3;

@storage_var
func s_config_code() -> (res: felt) {
}
@storage_var
func s_state_root() -> (res: felt) {
}
@storage_var
func s_perp_state_root() -> (res: felt) {
}

// TODO: EDIT BECASUE OF THE ARCHITECTURE UPDATE
@view
func parse_program_output{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    program_output_len: felt, program_output: felt*
) -> (
    dex_state: GlobalDexState,
    withdrawals_len: felt,
    withdrawals: WithdrawalTransactionOutput*,
    deposits_len: felt,
    deposits: DepositTransactionOutput*,
) {
    alloc_locals;

    let dex_state: GlobalDexState = parse_dex_state(program_output);

    let program_output_len = program_output_len - 14;
    let program_output = &program_output[14];

    // ? Parse Deposits
    let (deposits_len, deposits) = parse_deposits_array(program_output, dex_state.n_deposits);

    let program_output_len = program_output_len - dex_state.n_deposits * DepositTransactionOutput.SIZE;
    let program_output = &program_output[dex_state.n_deposits * DepositTransactionOutput.SIZE];

    // ? Parse Withdrawals
    let (withdrawals_len, withdrawals) = parse_withdrawals_array(
        program_output, dex_state.n_withdrawals
    );

    // TODO: Optional returns: position and note outputs

    return (dex_state, withdrawals_len, withdrawals, deposits_len, deposits,);
}

// ------------------------------------------------------------------------------

func parse_deposits_array(program_output: felt*, n_deposits: felt) -> (
    deposits_len: felt, deposits: DepositTransactionOutput*
) {
    alloc_locals;

    let (local empty_arr: DepositTransactionOutput*) = alloc();

    let (deposits_len: felt, deposits: DepositTransactionOutput*) = _build_deposits_array(
        program_output, n_deposits, 0, empty_arr
    );

    return (deposits_len, deposits);
}

func _build_deposits_array(
    program_output: felt*, n_deposits: felt, deposits_len: felt, deposits: DepositTransactionOutput*
) -> (deposits_len: felt, deposits: DepositTransactionOutput*) {
    if (n_deposits == deposits_len) {
        return (deposits_len, deposits);
    }

    let deposit_tx_info = DepositTransactionOutput(
        batched_deposit_info=program_output[0], stark_key=program_output[1]
    );

    assert deposits[deposits_len] = deposit_tx_info;

    return _build_deposits_array(&program_output[2], n_deposits, deposits_len + 1, deposits);
}

@view
func uncompress_deposit_output{range_check_ptr}(deposit: DepositTransactionOutput) -> (
    deposit_id: felt, token: felt, amount: felt, deposit_address: felt
) {
    let (deposit_id: felt, remainder: felt) = split_felt(deposit.batched_deposit_info);
    let (token: felt, amount: felt) = unsigned_div_rem(remainder, 2 ** 64);

    let deposit_address = deposit.stark_key;

    return (deposit_id, token, amount, deposit_address);
}

// ------------------------------------------------------------------------------

func parse_withdrawals_array(program_output: felt*, n_withdrawals: felt) -> (
    withdrawals_len: felt, withdrawals: WithdrawalTransactionOutput*
) {
    alloc_locals;

    let (local empty_arr: WithdrawalTransactionOutput*) = alloc();

    let (
        withdrawals_len: felt, withdrawals: WithdrawalTransactionOutput*
    ) = _build_withdrawals_array(program_output, n_withdrawals, 0, empty_arr);

    return (withdrawals_len, withdrawals);
}

func _build_withdrawals_array(
    program_output: felt*,
    n_withdrawals: felt,
    withdrawals_len: felt,
    withdrawals: WithdrawalTransactionOutput*,
) -> (withdrawals_len: felt, withdrawals: WithdrawalTransactionOutput*) {
    if (n_withdrawals == withdrawals_len) {
        return (withdrawals_len, withdrawals);
    }

    let withdrawal_tx_info = WithdrawalTransactionOutput(
        batched_withdraw_info=program_output[0], withdraw_address=program_output[1]
    );

    assert withdrawals[withdrawals_len] = withdrawal_tx_info;

    return _build_withdrawals_array(
        &program_output[2], n_withdrawals, withdrawals_len + 1, withdrawals
    );
}

@view
func uncompress_withdrawal_output{range_check_ptr}(withdrawal: WithdrawalTransactionOutput) -> (
    token: felt, amount: felt, withdrawal_address: felt
) {
    let (token: felt, amount: felt) = unsigned_div_rem(withdrawal.batched_withdraw_info, 2 ** 64);

    let withdrawal_address = withdrawal.withdraw_address;

    return (token, amount, withdrawal_address);
}

// ------------------------------------------------------------------------------

func parse_dex_state{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    dex_state_arr: felt*
) -> GlobalDexState {
    let config_code = dex_state_arr[0];
    let init_state_root = dex_state_arr[1];
    let final_state_root = dex_state_arr[2];
    let init_perp_state_root = dex_state_arr[3];
    let final_perp_state_root = dex_state_arr[4];
    let state_tree_depth = dex_state_arr[5];
    let perp_tree_depth = dex_state_arr[6];
    let global_expiration_timestamp = dex_state_arr[7];
    let n_deposits = dex_state_arr[8];
    let n_withdrawals = dex_state_arr[9];
    let n_output_positions = dex_state_arr[10];
    let n_empty_positions = dex_state_arr[11];
    let n_output_notes = dex_state_arr[12];
    let n_zero_notes = dex_state_arr[13];

    let (config_code_: felt) = s_config_code.read();
    let (state_root_: felt) = s_state_root.read();
    let (perp_state_root_: felt) = s_perp_state_root.read();
    with_attr error_message(
            "!======================= GLOBAL DEX STATE CONFIG MISSMATCH =========================!") {
        // TODO:  !!!
        // assert config_code_ = config_code;
        // assert state_root_ = init_state_root;
        // assert perp_state_root_ = init_perp_state_root;
        // assert state_tree_depth = TREE_DEPTH;
        // assert perp_tree_depth = PERP_TREE_DEPTH;
    }

    // Todo: verify that the global expiration timestamp

    let dex_state = GlobalDexState(
        config_code,
        init_state_root,
        final_state_root,
        init_perp_state_root,
        final_perp_state_root,
        state_tree_depth,
        perp_tree_depth,
        global_expiration_timestamp,
        n_deposits,
        n_withdrawals,
        n_output_positions,
        n_empty_positions,
        n_output_notes,
        n_zero_notes,
    );

    return (dex_state);
}
