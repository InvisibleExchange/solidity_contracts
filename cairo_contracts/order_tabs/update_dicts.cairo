from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.dict import dict_new, dict_write, dict_update, dict_squash, dict_read
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.merkle_multi_update import merkle_multi_update
from starkware.cairo.common.math import unsigned_div_rem, assert_le
from starkware.cairo.common.math_cmp import is_le

from invisible_swaps.order.invisible_order import Invisibl3Order
from rollup.output_structs import write_zero_note_to_output, ZeroOutput
from helpers.utils import Note, construct_new_note, sum_notes, hash_note, validate_fee_taken

func open_tab_state_note_updates{
    pedersen_ptr: HashBuiltin*, note_dict: DictAccess*, zero_tab_output_ptr: ZeroOutput*
}(
    base_notes_in_len: felt,
    base_notes_in: Note*,
    quote_notes_in_len: felt,
    quote_notes_in: Note*,
    base_refund_note: Note*,
    quote_refund_note: Note*,
) {
    // ? Remove the notes from the state
    _update_multi_inner(base_notes_in_len, base_notes_in);
    _update_multi_inner(quote_notes_in_len, quote_notes_in);

    // ? add the refund notes
    if (base_refund_note.hash != 0) {
        // * Update the note dict
        let note_dict_ptr = note_dict;
        note_dict_ptr.key = base_notes_in[0].index;
        note_dict_ptr.prev_value = 0;
        note_dict_ptr.new_value = base_refund_note.hash;

        let note_dict = note_dict + DictAccess.SIZE;

        %{
            if ids.base_refund_note.hash != 0:
                output_notes[ids.base_refund_note.index] = {
                    "address": {"x": ids.base_refund_note.address.x, "y": ids.base_refund_note.address.y},
                    "hash": ids.base_refund_note.hash,
                    "index": ids.base_refund_note.index,
                    "blinding": ids.base_refund_note.blinding_factor,
                    "token": ids.base_refund_note.token,
                    "amount": ids.base_refund_note.amount,
                }
        %}
    }
    if (quote_refund_note.hash != 0) {
        // * Update the note dict
        let note_dict_ptr = note_dict;
        note_dict_ptr.key = quote_notes_in[0].index;
        note_dict_ptr.prev_value = 0;
        note_dict_ptr.new_value = quote_refund_note.hash;

        let note_dict = note_dict + DictAccess.SIZE;

        %{
            if ids.quote_refund_note.hash != 0:
                output_notes[ids.quote_refund_note.index] = {
                    "address": {"x": ids.quote_refund_note.address.x, "y": ids.quote_refund_note.address.y},
                    "hash": ids.quote_refund_note.hash,
                    "index": ids.quote_refund_note.index,
                    "blinding": ids.quote_refund_note.blinding_factor,
                    "token": ids.quote_refund_note.token,
                    "amount": ids.quote_refund_note.amount,
                }
        %}
    }

    return ();
}

func close_tab_note_state_updates{pedersen_ptr: HashBuiltin*, note_dict: DictAccess*}(
    order_tab: OrderTab*, base_return_note: Note*, quote_return_note: Note*
) {
    // * Update the note dict
    let note_dict_ptr = note_dict;
    note_dict_ptr.key = base_return_note.index;
    note_dict_ptr.prev_value = 0;
    note_dict_ptr.new_value = base_return_note.hash;

    let note_dict = note_dict + DictAccess.SIZE;

    %{
        if ids.base_return_note.hash != 0:
            output_notes[ids.base_return_note.index] = {
                "address": {"x": ids.base_return_note.address.x, "y": ids.base_return_note.address.y},
                "hash": ids.base_return_note.hash,
                "index": ids.base_return_note.index,
                "blinding": ids.base_return_note.blinding_factor,
                "token": ids.base_return_note.token,
                "amount": ids.base_return_note.amount,
            }
    %}

    let note_dict_ptr = note_dict;
    note_dict_ptr.key = quote_return_note.index;
    note_dict_ptr.prev_value = 0;
    note_dict_ptr.new_value = quote_return_note.hash;

    let note_dict = note_dict + DictAccess.SIZE;

    %{
        if ids.quote_return_note.hash != 0:
            output_notes[ids.quote_return_note.index] = {
                "address": {"x": ids.quote_return_note.address.x, "y": ids.quote_return_note.address.y},
                "hash": ids.quote_return_note.hash,
                "index": ids.quote_return_note.index,
                "blinding": ids.quote_return_note.blinding_factor,
                "token": ids.quote_return_note.token,
                "amount": ids.quote_return_note.amount,
            }
    %}

    return ();
}

// ? ORDER TAB UPDATES ===================================================
func add_new_tab_to_state{pedersen_ptr: HashBuiltin*, tab_dict: DictAccess*}(order_tab: OrderTab*) {
    let tab_dict_ptr = tab_dict;
    tab_dict_ptr.key = order_tab.index;
    tab_dict_ptr.prev_value = 0;
    tab_dict_ptr.new_value = order_tab.hash;

    let tab_dict = tab_dict + DictAccess.SIZE;

    // TODO: %{
    //     if ids.order_tab.hash != 0:
    //         output_notes[ids.quote_refund_note.index] = {
    //             "address": {"x": ids.quote_refund_note.address.x, "y": ids.quote_refund_note.address.y},
    //             "hash": ids.quote_refund_note.hash,
    //             "index": ids.quote_refund_note.index,
    //             "blinding": ids.quote_refund_note.blinding_factor,
    //             "token": ids.quote_refund_note.token,
    //             "amount": ids.quote_refund_note.amount,
    //         }
    // %}

    return ();
}

func remove_tab_from_state{pedersen_ptr: HashBuiltin*, tab_dict: DictAccess*}(
    order_tab: OrderTab*
) {
    let tab_dict_ptr = tab_dict;
    tab_dict_ptr.key = order_tab.index;
    tab_dict_ptr.prev_value = order_tab.hash;
    tab_dict_ptr.new_value = 0;

    let tab_dict = tab_dict + DictAccess.SIZE;

    return ();
}

func update_tab_from_state{pedersen_ptr: HashBuiltin*, tab_dict: DictAccess*}(
    prev_order_tab: OrderTab*, updated_tab_hash: felt
) {
    let tab_dict_ptr = tab_dict;
    tab_dict_ptr.key = prev_order_tab.index;
    tab_dict_ptr.prev_value = prev_order_tab.hash;
    tab_dict_ptr.new_value = updated_tab_hash;

    let tab_dict = tab_dict + DictAccess.SIZE;

    // TODO: %{
    //     if ids.order_tab.hash != 0:
    //         output_notes[ids.quote_refund_note.index] = {
    //             "address": {"x": ids.quote_refund_note.address.x, "y": ids.quote_refund_note.address.y},
    //             "hash": ids.quote_refund_note.hash,
    //             "index": ids.quote_refund_note.index,
    //             "blinding": ids.quote_refund_note.blinding_factor,
    //             "token": ids.quote_refund_note.token,
    //             "amount": ids.quote_refund_note.amount,
    //         }
    // %}

    return ();
}
