from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin, BitwiseBuiltin
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.math import assert_le, abs_value, unsigned_div_rem
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.hash_state import (
    hash_init,
    hash_finalize,
    hash_update,
    hash_update_single,
)

from helpers.utils import Note, sum_notes, construct_new_note, hash_notes_array
from perpetuals.order.order_structs import (
    CloseOrderFields,
    PerpPosition,
    PerpOrder,
    OpenOrderFields,
)
from perpetuals.order.order_hash import _hash_close_order_fields
from perpetuals.order.perp_position import modify_margin
from perpetuals.transaction.perp_transaction import get_perp_position, get_init_margin
from helpers.signatures.signatures import verify_margin_change_signature

from rollup.global_config import GlobalConfig

func execute_margin_change{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    state_dict: DictAccess*,
    ecdsa_ptr: SignatureBuiltin*,
    global_config: GlobalConfig*,
    note_updates: Note*,
}() {
    alloc_locals;

    local margin_change: felt;
    local notes_in_len: felt;
    local notes_in: Note*;
    local refund_note: Note;
    local close_order_fields: CloseOrderFields;

    let (__fp__, _) = get_fp_and_pc();
    handle_inputs(&margin_change, &notes_in_len, &notes_in, &refund_note, &close_order_fields);

    %{ prev_position = current_margin_change_info["position"] %}
    let position: PerpPosition = get_perp_position();

    let (msg_hash: felt) = hash_margin_change_message(
        margin_change, notes_in_len, notes_in, refund_note, close_order_fields, position
    );

    let is_increase: felt = is_le(0, margin_change);
    verify_margin_change_signature(
        msg_hash, notes_in_len, notes_in, position.position_header.position_address, is_increase
    );

    let (new_position: PerpPosition) = modify_margin(position, margin_change);

    if (is_increase == 1) {
        // ? Sum notes and verify amount being spent
        let (total_notes_in: felt) = sum_notes(
            notes_in_len, notes_in, global_config.collateral_token, 0
        );
        assert_le(margin_change + refund_note.amount, total_notes_in);

        // ? Update the state
        update_state_after_increase(
            notes_in_len, notes_in, refund_note, new_position, position.hash
        );
    } else {
        local index: felt;
        %{ ids.index = zero_index %}

        let return_value = abs_value(margin_change);

        let (return_collateral_note: Note) = construct_new_note(
            close_order_fields.dest_received_address,
            global_config.collateral_token,
            return_value,
            close_order_fields.dest_received_blinding,
            index,
        );

        // ? Update the state
        update_state_after_decrease(return_collateral_note, new_position, position.hash);
    }

    return ();
}

func update_state_after_increase{
    pedersen_ptr: HashBuiltin*, range_check_ptr, state_dict: DictAccess*, note_updates: Note*
}(
    notes_in_len: felt,
    notes_in: Note*,
    refund_note: Note,
    position: PerpPosition,
    prev_position_hash: felt,
) {
    // * Update the position dict
    let state_dict_ptr = state_dict;
    assert state_dict_ptr.key = position.index;
    assert state_dict_ptr.prev_value = prev_position_hash;
    assert state_dict_ptr.new_value = position.hash;

    let state_dict = state_dict + DictAccess.SIZE;

    %{ leaf_node_types[ids.position.index] = "position" %}
    %{ store_output_position(ids.position.address_, ids.position.index) %}

    let state_dict_ptr = state_dict;
    assert state_dict_ptr.key = notes_in[0].index;
    assert state_dict_ptr.prev_value = notes_in[0].hash;
    assert state_dict_ptr.new_value = refund_note.hash;

    let state_dict = state_dict + DictAccess.SIZE;

    // ? store to an array used for program outputs
    if (refund_note.hash != 0) {
        %{ leaf_node_types[ids.refund_note.index] = "note" %}
        %{
            note_output_idxs[ids.refund_note.index] = note_outputs_len 
            note_outputs_len += 1
        %}

        assert note_updates[0] = refund_note;
        let note_updates = &note_updates[1];

        return update_state_after_increase_inner(notes_in_len - 1, &notes_in[1]);
    }

    return update_state_after_increase_inner(notes_in_len - 1, &notes_in[1]);
}

