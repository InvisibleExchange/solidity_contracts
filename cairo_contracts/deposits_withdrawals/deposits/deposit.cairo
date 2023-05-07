// %builtins output pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.dict import dict_new, dict_write, dict_update, dict_squash, dict_read
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.cairo_secp.bigint import BigInt3, bigint_to_uint256, uint256_to_bigint
from starkware.cairo.common.cairo_secp.ec import EcPoint
from starkware.cairo.common.merkle_multi_update import merkle_multi_update
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.math import unsigned_div_rem, assert_le
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.squash_dict import squash_dict
from starkware.cairo.common.hash_state import (
    hash_init,
    hash_finalize,
    hash_update,
    hash_update_single,
)

from helpers.utils import Note
from deposits_withdrawals.deposits.deposit_utils import (
    Deposit,
    get_deposit_notes,
    verify_deposit_notes,
)
from helpers.spot_helpers.dict_updates import deposit_note_dict_updates

from rollup.output_structs import (
    NoteDiffOutput,
    DepositTransactionOutput,
    write_deposit_info_to_output,
)

func verify_deposit{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    deposit_output_ptr: DepositTransactionOutput*,
    note_dict: DictAccess*,
}() {
    alloc_locals;

    // & This is the public on_chain deposit information
    local deposit: Deposit;
    %{
        # current_deposit = deposits.pop(0)

        memory[ids.deposit.address_ + DEPOSIT_ID_OFFSET] = int(current_deposit["deposit_id"])
        memory[ids.deposit.address_ + DEPOSIT_TOKEN_OFFSET] = int(current_deposit["deposit_token"])
        memory[ids.deposit.address_ + DEPOSIT_AMOUNT_OFFSET] = int(current_deposit["deposit_amount"])
        memory[ids.deposit.address_ + DEPOSIT_ADDRESS_OFFSET] = int(current_deposit["stark_key"])
    %}

    let (deposit_notes_len: felt, deposit_notes: Note*) = get_deposit_notes();

    // & Verify the newly minted deposit notes have the same amount and token as the on-chain deposit
    // & Also verify that the deposit was signed by the owner of the deposit address
    verify_deposit_notes(deposit_notes_len, deposit_notes, deposit);

    // Update the note dict
    deposit_note_dict_updates(deposit_notes_len, deposit_notes);

    // Write the deposit info to the output
    write_deposit_info_to_output(deposit);

    return ();
}
