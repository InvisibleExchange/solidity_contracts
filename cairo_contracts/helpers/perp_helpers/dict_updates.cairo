from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.dict import dict_new, dict_write, dict_update, dict_squash, dict_read
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.merkle_multi_update import merkle_multi_update
from starkware.cairo.common.math import unsigned_div_rem, assert_le
from starkware.cairo.common.math_cmp import is_le

from rollup.output_structs import NoteDiffOutput, PerpPositionOutput, ZeroOutput
from perpetuals.order.order_structs import PerpOrder, PerpPosition
from helpers.utils import Note

func update_note_dict{pedersen_ptr: HashBuiltin*, note_dict: DictAccess*}(
    notes_in_len: felt, notes_in: Note*, refund_note: Note
) {
    alloc_locals;

    let note_in = notes_in[0];
    update_one(note_in, refund_note);

    if (notes_in_len == 1) {
        return ();
    }

    return _update_multi_inner(notes_in_len - 1, &notes_in[1]);
}

func update_one{pedersen_ptr: HashBuiltin*, note_dict: DictAccess*, note_updates: Note*}(
    note_in: Note, refund_note: Note
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

    return ();
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

    // ? store to an array used for program outputs
    let (zero_note) = get_zero_note(note_in.index);
    assert note_updates[0] = zero_note;
    note_updates = &note_updates[1];

    let note_dict = note_dict + DictAccess.SIZE;

    return _update_multi_inner(notes_in_len - 1, &notes_in[1]);
}

func update_rc_note_dict{pedersen_ptr: HashBuiltin*, note_dict: DictAccess*, note_updates: Note*}(
    rc_note: Note
) {
    // * Update the note dict
    let note_dict_ptr = note_dict;
    assert note_dict_ptr.key = rc_note.index;
    assert note_dict_ptr.prev_value = 0;
    assert note_dict_ptr.new_value = rc_note.hash;

    let note_dict = note_dict + DictAccess.SIZE;

    // ? store to an array used for program outputs
    assert note_updates[0] = rc_note;
    note_updates = &note_updates[1];

    // %{
    //     output_notes[ids.rc_note.index] = {
    //            "address": {"x": ids.rc_note.address.x, "y": ids.rc_note.address.y},
    //            "hash": ids.rc_note.hash,
    //            "index": ids.rc_note.index,
    //            "blinding": ids.rc_note.blinding_factor,
    //            "token": ids.rc_note.token,
    //            "amount": ids.rc_note.amount,
    //        }
    // %}

    return ();
}

// * UPDATE

func update_position_dict{pedersen_ptr: HashBuiltin*, position_dict: DictAccess*}(
    prev_position_hash: felt, position: PerpPosition
) {
    // * Update the position dict
    let position_dict_ptr = position_dict;
    assert position_dict_ptr.key = position.index;
    assert position_dict_ptr.prev_value = prev_position_hash;
    assert position_dict_ptr.new_value = position.hash;

    let position_dict = position_dict + DictAccess.SIZE;

    %{ store_output_position(ids.position.address_, ids.position.index) %}

    return ();
}

func update_position_dict_on_close{
    pedersen_ptr: HashBuiltin*, position_dict: DictAccess*, empty_position_output_ptr: ZeroOutput*
}(prev_position_hash: felt, idx: felt) {
    // * Update the note dict
    let position_dict_ptr = position_dict;
    assert position_dict_ptr.key = idx;
    assert position_dict_ptr.prev_value = prev_position_hash;
    assert position_dict_ptr.new_value = 0;

    let position_dict = position_dict + DictAccess.SIZE;

    return ();
}