func update_state_after_increase_inner{
    pedersen_ptr: HashBuiltin*, range_check_ptr, state_dict: DictAccess*, note_updates: Note*
}(notes_in_len: felt, notes_in: Note*) {
    if (notes_in_len == 0) {
        return ();
    }

    let note_in0 = notes_in[0];

    let state_dict_ptr = state_dict;
    assert state_dict_ptr.key = note_in0.index;
    assert state_dict_ptr.prev_value = note_in0.hash;
    assert state_dict_ptr.new_value = 0;

    let state_dict = state_dict + DictAccess.SIZE;

    %{ leaf_node_types[ids.note_in0.index] = "note" %}

    return update_state_after_increase_inner(notes_in_len - 1, &notes_in[1]);
}

func update_state_after_decrease{
    pedersen_ptr: HashBuiltin*, range_check_ptr, state_dict: DictAccess*, note_updates: Note*
}(return_collateral_note: Note, position: PerpPosition, prev_position_hash: felt) {
    let state_dict_ptr = state_dict;
    assert state_dict_ptr.key = return_collateral_note.index;
    assert state_dict_ptr.prev_value = 0;
    assert state_dict_ptr.new_value = return_collateral_note.hash;

    // ? store to an array used for program outputs
    assert note_updates[0] = return_collateral_note;
    let note_updates = &note_updates[1];

    %{ leaf_node_types[ids.return_collateral_note.index] = "note" %}
    %{
        note_output_idxs[ids.return_collateral_note.index] = note_outputs_len 
        note_outputs_len += 1
    %}

    let state_dict = state_dict + DictAccess.SIZE;

    // * Update the position dict
    let state_dict_ptr = state_dict;
    assert state_dict_ptr.key = position.index;
    assert state_dict_ptr.prev_value = prev_position_hash;
    assert state_dict_ptr.new_value = position.hash;

    let state_dict = state_dict + DictAccess.SIZE;

    %{ leaf_node_types[ids.position.index] = "position" %}
    %{ store_output_position(ids.position.address_, ids.position.index) %}

    return ();
}

// Hash the margin change message

func hash_margin_change_message{
    pedersen_ptr: HashBuiltin*, range_check_ptr, state_dict: DictAccess*
}(
    margin_change: felt,
    notes_in_len: felt,
    notes_in: Note*,
    refund_note: Note,
    close_order_fields: CloseOrderFields,
    position: PerpPosition,
) -> (res: felt) {
    alloc_locals;

    let cond = is_le(0, margin_change);

    if (cond == 1) {
        let (local empty_arr: felt*) = alloc();
        let (hashes_len: felt, hashes: felt*) = hash_notes_array(
            notes_in_len, notes_in, 0, empty_arr
        );

        let hash_ptr = pedersen_ptr;
        with hash_ptr {
            let (hash_state_ptr) = hash_init();
            let (hash_state_ptr) = hash_update(hash_state_ptr, hashes, hashes_len);
            let (hash_state_ptr) = hash_update_single(hash_state_ptr, refund_note.hash);
            let (hash_state_ptr) = hash_update_single(hash_state_ptr, position.hash);
            let (res) = hash_finalize(hash_state_ptr);
            let pedersen_ptr = hash_ptr;
            return (res=res);
        }
    } else {
        let (fields_hash: felt) = _hash_close_order_fields(close_order_fields);

        let hash_ptr = pedersen_ptr;

        with hash_ptr {
            let (hash_state_ptr) = hash_init();
            let (hash_state_ptr) = hash_update_single(hash_state_ptr, margin_change);
            let (hash_state_ptr) = hash_update_single(hash_state_ptr, fields_hash);
            let (hash_state_ptr) = hash_update_single(hash_state_ptr, position.hash);
            let (res) = hash_finalize(hash_state_ptr);
            let pedersen_ptr = hash_ptr;
            return (res=res);
        }
    }
}

