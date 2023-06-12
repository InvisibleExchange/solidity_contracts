from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.dict import dict_new, dict_write, dict_update, dict_squash, dict_read
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.ec_point import EcPoint
from starkware.cairo.common.math import unsigned_div_rem, assert_le
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.hash_state import (
    hash_init,
    hash_finalize,
    hash_update,
    hash_update_single,
)

from helpers.utils import Note, construct_new_note, sum_notes, hash_note, take_fee
from helpers.signatures.signatures import verify_spot_signature
from helpers.spot_helpers.dict_updates import update_note_dict

from helpers.spot_helpers.checks import range_checks_
from helpers.spot_helpers.partial_fill_helpers import refund_partial_fill

from rollup.output_structs import ZeroOutput
from rollup.global_config import get_dust_amount, GlobalConfig

from invisible_swaps.order.invisible_order import hash_transaction, Invisibl3Order

func execute_invisibl3_transaction{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    note_dict: DictAccess*,
    fee_tracker_dict: DictAccess*,
    zero_note_output_ptr: ZeroOutput*,
    global_config: GlobalConfig*,
}(
    order_hash: felt,
    notes_in_len: felt,
    notes_in: Note*,
    refund_note: Note,
    invisibl3_order: Invisibl3Order,
    spend_amount: felt,
    receive_amount: felt,
    fee_taken: felt,
) {
    alloc_locals;

    // * ORDER ============================================================
    // If this is not the first fill return the last partial fill note hash else return 0

    %{ is_first_fill = not prev_pfr_note %}

    if (nondet %{ is_first_fill %} != 0) {
        // ! if this is the first fill
        first_fill(
            notes_in_len,
            notes_in,
            refund_note,
            invisibl3_order,
            spend_amount,
            receive_amount,
            order_hash,
            fee_taken,
        );
    } else {
        // ! if the order was filled partially before this
        later_fills(
            notes_in_len,
            notes_in,
            order_hash,
            invisibl3_order,
            receive_amount,
            spend_amount,
            fee_taken,
        );
    }

    return ();
}

// ==================================================================================

func first_fill{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    note_dict: DictAccess*,
    fee_tracker_dict: DictAccess*,
    zero_note_output_ptr: ZeroOutput*,
    global_config: GlobalConfig*,
}(
    notes_in_len: felt,
    notes_in: Note*,
    refund_note: Note,
    invisibl3_order: Invisibl3Order,
    spend_amount: felt,
    receive_amount: felt,
    order_hash: felt,
    fee_taken: felt,
) {
    alloc_locals;

    // ? verify the sums match the refund and spend amounts
    let (sum_inputs: felt) = sum_notes(notes_in_len, notes_in, invisibl3_order.token_spent, 0);
    assert_le(invisibl3_order.amount_spent + refund_note.amount, sum_inputs);

    // ? Verify all values are in a certain range
    range_checks_(invisibl3_order, refund_note, spend_amount);

    // ? take a fee
    take_fee(invisibl3_order.token_received, fee_taken);

    // ? verify the signatures for the notes spent
    let (pub_key_sum: EcPoint) = verify_spot_signature(order_hash, notes_in_len, notes_in);

    local swap_note_idx: felt;
    %{
        ids.swap_note_idx = int(order_indexes["swap_note_idx"])
        if ids.notes_in_len > 1:
            note_in2_idx = memory[ids.notes_in.address_ + NOTE_SIZE + INDEX_OFFSET]
            assert ids.swap_note_idx == note_in2_idx, "something funky happening with the swap note index"
    %}

    // let swap_received_amount = amount - fee
    // ? This is the note receiveing the funds of this swap
    let (swap_note: Note) = construct_new_note(
        invisibl3_order.dest_received_address,
        invisibl3_order.token_received,
        receive_amount - fee_taken,
        invisibl3_order.dest_received_blinding,
        swap_note_idx,
    );

    // ? update the note dict with the new notes
    update_note_dict{note_dict=note_dict}(notes_in_len, notes_in, refund_note, swap_note);

    // ! Only executed  if the order was filled partialy not completely ------------------
    let (dust_amount) = get_dust_amount(invisibl3_order.token_spent);
    let is_partialy_filled: felt = is_le(dust_amount, invisibl3_order.amount_spent - spend_amount);
    if (is_partialy_filled == 0) {
        return ();
    }

    let notes_in_0 = notes_in[0];
    let unspent_amount = invisibl3_order.amount_spent - spend_amount;
    refund_partial_fill(
        invisibl3_order, notes_in_0.address.x, notes_in_0.blinding_factor, unspent_amount, 0
    );

    return ();
}

