// %builtins output pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.dict import dict_new, dict_write, dict_update, dict_squash, dict_read
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.merkle_multi_update import merkle_multi_update
from starkware.cairo.common.math import unsigned_div_rem, assert_le
from starkware.cairo.common.squash_dict import squash_dict
from starkware.cairo.common.hash_state import (
    hash_init,
    hash_finalize,
    hash_update,
    hash_update_single,
)

from helpers.utils import Note
from deposits_withdrawals.withdrawals.withdraw_utils import (
    Withdrawal,
    get_withdraw_and_refund_notes,
    verify_withdraw_notes,
)
from helpers.spot_helpers.dict_updates import withdraw_note_dict_updates

from rollup.output_structs import (
    NoteDiffOutput,
    ZeroOutput,
    WithdrawalTransactionOutput,
    write_withdrawal_info_to_output,
)

func verify_withdrawal{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    withdraw_output_ptr: WithdrawalTransactionOutput*,
    note_dict: DictAccess*,
    zero_note_output_ptr: ZeroOutput*,
}() {
    alloc_locals;

    // & This is the public on_chain withdraw information
    local withdrawal: Withdrawal;
    %{
        memory[ids.withdrawal.address_ + WITHDRAWAL_TOKEN_OFFSET] = int(current_withdrawal["withdrawal_token"])
        memory[ids.withdrawal.address_ + WITHDRAWAL_AMOUNT_OFFSET] = int(current_withdrawal["withdrawal_amount"])
        memory[ids.withdrawal.address_ + WITHDRAWAL_ADDRESS_OFFSET] = int(current_withdrawal["stark_key"])
    %}

    let (
        withdraw_notes_len: felt, withdraw_notes: Note*, refund_note: Note
    ) = get_withdraw_and_refund_notes();

    // & Verify the amount to be withdrawn is less or equal the sum of notes spent
    // & also verify all the notes were signed correctly
    verify_withdraw_notes(withdraw_notes_len, withdraw_notes, refund_note, withdrawal);

    // Update the note dict
    withdraw_note_dict_updates(withdraw_notes_len, withdraw_notes, refund_note);

    // Todo Should write empty notes to output

    // write withdrawal info to the output
    write_withdrawal_info_to_output(withdrawal);

    return ();
}