func handle_inputs{pedersen_ptr: HashBuiltin*}(
    margin_change: felt*,
    notes_in_len: felt*,
    notes_in: Note**,
    refund_note: Note*,
    close_order_fields: CloseOrderFields*,
) {
    %{
        P = 2**251 + 17*2**192 + 1

        margin_change_ = None
        if int(current_margin_change_info["margin_change"]) >= 0:
            margin_change_ = int(current_margin_change_info["margin_change"])
        else:
            margin_change_ = P+int(current_margin_change_info["margin_change"])

        memory[ids.margin_change] = margin_change_


        input_notes = current_margin_change_info["notes_in"]

        memory[ids.notes_in_len] = notes_len = len(input_notes) if input_notes else 0
        memory[ids.notes_in] = notes_ = segments.add()
        for i in range(notes_len):
            memory[notes_ + i* NOTE_SIZE + ADDRESS_OFFSET+0] = int(input_notes[i]["address"]["x"])
            memory[notes_ + i* NOTE_SIZE + ADDRESS_OFFSET+1] = int(input_notes[i]["address"]["y"])
            memory[notes_ + i* NOTE_SIZE + TOKEN_OFFSET] = int(input_notes[i]["token"])
            memory[notes_ + i* NOTE_SIZE + AMOUNT_OFFSET] = int(input_notes[i]["amount"])
            memory[notes_ + i* NOTE_SIZE + BLINDING_FACTOR_OFFSET] = int(input_notes[i]["blinding"])
            memory[notes_ + i* NOTE_SIZE + INDEX_OFFSET] = int(input_notes[i]["index"])
            memory[notes_ + i* NOTE_SIZE + HASH_OFFSET] = int(input_notes[i]["hash"])


        refund_note = current_margin_change_info["refund_note"]
        if refund_note is not None:
            memory[ids.refund_note.address_ + ADDRESS_OFFSET+0] = int(refund_note["address"]["x"])
            memory[ids.refund_note.address_ + ADDRESS_OFFSET+1] = int(refund_note["address"]["y"])
            memory[ids.refund_note.address_ + TOKEN_OFFSET] = int(refund_note["token"])
            memory[ids.refund_note.address_ + AMOUNT_OFFSET] = int(refund_note["amount"])
            memory[ids.refund_note.address_ + BLINDING_FACTOR_OFFSET] = int(refund_note["blinding"])
            memory[ids.refund_note.address_ + INDEX_OFFSET] = int(refund_note["index"])
            memory[ids.refund_note.address_ + HASH_OFFSET] = int(refund_note["hash"])
        else:
            memory[ids.refund_note.address_ + ADDRESS_OFFSET+0] = 0
            memory[ids.refund_note.address_ + ADDRESS_OFFSET+1] = 0
            memory[ids.refund_note.address_ + TOKEN_OFFSET] = 0
            memory[ids.refund_note.address_ + AMOUNT_OFFSET] = 0
            memory[ids.refund_note.address_ + BLINDING_FACTOR_OFFSET] = 0
            memory[ids.refund_note.address_ + INDEX_OFFSET] = 0
            memory[ids.refund_note.address_ + HASH_OFFSET] = 0


        close_order_field_inputs = current_margin_change_info["close_order_fields"]


        memory[ids.close_order_fields.address_ + ids.CloseOrderFields.dest_received_address] = int(close_order_field_inputs["dest_received_address"]["x"]) if close_order_field_inputs  else 0
        memory[ids.close_order_fields.address_ + ids.CloseOrderFields.dest_received_blinding] = int(close_order_field_inputs["dest_received_blinding"]) if close_order_field_inputs else 0


        signature = current_margin_change_info["signature"]
    %}

    return ();
}
