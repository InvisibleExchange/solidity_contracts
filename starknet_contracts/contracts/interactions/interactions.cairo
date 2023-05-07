%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.starknet.common.syscalls import get_block_number, get_block_timestamp
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import assert_not_zero, assert_le, assert_lt, unsigned_div_rem
from starkware.cairo.common.pow import pow
from starkware.starknet.common.syscalls import get_tx_info

from contracts.structs.output_structs import (
    DepositTransactionOutput,
    WithdrawalTransactionOutput,
    GlobalDexState,
)
from contracts.helpers.parse_program_output import parse_program_output
from contracts.helpers.token_info import (
    scale_up,
    scale_down,
    get_token_id,
    register_token,
    get_token_address,
    get_token_scale_factor,
)
from contracts.interactions.deposits import (
    make_deposit,
    get_pending_deposit_amount,
    update_pending_deposits,
)
from contracts.interactions.withdrawal import (
    make_withdrawal,
    store_new_batch_withdrawal_outputs,
    get_withdrawable_amount,
)

// * PARSE PROGRAM OUTPUT * //

@view
func parse_program_output_proxy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    program_output_len: felt, program_output: felt*
) -> (
    dex_state: GlobalDexState,
    withdrawals_len: felt,
    withdrawals: WithdrawalTransactionOutput*,
    deposits_len: felt,
    deposits: DepositTransactionOutput*,
) {
    return parse_program_output(program_output_len, program_output);
}

// * DEPOSITS * //

@external
func make_deposit_proxy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_address: felt, amount: felt
) -> (deposit_amount: felt) {
    return make_deposit(token_address, amount);
}

@external
func update_pending_deposits_proxy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    deposit_outputs_len: felt, deposit_outputs: DepositTransactionOutput*
) {
    return update_pending_deposits(deposit_outputs_len, deposit_outputs);
}

@view
func get_pending_deposit_amount_proxy{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}(user_address: felt, token_address: felt) -> (deposit_amount: felt) {
    return get_pending_deposit_amount(user_address, token_address);
}

// * WITHDRAWAL * //

@external
func make_withdrawal_proxy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_address: felt
) {
    return make_withdrawal(token_address);
}

@external
func store_new_batch_withdrawal_outputs_proxy{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}(withdrawal_outputs_len: felt, withdrawal_outputs: WithdrawalTransactionOutput*) {
    return store_new_batch_withdrawal_outputs(withdrawal_outputs_len, withdrawal_outputs);
}

@view
func get_withdrawable_amount_proxy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    user_address: felt, token_address: felt
) -> (withdraw_amount_scaled: felt) {
    return get_withdrawable_amount(user_address, token_address);
}

// TOKEN INFO ------------------------------------------------------

@external
func register_token_proxy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_address: felt, scale_factor: felt
) -> (token_id: felt) {
    let (token_id: felt) = register_token(token_address, scale_factor);

    return (token_id,);
}

@view
func get_token_id_proxy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_address: felt
) -> (res: felt) {
    let res = get_token_id(token_address);

    return (res,);
}

@view
func get_token_address_proxy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_id: felt
) -> (res: felt) {
    let res = get_token_address(token_id);

    return (res,);
}

@view
func get_token_scale_factor_proxy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_id: felt
) -> (res: felt) {
    let res = get_token_scale_factor(token_id);

    return (res,);
}