func later_fills{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    note_dict: DictAccess*,
    fee_tracker_dict: DictAccess*,
    zero_note_output_ptr: ZeroOutput*,
    global_config: GlobalConfig*,
}(
    notes_in_len: felt,
    notes_in: Note*,
    order_hash: felt,
    invisibl3_order: Invisibl3Order,
    receive_amount: felt,
    spend_amount: felt,
    fee_taken: felt,
) {
    alloc_locals;

    // ? This is the note that was refunded (leftover) from the previous fill
    local prev_fill_refund_note: Note;
    %{
        note_data = prev_pfr_note
        address_x = note_data["address"]["x"]
        address_y = note_data["address"]["y"]
        token = note_data["token"]
        amount = note_data["amount"]
        blinding_factor = note_data["blinding"]
        index = note_data["index"]
        note_hash = note_data["hash"]

        addr_ = ids.prev_fill_refund_note.address_
        memory[addr_ + ADDRESS_OFFSET + 0] = int(address_x)
        memory[addr_ + ADDRESS_OFFSET + 1] = int(address_y)
        memory[addr_ + TOKEN_OFFSET] = int(token)
        memory[addr_ + AMOUNT_OFFSET] = int(amount)
        memory[addr_ + BLINDING_FACTOR_OFFSET] = int(blinding_factor)
        memory[addr_ + INDEX_OFFSET] = int(index)
        memory[addr_ + HASH_OFFSET] = int(note_hash)
    %}

    // ? Check for valid token
    assert prev_fill_refund_note.token = invisibl3_order.token_spent;

    // ? Check for valid address
    assert prev_fill_refund_note.address.x = notes_in[0].address.x;

    // ? Verify the signature for the refund note
    verify_spot_signature(order_hash, notes_in_len, notes_in);

    // ? take a fee
    take_fee(invisibl3_order.token_received, fee_taken);

    // ? prevent spending more than the previous refund note
    assert_le(spend_amount, prev_fill_refund_note.amount);

    local swap_note_idx: felt;
    %{ ids.swap_note_idx = int(order_indexes["swap_note_idx"]) %}

    // ? This is the note receiveing the funds of this swap
    let (swap_note: Note) = construct_new_note(
        invisibl3_order.dest_received_address,
        invisibl3_order.token_received,
        receive_amount - fee_taken,
        invisibl3_order.dest_received_blinding,
        swap_note_idx,
    );

    // * Update the note dict with the new notes

    let note_dict_ptr = note_dict;
    assert note_dict_ptr.key = prev_fill_refund_note.index;
    assert note_dict_ptr.prev_value = prev_fill_refund_note.hash;
    assert note_dict_ptr.new_value = swap_note.hash;

    let note_dict = note_dict + DictAccess.SIZE;

    %{
        output_notes[ids.swap_note.index] = {
               "address": {"x": ids.swap_note.address.x, "y": ids.swap_note.address.y},
               "hash": ids.swap_note.hash,
               "index": ids.swap_note.index,
               "blinding": ids.swap_note.blinding_factor,
               "token": ids.swap_note.token,
               "amount": ids.swap_note.amount,
           }
    %}

    // ! if the order was filled partialy not completely ---------------------------
    let spend_amount_left = prev_fill_refund_note.amount - spend_amount;

    let (dust_amount) = get_dust_amount(invisibl3_order.token_spent);
    let is_partialy_filled: felt = is_le(dust_amount, spend_amount_left - spend_amount);
    if (is_partialy_filled == 0) {
        return ();
    }

    let unspent_amount = prev_fill_refund_note.amount - spend_amount;
    refund_partial_fill(
        invisibl3_order,
        prev_fill_refund_note.address.x,
        prev_fill_refund_note.blinding_factor,
        unspent_amount,
        prev_fill_refund_note.hash,
    );

    // order: Invisibl3Order, address: felt, blinding: felt, unspent_amount: felt, prev_hash: felt

    return ();
}
