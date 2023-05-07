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
from helpers.signatures.signatures import verify_margin_change_signature

from rollup.global_config import GlobalConfig

func execute_margin_change{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    note_dict: DictAccess*,
    position_dict: DictAccess*,
    ecdsa_ptr: SignatureBuiltin*,
    global_config: GlobalConfig*,
}() {
    alloc_locals;

    local margin_change: felt;
    local notes_in_len: felt;
    local notes_in: Note*;
    local refund_note: Note;
    local close_order_fields: CloseOrderFields;
    local position: PerpPosition;
    // local signature: SignatureBuiltin;

    let (__fp__, _) = get_fp_and_pc();
    handle_inputs(
        &margin_change, &notes_in_len, &notes_in, &refund_note, &close_order_fields, &position
    );

    let (msg_hash: felt) = hash_margin_change_message(
        margin_change, notes_in_len, notes_in, refund_note, close_order_fields, position
    );

    let is_increase: felt = is_le(0, margin_change);
    verify_margin_change_signature(
        msg_hash, notes_in_len, notes_in, position.position_address, is_increase
    );

    let (new_position: PerpPosition) = modify_margin(position, margin_change);

    if (is_increase == 1) {
        // ? Sum notes and verify amount being spent
        let (total_notes_in: felt) = sum_notes(
            notes_in_len, notes_in, position.collateral_token, 0
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
            close_order_fields.return_collateral_address,
            position.collateral_token,
            return_value,
            close_order_fields.return_collateral_blinding,
            index,
        );

        // ? Update the state
        update_state_after_decrease(return_collateral_note, new_position, position.hash);
    }

    return ();
}

func update_state_after_increase{
    pedersen_ptr: HashBuiltin*, range_check_ptr, note_dict: DictAccess*, position_dict: DictAccess*
}(
    notes_in_len: felt,
    notes_in: Note*,
    refund_note: Note,
    position: PerpPosition,
    prev_position_hash: felt,
) {
    let note_dict_ptr = note_dict;
    assert note_dict_ptr.key = notes_in[0].index;
    assert note_dict_ptr.prev_value = notes_in[0].hash;
    assert note_dict_ptr.new_value = refund_note.hash;

    %{
        output_notes[memory[ids.notes_in.address_ + INDEX_OFFSET]] = {
            "address": {"x": ids.refund_note.address.x, "y": ids.refund_note.address.y},
            "hash": ids.refund_note.hash,
            "index": ids.refund_note.index,
            "blinding": ids.refund_note.blinding_factor,
            "token": ids.refund_note.token,
            "amount": ids.refund_note.amount,
        }
    %}

    let note_dict = note_dict + DictAccess.SIZE;

    // * Update the position dict
    let position_dict_ptr = position_dict;
    assert position_dict_ptr.key = position.index;
    assert position_dict_ptr.prev_value = prev_position_hash;
    assert position_dict_ptr.new_value = position.hash;

    let position_dict = position_dict + DictAccess.SIZE;

    %{
        output_positions[ids.position.index] = {
            "order_side": ids.position.order_side,
            "synthetic_token": ids.position.synthetic_token,
            "collateral_token": ids.position.collateral_token,
            "position_size": ids.position.position_size,
            "margin": ids.position.margin,
            "entry_price": ids.position.entry_price,
            "liquidation_price": ids.position.liquidation_price,
            "bankruptcy_price": ids.position.bankruptcy_price,
            "position_address": ids.position.position_address,
            "last_funding_idx": ids.position.last_funding_idx,
            "index": ids.position.index,
            "hash": ids.position.hash,
        }
    %}

    return update_state_after_increase_inner(notes_in_len - 1, &notes_in[1]);
}

func update_state_after_increase_inner{
    pedersen_ptr: HashBuiltin*, range_check_ptr, note_dict: DictAccess*, position_dict: DictAccess*
}(notes_in_len: felt, notes_in: Note*) {
    if (notes_in_len == 0) {
        return ();
    }

    let note_dict_ptr = note_dict;
    assert note_dict_ptr.key = notes_in[0].index;
    assert note_dict_ptr.prev_value = notes_in[0].hash;
    assert note_dict_ptr.new_value = 0;

    let note_dict = note_dict + DictAccess.SIZE;

    return update_state_after_increase_inner(notes_in_len - 1, &notes_in[1]);
}

