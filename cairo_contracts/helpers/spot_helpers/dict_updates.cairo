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
from helpers.utils import (
    Note,
    construct_new_note,
    sum_notes,
    hash_note,
    validate_fee_taken,
    get_zero_note,
)

// ! NOTE DICT UPDATES FOR SWAPS =====================================================

func update_note_dict{pedersen_ptr: HashBuiltin*, note_dict: DictAccess*}(
    notes_in_len: felt, notes_in: Note*, refund_note: Note, swap_note: Note
) {
    alloc_locals;

    if (notes_in_len == 1) {
        let note_in = notes_in[0];
        return update_one(note_in, refund_note, swap_note);
    }
    if (notes_in_len == 2) {
        let note_in1 = notes_in[0];
        let note_in2 = notes_in[1];
        return update_two(note_in1, note_in2, refund_note, swap_note);
    }

    return update_multi(notes_in_len, notes_in, refund_note, swap_note);
}

func update_one{pedersen_ptr: HashBuiltin*, note_dict: DictAccess*, note_updates: Note*}(
    note_in: Note, refund_note: Note, swap_note: Note
) {
    // * Update the note dict
    let note_dict_ptr = note_dict;
    assert note_dict_ptr.key = note_in.index;
    assert note_dict_ptr.prev_value = note_in.hash;
    assert note_dict_ptr.new_value = refund_note.hash;

    let note_dict = note_dict + DictAccess.SIZE;

    // ? store to an array used for program outputs
    if (refund_note.hash != 0) {
        assert note_updates[0] = refund_note;
        note_updates = &note_updates[1];
    }

    // %{
    //     if ids.refund_note.hash != 0:
    //         output_notes[ids.refund_note.index] = {
    //             "address": {"x": ids.refund_note.address.x, "y": ids.refund_note.address.y},
    //             "hash": ids.refund_note.hash,
    //             "index": ids.refund_note.index,
    //             "blinding": ids.refund_note.blinding_factor,
    //             "token": ids.refund_note.token,
    //             "amount": ids.refund_note.amount,
    //         }
    // %}

    // * Write the note dict
    let note_dict_ptr = note_dict;
    assert note_dict_ptr.key = swap_note.index;
    assert note_dict_ptr.prev_value = 0;
    assert note_dict_ptr.new_value = swap_note.hash;

    let note_dict = note_dict + DictAccess.SIZE;

    // ? store to an array used for program outputs
    assert note_updates[0] = swap_note;
    note_updates = &note_updates[1];

    // %{
    //     output_notes[ids.swap_note.index] = {
    //            "address": {"x": ids.swap_note.address.x, "y": ids.swap_note.address.y},
    //            "hash": ids.swap_note.hash,
    //            "index": ids.swap_note.index,
    //            "blinding": ids.swap_note.blinding_factor,
    //            "token": ids.swap_note.token,
    //            "amount": ids.swap_note.amount,
    //        }
    // %}

    return ();
}

func update_two{pedersen_ptr: HashBuiltin*, note_dict: DictAccess*, note_updates: Note*}(
    note_in1: Note, note_in2: Note, refund_note: Note, swap_note: Note
) {
    // * Update the note dict
    let note_dict_ptr = note_dict;
    note_dict_ptr.key = note_in1.index;
    note_dict_ptr.prev_value = note_in1.hash;
    note_dict_ptr.new_value = refund_note.hash;

    let note_dict = note_dict + DictAccess.SIZE;

    // ? store to an array used for program outputs
    if (refund_note.hash != 0) {
        assert note_updates[0] = refund_note;
        note_updates = &note_updates[1];
    }

    // %{
    //     if ids.refund_note.hash != 0:
    //         output_notes[ids.refund_note.index] = {
    //             "address": {"x": ids.refund_note.address.x, "y": ids.refund_note.address.y},
    //             "hash": ids.refund_note.hash,
    //             "index": ids.refund_note.index,
    //             "blinding": ids.refund_note.blinding_factor,
    //             "token": ids.refund_note.token,
    //             "amount": ids.refund_note.amount,
    //         }
    // %}

    // * Update the note dict
    let note_dict_ptr = note_dict;
    note_dict_ptr.key = swap_note.index;
    note_dict_ptr.prev_value = note_in2.hash;
    note_dict_ptr.new_value = swap_note.hash;

    let note_dict = note_dict + DictAccess.SIZE;

    // ? store to an array used for program outputs
    assert note_updates[0] = swap_note;
    note_updates = &note_updates[1];

    // %{
    //     output_notes[ids.swap_note.index] = {
    //            "address": {"x": ids.swap_note.address.x, "y": ids.swap_note.address.y},
    //            "hash": ids.swap_note.hash,
    //            "index": ids.swap_note.index,
    //            "blinding": ids.swap_note.blinding_factor,
    //            "token": ids.swap_note.token,
    //            "amount": ids.swap_note.amount,
    //        }
    // %}

    return ();
}

