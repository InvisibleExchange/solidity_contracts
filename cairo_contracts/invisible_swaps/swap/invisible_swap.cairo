// %builtins output pedersen range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin, BitwiseBuiltin
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

from invisible_swaps.order.invisible_order import hash_transaction, Invisibl3Order
from invisible_swaps.transaction.invisible_tx import execute_invisibl3_transaction
from helpers.utils import Note
from helpers.spot_helpers.checks import consistency_checks

from rollup.output_structs import ZeroOutput, NoteDiffOutput
from rollup.global_config import GlobalConfig

func execute_swap{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    note_dict: DictAccess*,
    fee_tracker_dict: DictAccess*,
    zero_note_output_ptr: ZeroOutput*,
    global_config: GlobalConfig*,
}() {
    alloc_locals;

    local invisibl3_order_A: Invisibl3Order;
    local invisibl3_order_B: Invisibl3Order;

    local notes_in_A_len: felt;
    local notes_in_A: Note*;
    local refund_note_A: Note;

    local notes_in_B_len: felt;
    local notes_in_B: Note*;
    local refund_note_B: Note;

    let (__fp__, _) = get_fp_and_pc();
    handle_inputs(
        &invisibl3_order_A,
        &invisibl3_order_B,
        &notes_in_A_len,
        &notes_in_A,
        &refund_note_A,
        &notes_in_B_len,
        &notes_in_B,
        &refund_note_B,
    );

    local spend_amountA: felt;
    local spend_amountB: felt;
    local fee_takenA: felt;
    local fee_takenB: felt;

    %{
        swap_data = current_swap["swap_data"]

        spend_amountA = int(swap_data["spent_amount_a"]) 
        spend_amountB = int(swap_data["spent_amount_b"])

        ids.spend_amountA = spend_amountA
        ids.spend_amountB = spend_amountB

        ids.fee_takenA = int(swap_data["fee_taken_a"])
        ids.fee_takenB = int(swap_data["fee_taken_b"])
    %}

    consistency_checks(
        invisibl3_order_A,
        invisibl3_order_B,
        spend_amountA,
        spend_amountB,
        fee_takenA,
        fee_takenB,
        notes_in_A_len,
        notes_in_A,
        notes_in_B_len,
        notes_in_B,
    );

    let (order_hash_A: felt) = hash_transaction(
        invisibl3_order_A, notes_in_A_len, notes_in_A, refund_note_A
    );

    let (order_hash_B: felt) = hash_transaction(
        invisibl3_order_B, notes_in_B_len, notes_in_B, refund_note_B
    );

    %{
        order_indexes = index_data["order_a"]
        current_order = swap_data["order_a"]
        signature = swap_data["signature_a"]
        prev_pfr_note = current_swap["prev_pfr_note_a"]
    %}
    execute_invisibl3_transaction(
        order_hash_A,
        notes_in_A_len,
        notes_in_A,
        refund_note_A,
        invisibl3_order_A,
        spend_amountA,
        spend_amountB,
        fee_takenA,
    );
    %{
        order_indexes = index_data["order_b"] 
        current_order = swap_data["order_b"]
        signature = swap_data["signature_b"]
        prev_pfr_note = current_swap["prev_pfr_note_b"]
    %}
    execute_invisibl3_transaction(
        order_hash_B,
        notes_in_B_len,
        notes_in_B,
        refund_note_B,
        invisibl3_order_B,
        spend_amountB,
        spend_amountA,
        fee_takenB,
    );

    return ();
}