func update_state_after_decrease{
    pedersen_ptr: HashBuiltin*, range_check_ptr, note_dict: DictAccess*, position_dict: DictAccess*
}(return_collateral_note: Note, position: PerpPosition, prev_position_hash: felt) {
    let note_dict_ptr = note_dict;
    assert note_dict_ptr.key = return_collateral_note.index;
    assert note_dict_ptr.prev_value = 0;
    assert note_dict_ptr.new_value = return_collateral_note.hash;

    %{
        output_notes[ids.return_collateral_note.index] = {
            "address": {"x": ids.return_collateral_note.address.x, "y": ids.return_collateral_note.address.y},
            "hash": ids.return_collateral_note.hash,
            "index": ids.return_collateral_note.index,
            "blinding": ids.return_collateral_note.blinding_factor,
            "token": ids.return_collateral_note.token,
            "amount": ids.return_collateral_note.amount,
        }
    %}

    let note_dict = note_dict + DictAccess.SIZE;

    // * Update the position dict
    let position_dict_ptr = position_dict;
    assert position_dict_ptr.key = position.index;
    assert position_dict_ptr.prev_value = prev_position_hash;
    assert position_dict_ptr.new_value = position.hash;

    let position_dict = position_dict + DictAccess.SIZE;

    %{
        output_positions[ids.position.index] = {
            "order_side": ids.position.order_side,
            "synthetic_token": ids.position.synthetic_token,
            "collateral_token": ids.position.collateral_token,
            "position_size": ids.position.position_size,
            "margin": ids.position.margin,
            "entry_price": ids.position.entry_price,
            "liquidation_price": ids.position.liquidation_price,
            "bankruptcy_price": ids.position.bankruptcy_price,
            "position_address": ids.position.position_address,
            "last_funding_idx": ids.position.last_funding_idx,
            "index": ids.position.index,
            "hash": ids.position.hash,
        }
    %}

    return ();
}

// Hash the margin change message

func hash_margin_change_message{
    pedersen_ptr: HashBuiltin*, range_check_ptr, note_dict: DictAccess*
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
    position: PerpPosition*,
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


        memory[ids.close_order_fields.address_ + RETURN_COLLATERAL_ADDRESS_OFFSET] = int(close_order_field_inputs["dest_received_address"]["x"]) if close_order_field_inputs  else 0
        memory[ids.close_order_fields.address_ + RETURN_COLLATERAL_BLINDING_OFFSET] = int(close_order_field_inputs["dest_received_blinding"]) if close_order_field_inputs else 0


        position = current_margin_change_info["position"]

        memory[ids.position.address_ + PERP_POSITION_ORDER_SIDE_OFFSET] = 0 if position["order_side"] == "Long" else 1
        memory[ids.position.address_ + PERP_POSITION_SYNTHETIC_TOKEN_OFFSET] = int(position["synthetic_token"])
        memory[ids.position.address_ + PERP_POSITION_COLLATERAL_TOKEN_OFFSET] = int(position["collateral_token"])
        memory[ids.position.address_ + PERP_POSITION_POSITION_SIZE_OFFSET] = int(position["position_size"])
        memory[ids.position.address_ + PERP_POSITION_MARGIN_OFFSET] = int(position["margin"])
        memory[ids.position.address_ + PERP_POSITION_ENTRY_PRICE_OFFSET] = int(position["entry_price"])
        memory[ids.position.address_ + PERP_POSITION_LIQUIDATION_PRICE_OFFSET] = int(position["liquidation_price"])
        memory[ids.position.address_ + PERP_POSITION_BANKRUPTCY_PRICE_OFFSET] = int(position["bankruptcy_price"])
        memory[ids.position.address_ + PERP_POSITION_ADDRESS_OFFSET] = int(position["position_address"])
        memory[ids.position.address_ + PERP_POSITION_LAST_FUNDING_IDX_OFFSET] = int(position["last_funding_idx"])
        memory[ids.position.address_ + PERP_POSITION_INDEX_OFFSET] = int(position["index"])
        memory[ids.position.address_ + PERP_POSITION_HASH_OFFSET] = int(position["hash"])


        signature = current_margin_change_info["signature"]
    %}

    return ();
}

// ? GET INIT MARGIN
func get_init_margin{range_check_ptr}(
    order: PerpOrder, open_order_fields: OpenOrderFields, spent_synthetic: felt
) -> felt {
    alloc_locals;

    let quotient = open_order_fields.initial_margin * spent_synthetic;
    let divisor = order.synthetic_amount;

    let (margin, _) = unsigned_div_rem(quotient, divisor);

    return margin;
}
