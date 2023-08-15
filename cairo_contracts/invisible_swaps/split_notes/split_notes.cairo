from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin, BitwiseBuiltin
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.math import assert_le
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.registers import get_fp_and_pc

from helpers.utils import Note, sum_notes

func execute_note_split{
    pedersen_ptr: HashBuiltin*, range_check_ptr, state_dict: DictAccess*, note_updates: Note*
}() {
    alloc_locals;

    local token: felt;
    local notes_in_len: felt;
    local notes_in: Note*;
    local notes_out_len: felt;
    local notes_out: Note*;

    let (__fp__, _) = get_fp_and_pc();
    handle_inputs(&token, &notes_in_len, &notes_in, &notes_out_len, &notes_out);

    let (notes_in_sum: felt) = sum_notes(notes_in_len, notes_in, token, 0);
    let (notes_out_sum: felt) = sum_notes(notes_out_len, notes_out, token, 0);

    let note_in1 = notes_in[0];
    let note_in2 = notes_in[notes_in_len - 1];

    assert note_in1.address.x = notes_out[0].address.x;
    assert note_in1.blinding_factor = notes_out[0].blinding_factor;
    assert note_in2.address.x = notes_out[notes_out_len - 1].address.x;
    assert note_in2.blinding_factor = notes_out[notes_out_len - 1].blinding_factor;

    assert notes_out_sum = notes_in_sum;

    let cond = is_le(notes_out_len, notes_in_len);

    if (cond == 1) {
        // ? There's more (or equal) notes_in than notes_out
        write_notes_out_over_notes_in(
            notes_in_len, notes_in, notes_out_len, notes_out, notes_out_len
        );
        remove_extra_notes_in(notes_in_len - notes_out_len, &notes_in[notes_out_len]);
    } else {
        // ? There's more (or equal) notes_out than notes_in
        write_notes_out_over_notes_in(
            notes_in_len, notes_in, notes_out_len, notes_out, notes_in_len
        );
        write_notes_out_over_empty(notes_out_len - notes_in_len, &notes_out[notes_in_len]);
    }

    return ();
}

func write_notes_out_over_notes_in{
    pedersen_ptr: HashBuiltin*, state_dict: DictAccess*, note_updates: Note*
}(notes_in_len: felt, notes_in: Note*, notes_out_len: felt, notes_out: Note*, len: felt) {
    if (len == 0) {
        return ();
    }

    %{ current_split_info["zero_idxs"].pop(0) %}

    // * Update the note dict
    let note_in: Note = notes_in[0];
    let note_out: Note = notes_out[0];

    let state_dict_ptr = state_dict;
    assert state_dict_ptr.key = note_in.index;
    assert state_dict_ptr.prev_value = note_in.hash;
    assert state_dict_ptr.new_value = note_out.hash;

    let state_dict = state_dict + DictAccess.SIZE;

    // ? store to an array used for program outputs
    assert note_updates[0] = note_out;
    let note_updates = &note_updates[1];

    %{ leaf_node_types[ids.note_in.index] = "note" %}
    %{
        note_output_idxs[ids.note_in.index] = note_outputs_len 
        note_outputs_len += 1
    %}

    return write_notes_out_over_notes_in(
        notes_in_len - 1, &notes_in[1], notes_out_len - 1, &notes_out[1], len - 1
    );
}

func write_notes_out_over_empty{
    pedersen_ptr: HashBuiltin*, state_dict: DictAccess*, note_updates: Note*
}(notes_out_len: felt, notes_out: Note*) {
    alloc_locals;

    if (notes_out_len == 0) {
        return ();
    }

    // * Update the note dict
    let note_out: Note = notes_out[0];

    local zero_idx: felt;
    %{ ids.zero_idx = int(current_split_info["zero_idxs"].pop(0)) %}

    let state_dict_ptr = state_dict;
    assert state_dict_ptr.key = zero_idx;
    assert state_dict_ptr.prev_value = 0;
    assert state_dict_ptr.new_value = note_out.hash;

    // ? store to an array used for program outputs
    assert note_updates[0] = note_out;
    let note_updates = &note_updates[1];

    %{ leaf_node_types[ids.zero_idx] = "note" %}
    %{
        note_output_idxs[ids.zero_idx] = note_outputs_len 
        note_outputs_len += 1
    %}

    let state_dict = state_dict + DictAccess.SIZE;

    return write_notes_out_over_empty(notes_out_len - 1, &notes_out[1]);
}

func remove_extra_notes_in{
    pedersen_ptr: HashBuiltin*, state_dict: DictAccess*, note_updates: Note*
}(notes_in_len: felt, notes_in: Note*) {
    if (notes_in_len == 0) {
        return ();
    }

    // * Update the note dict
    let note_in: Note = notes_in[0];

    let state_dict_ptr = state_dict;
    assert state_dict_ptr.key = note_in.index;
    assert state_dict_ptr.prev_value = note_in.hash;
    assert state_dict_ptr.new_value = 0;

    let state_dict = state_dict + DictAccess.SIZE;

    %{ leaf_node_types[ids.note_in.index] = "note" %}

    return remove_extra_notes_in(notes_in_len - 1, &notes_in[1]);
}

//

func handle_inputs{pedersen_ptr: HashBuiltin*}(
    token: felt*, notes_in_len: felt*, notes_in: Note**, notes_out_len: felt*, notes_out: Note**
) {
    %{
        memory[ids.token] = int(current_split_info["token"])

        input_notes = current_split_info["notes_in"]

        memory[ids.notes_in_len] = len(input_notes)
        memory[ids.notes_in] = notes_ = segments.add()
        for i in range(len(input_notes)):
            memory[notes_ + i* NOTE_SIZE + ADDRESS_OFFSET+0] = int(input_notes[i]["address"]["x"])
            memory[notes_ + i* NOTE_SIZE + ADDRESS_OFFSET+1] = int(input_notes[i]["address"]["y"])
            memory[notes_ + i* NOTE_SIZE + TOKEN_OFFSET] = int(input_notes[i]["token"])
            memory[notes_ + i* NOTE_SIZE + AMOUNT_OFFSET] = int(input_notes[i]["amount"])
            memory[notes_ + i* NOTE_SIZE + BLINDING_FACTOR_OFFSET] = int(input_notes[i]["blinding"])
            memory[notes_ + i* NOTE_SIZE + INDEX_OFFSET] = int(input_notes[i]["index"])
            memory[notes_ + i* NOTE_SIZE + HASH_OFFSET] = int(input_notes[i]["hash"])


        out_notes = current_split_info["notes_out"]

        memory[ids.notes_out_len] = len(out_notes)
        memory[ids.notes_out] = notes_ = segments.add()
        for i in range(len(out_notes)):
            memory[notes_ + i* NOTE_SIZE + ADDRESS_OFFSET+0] = int(out_notes[i]["address"]["x"])
            memory[notes_ + i* NOTE_SIZE + ADDRESS_OFFSET+1] = int(out_notes[i]["address"]["y"])
            memory[notes_ + i* NOTE_SIZE + TOKEN_OFFSET] = int(out_notes[i]["token"])
            memory[notes_ + i* NOTE_SIZE + AMOUNT_OFFSET] = int(out_notes[i]["amount"])
            memory[notes_ + i* NOTE_SIZE + BLINDING_FACTOR_OFFSET] = int(out_notes[i]["blinding"])
            memory[notes_ + i* NOTE_SIZE + INDEX_OFFSET] = int(out_notes[i]["index"])
            memory[notes_ + i* NOTE_SIZE + HASH_OFFSET] = int(out_notes[i]["hash"])
    %}

    return ();
}

//

//