func handle_inputs{pedersen_ptr: HashBuiltin*}(
    invisibl3_order_A: Invisibl3Order*,
    invisibl3_order_B: Invisibl3Order*,
    notes_in_A_len: felt*,
    notes_in_A: Note**,
    refund_note_A: Note*,
    notes_in_B_len: felt*,
    notes_in_B: Note**,
    refund_note_B: Note*,
) {
    %{
        ##* ORDER A =============================================================

        order_A_input = current_swap["swap_data"]["order_a"]

        order_A_addr = ids.invisibl3_order_A.address_

        memory[order_A_addr + ORDER_ID_OFFSET] = int(order_A_input["order_id"])
        memory[order_A_addr + EXPIRATION_TIMESTAMP_OFFSET] = int(order_A_input["expiration_timestamp"])
        memory[order_A_addr + TOKEN_SPENT_OFFSET] = int(order_A_input["token_spent"])
        memory[order_A_addr + TOKEN_RECEIVED_OFFSET] = int(order_A_input["token_received"])
        memory[order_A_addr + AMOUNT_SPENT_OFFSET] = int(order_A_input["amount_spent"])
        memory[order_A_addr + AMOUNT_RECEIVED_OFFSET] = int(order_A_input["amount_received"]) 
        memory[order_A_addr + DEST_RECEIVED_ADDR_OFFSET] = int(order_A_input["dest_received_address"]["x"])# Need just the x coordinate
        memory[order_A_addr + DEST_SPENT_BLINDING_OFFSET] = int(order_A_input["dest_spent_blinding"])
        memory[order_A_addr + DEST_RECEIVED_BLINDING_OFFSET] = int(order_A_input["dest_received_blinding"])
        memory[order_A_addr + FEE_LIMIT_OFFSET] = int(order_A_input["fee_limit"])

        input_notes = order_A_input["notes_in"]

        memory[ids.notes_in_A_len] = len(input_notes)
        memory[ids.notes_in_A] = notes_ = segments.add()
        for i in range(len(input_notes)):
            memory[notes_ + i* NOTE_SIZE + ADDRESS_OFFSET+0] = int(input_notes[i]["address"]["x"])
            memory[notes_ + i* NOTE_SIZE + ADDRESS_OFFSET+1] = int(input_notes[i]["address"]["y"])
            memory[notes_ + i* NOTE_SIZE + TOKEN_OFFSET] = int(input_notes[i]["token"])
            memory[notes_ + i* NOTE_SIZE + AMOUNT_OFFSET] = int(input_notes[i]["amount"])
            memory[notes_ + i* NOTE_SIZE + BLINDING_FACTOR_OFFSET] = int(input_notes[i]["blinding"])
            memory[notes_ + i* NOTE_SIZE + INDEX_OFFSET] = int(input_notes[i]["index"])
            memory[notes_ + i* NOTE_SIZE + HASH_OFFSET] = int(input_notes[i]["hash"])

        refund_note__  = order_A_input["refund_note"]
        if refund_note__ is not None:
            memory[ids.refund_note_A.address_ + ADDRESS_OFFSET+0] = int(refund_note__["address"]["x"])
            memory[ids.refund_note_A.address_ + ADDRESS_OFFSET+1] = int(refund_note__["address"]["y"])
            memory[ids.refund_note_A.address_ + TOKEN_OFFSET] = int(refund_note__["token"])
            memory[ids.refund_note_A.address_ + AMOUNT_OFFSET] = int(refund_note__["amount"])
            memory[ids.refund_note_A.address_ + BLINDING_FACTOR_OFFSET] = int(refund_note__["blinding"])
            memory[ids.refund_note_A.address_ + INDEX_OFFSET] = int(refund_note__["index"])
            memory[ids.refund_note_A.address_ + HASH_OFFSET] = int(refund_note__["hash"])
        else:
            memory[ids.refund_note_A.address_ + ADDRESS_OFFSET+0] = 0
            memory[ids.refund_note_A.address_ + ADDRESS_OFFSET+1] = 0
            memory[ids.refund_note_A.address_ + TOKEN_OFFSET] = 0
            memory[ids.refund_note_A.address_ + AMOUNT_OFFSET] = 0
            memory[ids.refund_note_A.address_ + BLINDING_FACTOR_OFFSET] = 0
            memory[ids.refund_note_A.address_ + INDEX_OFFSET] = 0
            memory[ids.refund_note_A.address_ + HASH_OFFSET] = 0




        ##* ORDER B =============================================================

        order_B_input = current_swap["swap_data"]["order_b"]

        order_B_addr = ids.invisibl3_order_B.address_

        memory[order_B_addr + ORDER_ID_OFFSET] = int(order_B_input["order_id"])
        memory[order_B_addr + EXPIRATION_TIMESTAMP_OFFSET] = int(order_B_input["expiration_timestamp"])
        memory[order_B_addr + TOKEN_SPENT_OFFSET] = int(order_B_input["token_spent"])
        memory[order_B_addr + TOKEN_RECEIVED_OFFSET] = int(order_B_input["token_received"])
        memory[order_B_addr + AMOUNT_SPENT_OFFSET] = int(order_B_input["amount_spent"])
        memory[order_B_addr + AMOUNT_RECEIVED_OFFSET] = int(order_B_input["amount_received"])
        memory[order_B_addr + DEST_RECEIVED_ADDR_OFFSET] = int(order_B_input["dest_received_address"]["x"]) # Need just the x coordinate
        memory[order_B_addr + DEST_SPENT_BLINDING_OFFSET] = int(order_B_input["dest_spent_blinding"])
        memory[order_B_addr + DEST_RECEIVED_BLINDING_OFFSET] = int(order_B_input["dest_received_blinding"])
        memory[order_B_addr + FEE_LIMIT_OFFSET] = int(order_B_input["fee_limit"])

        input_notes = order_B_input["notes_in"]

        memory[ids.notes_in_B_len] = len(input_notes)
        memory[ids.notes_in_B] = notes_ = segments.add()
        for i in range(len(input_notes)):
            memory[notes_ + i* NOTE_SIZE + ADDRESS_OFFSET+0] = int(input_notes[i]["address"]["x"])
            memory[notes_ + i* NOTE_SIZE + ADDRESS_OFFSET+1] = int(input_notes[i]["address"]["y"])
            memory[notes_ + i* NOTE_SIZE + TOKEN_OFFSET] = int(input_notes[i]["token"])
            memory[notes_ + i* NOTE_SIZE + AMOUNT_OFFSET] = int(input_notes[i]["amount"])
            memory[notes_ + i* NOTE_SIZE + BLINDING_FACTOR_OFFSET] = int(input_notes[i]["blinding"])
            memory[notes_ + i* NOTE_SIZE + INDEX_OFFSET] = int(input_notes[i]["index"])
            memory[notes_ + i* NOTE_SIZE + HASH_OFFSET] = int(input_notes[i]["hash"])

        refund_note__  = order_B_input["refund_note"]
        if  refund_note__ is not None:
            memory[ids.refund_note_B.address_ + ADDRESS_OFFSET+0] = int(refund_note__["address"]["x"]) 
            memory[ids.refund_note_B.address_ + ADDRESS_OFFSET+1] = int(refund_note__["address"]["y"])
            memory[ids.refund_note_B.address_ + TOKEN_OFFSET] = int(refund_note__["token"])
            memory[ids.refund_note_B.address_ + AMOUNT_OFFSET] = int(refund_note__["amount"])
            memory[ids.refund_note_B.address_ + BLINDING_FACTOR_OFFSET] = int(refund_note__["blinding"])
            memory[ids.refund_note_B.address_ + INDEX_OFFSET] = int(refund_note__["index"])
            memory[ids.refund_note_B.address_ + HASH_OFFSET] = int(refund_note__["hash"])
        else:
            memory[ids.refund_note_B.address_ + ADDRESS_OFFSET+0] = 0
            memory[ids.refund_note_B.address_ + ADDRESS_OFFSET+1] = 0
            memory[ids.refund_note_B.address_ + TOKEN_OFFSET] = 0
            memory[ids.refund_note_B.address_ + AMOUNT_OFFSET] = 0
            memory[ids.refund_note_B.address_ + BLINDING_FACTOR_OFFSET] = 0
            memory[ids.refund_note_B.address_ + INDEX_OFFSET] = 0
            memory[ids.refund_note_B.address_ + HASH_OFFSET] = 0


        ##* OTHER =============================================================

        index_data = current_swap["indexes"]
    %}

    return ();
}
