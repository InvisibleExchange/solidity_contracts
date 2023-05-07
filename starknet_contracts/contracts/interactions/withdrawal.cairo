%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.starknet.common.syscalls import get_block_number, get_block_timestamp
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import assert_not_zero, assert_le, assert_lt, unsigned_div_rem
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.pow import pow
from starkware.starknet.common.syscalls import get_tx_info

from contracts.structs.output_structs import WithdrawalTransactionOutput
from contracts.helpers.parse_program_output import uncompress_withdrawal_output
from contracts.helpers.token_info import (
    scale_up,
    scale_down,
    get_token_id,
    register_token,
    get_token_address,
    get_token_scale_factor,
)

from openzeppelin.account.IAccount import IAccount
from openzeppelin.token.erc20.IERC20 import IERC20

@event
func withdrawal_event(
    withdrawer_address: felt, token_address: felt, withdrawal_amount: felt, timestamp: felt
) {
}

@storage_var
func s_pending_withdrawals(address: felt, token_id: felt) -> (amount: felt) {
}

func store_new_batch_withdrawal_outputs{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}(withdrawal_outputs_len: felt, withdrawal_outputs: WithdrawalTransactionOutput*) {
    if (withdrawal_outputs_len == 0) {
        return ();
    }

    // ? Uncompress withdrawal outputs
    let (token, amount, withdrawal_address) = uncompress_withdrawal_output(withdrawal_outputs[0]);

    // ? Get the current pending withdrawal for this address
    let (withdrawal_amount: felt) = s_pending_withdrawals.read(withdrawal_address, token);

    // ? Add the new withdrawal amount to the current pending withdrawal
    s_pending_withdrawals.write(
        address=withdrawal_address, token_id=token, value=withdrawal_amount + amount
    );

    return store_new_batch_withdrawal_outputs(withdrawal_outputs_len - 1, &withdrawal_outputs[1]);
}

@external
func make_withdrawal{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_address: felt
) {
    alloc_locals;

    // ? Get the caller and his pending deposit amount
    let (msg_sender: felt) = get_caller_address();
    let (withdrawable_amount: felt) = get_withdrawable_amount(msg_sender, token_address);

    // ? Update his pending withdrawal amount to zero
    let token_id: felt = get_token_id(token_address);
    s_pending_withdrawals.write(msg_sender, token_id, value=0);

    // ? Transfer the funds to the user (if withdrawable_amount > 0)
    let cond: felt = is_le(1, withdrawable_amount);
    if (cond == 1) {
        // ? Convert deposit amount to uint256
        let (high, low) = split_felt(withdrawable_amount);
        let uint256_amount: Uint256 = Uint256(low=low, high=high);

        // ? Refund the deposit back to the user
        let (success: felt) = IERC20.transfer(
            contract_address=token_address, recipient=msg_sender, amount=uint256_amount
        );

        with_attr error_message("Transfering funds to withdrawr failed") {
            assert success = 1;
        }
    }

    let (timestamp: felt) = get_block_timestamp();
    withdrawal_event.emit(msg_sender, token_address, withdrawable_amount, timestamp);

    return ();
}

// & ================= GETTERS =======================
@view
func get_withdrawable_amount{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    user_address: felt, token_address: felt
) -> (withdraw_amount_scaled: felt) {
    alloc_locals;

    let token_id: felt = get_token_id(token_address);

    let (withdrawable_amount: felt) = s_pending_withdrawals.read(user_address, token_id);

    let withdraw_amount_scaled = scale_up(withdrawable_amount, token_id);

    return (withdraw_amount_scaled,);
}

// TOKEN INFO

@external
func register_token_proxy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_address: felt, scale_factor: felt
) {
    register_token(token_address, scale_factor);

    return ();
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
    x: felt
) -> (res: felt) {
    let res = get_token_address(x);

    return (res,);
}

@view
func get_token_scale_factor_proxy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    x: felt
) -> (res: felt) {
    let res = get_token_scale_factor(x);

    return (res,);
}