func update_multi{pedersen_ptr: HashBuiltin*, note_dict: DictAccess*, note_updates: Note*}(
    notes_in_len: felt, notes_in: Note*, refund_note: Note, swap_note: Note
) {
    let note_in1: Note = notes_in[0];
    let note_in2: Note = notes_in[1];

    update_two(note_in1, note_in2, refund_note, swap_note);

    return _update_multi_inner(notes_in_len - 2, &notes_in[2]);
}

func _update_multi_inner{pedersen_ptr: HashBuiltin*, note_dict: DictAccess*, note_updates: Note*}(
    notes_in_len: felt, notes_in: Note*
) {
    if (notes_in_len == 0) {
        return ();
    }

    // * Update the note dict
    let note_in: Note = notes_in[0];

    let note_dict_ptr = note_dict;
    assert note_dict_ptr.key = note_in.index;
    assert note_dict_ptr.prev_value = note_in.hash;
    assert note_dict_ptr.new_value = 0;

    let note_dict = note_dict + DictAccess.SIZE;

    // ? store to an array used for program outputs
    let (zero_note) = get_zero_note(note_in.index);
    assert note_updates[0] = zero_note;
    note_updates = &note_updates[1];

    return _update_multi_inner(notes_in_len - 1, &notes_in[1]);
}

// ! NOTE DICT UPDATES FOR DEPOSITS AND WITHDRAWALS =====================================================

func deposit_note_dict_updates{
    pedersen_ptr: HashBuiltin*, note_dict: DictAccess*, note_updates: Note*
}(deposit_notes_len: felt, deposit_notes: Note*) {
    if (deposit_notes_len == 0) {
        return ();
    }

    // * Update the note dict
    let deposit_note: Note = deposit_notes[0];

    let note_dict_ptr = note_dict;
    assert note_dict_ptr.key = deposit_note.index;
    assert note_dict_ptr.prev_value = 0;
    assert note_dict_ptr.new_value = deposit_note.hash;

    let note_dict = note_dict + DictAccess.SIZE;

    // ? store to an array used for program outputs
    assert note_updates[0] = deposit_note;
    note_updates = &note_updates[1];

    // %{
    //     output_notes[ids.deposit_note.index] = {
    //            "address": {"x": ids.deposit_note.address.x, "y": ids.deposit_note.address.y},
    //            "hash": ids.deposit_note.hash,
    //            "index": ids.deposit_note.index,
    //            "blinding": ids.deposit_note.blinding_factor,
    //            "token": ids.deposit_note.token,
    //            "amount": ids.deposit_note.amount,
    //        }
    // %}

    return deposit_note_dict_updates(deposit_notes_len - 1, &deposit_notes[1]);
}

func withdraw_note_dict_updates{
    pedersen_ptr: HashBuiltin*, note_dict: DictAccess*, note_updates: Note*
}(withdraw_notes_len: felt, withdraw_notes: Note*, refund_note: Note) {
    if (withdraw_notes_len == 0) {
        return ();
    }

    _update_one_withdraw(withdraw_notes[0], refund_note);
    return _update_multi_inner_withdraw(withdraw_notes_len - 1, &withdraw_notes[1]);
}

func _update_one_withdraw{pedersen_ptr: HashBuiltin*, note_dict: DictAccess*, note_updates: Note*}(
    note_in: Note, refund_note: Note
) {
    // * Update the note dict
    let note_dict_ptr = note_dict;
    assert note_dict_ptr.key = note_in.index;
    assert note_dict_ptr.prev_value = note_in.hash;
    assert note_dict_ptr.new_value = refund_note.hash;

    let note_dict = note_dict + DictAccess.SIZE;

    // %{
    //     output_notes[ids.refund_note.index] = {
    //            "address": {"x": ids.refund_note.address.x, "y": ids.refund_note.address.y},
    //            "hash": ids.refund_note.hash,
    //            "index": ids.refund_note.index,
    //            "blinding": ids.refund_note.blinding_factor,
    //            "token": ids.refund_note.token,
    //            "amount": ids.refund_note.amount,
    //        }
    // %}

    if (refund_note.hash != 0) {
        // ? store to an array used for program outputs
        assert note_updates[0] = refund_note;
        note_updates = &note_updates[1];
    }

    return ();
}

func _update_multi_inner_withdraw{
    pedersen_ptr: HashBuiltin*, note_dict: DictAccess*, note_updates: Note*
}(notes_in_len: felt, notes_in: Note*) {
    if (notes_in_len == 0) {
        return ();
    }

    // * Update the note dict
    let note_in: Note = notes_in[0];

    let note_dict_ptr = note_dict;
    assert note_dict_ptr.key = note_in.index;
    assert note_dict_ptr.prev_value = note_in.hash;
    assert note_dict_ptr.new_value = 0;

    let note_dict = note_dict + DictAccess.SIZE;

    // ? store to an array used for program outputs
    let (zero_note) = get_zero_note(note_in.index);
    assert note_updates[0] = zero_note;
    note_updates = &note_updates[1];

    return _update_multi_inner(notes_in_len - 1, &notes_in[1]);
}
