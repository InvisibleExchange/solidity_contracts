from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.hash_state import (
    hash_init,
    hash_finalize,
    hash_update,
    hash_update_single,
)
from starkware.cairo.common.ec_point import EcPoint

from helpers.utils import Note, hash_note, hash_notes_array

from perpetuals.order.order_structs import (
    PerpOrder,
    OpenOrderFields,
    CloseOrderFields,
    PerpPosition,
)

// * HASH VERIFICATION FUNCTIONS * #

func verify_open_order_hash{pedersen_ptr: HashBuiltin*}(
    perp_order: PerpOrder, order_fields: OpenOrderFields
) {
    alloc_locals;

    assert perp_order.position_effect_type = 0;

    let (order_hash: felt) = _hash_perp_order_internal(perp_order);

    let (fields_hash: felt) = _hash_open_order_fields(order_fields);

    let (order_hash: felt) = hash2{hash_ptr=pedersen_ptr}(order_hash, fields_hash);

    assert order_hash = perp_order.hash;

    return ();
}

func verify_order_hash{pedersen_ptr: HashBuiltin*}(perp_order: PerpOrder) {
    let (order_hash: felt) = _hash_perp_order_internal(perp_order);

    assert order_hash = perp_order.hash;

    return ();
}

func verify_close_order_hash{pedersen_ptr: HashBuiltin*}(
    perp_order: PerpOrder, close_order_fields: CloseOrderFields
) {
    alloc_locals;

    assert perp_order.position_effect_type = 2;

    let (order_hash: felt) = _hash_perp_order_internal(perp_order);

    let (fields_hash: felt) = _hash_close_order_fields(close_order_fields);

    let (final_hash: felt) = hash2{hash_ptr=pedersen_ptr}(order_hash, fields_hash);

    assert final_hash = perp_order.hash;

    return ();
}

func verify_position_hash{pedersen_ptr: HashBuiltin*}(position: PerpPosition) {
    let (position_hash: felt) = _hash_position_internal(
        position.order_side,
        position.synthetic_token,
        position.position_size,
        position.entry_price,
        position.liquidation_price,
        position.position_address,
        position.last_funding_idx,
    );

    assert position_hash = position.hash;

    return ();
}

// * HASH FUNCTION HELPERS * #

func _hash_position_internal{pedersen_ptr: HashBuiltin*}(
    order_side: felt,
    synthetic_token: felt,
    position_size: felt,
    entry_price: felt,
    liquidation_price: felt,
    position_address: felt,
    last_funding_idx: felt,
) -> (res: felt) {
    alloc_locals;

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state_ptr) = hash_init();
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, order_side);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, synthetic_token);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, position_size);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, entry_price);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, liquidation_price);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, position_address);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, last_funding_idx);
        let (res) = hash_finalize(hash_state_ptr);
        let pedersen_ptr = hash_ptr;
        return (res=res);
    }
}

func _hash_open_order_fields{pedersen_ptr: HashBuiltin*}(order_fields: OpenOrderFields) -> (
    res: felt
) {
    alloc_locals;

    let (local empty_arr) = alloc();
    let (hashed_notes_in_len: felt, hashed_notes_in: felt*) = hash_notes_array(
        order_fields.notes_in_len, order_fields.notes_in, 0, empty_arr
    );
    let (refund_note_hash: felt) = hash_note(order_fields.refund_note);

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state_ptr) = hash_init();
        let (hash_state_ptr) = hash_update(hash_state_ptr, hashed_notes_in, hashed_notes_in_len);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, refund_note_hash);

        let (hash_state_ptr) = hash_update_single(hash_state_ptr, order_fields.initial_margin);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, order_fields.collateral_token);

        let (hash_state_ptr) = hash_update_single(hash_state_ptr, order_fields.position_address);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, order_fields.blinding);

        let (res) = hash_finalize(hash_state_ptr);
        let pedersen_ptr = hash_ptr;
        return (res=res);
    }
}

func _hash_close_order_fields{pedersen_ptr: HashBuiltin*}(close_order_fields: CloseOrderFields) -> (
    res: felt
) {
    alloc_locals;

    let (hash: felt) = hash2{hash_ptr=pedersen_ptr}(
        close_order_fields.return_collateral_address, close_order_fields.return_collateral_blinding
    );

    return (res=hash);
}

func _hash_perp_order_internal{pedersen_ptr: HashBuiltin*}(perp_order: PerpOrder) -> (res: felt) {
    alloc_locals;

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state_ptr) = hash_init();
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, perp_order.expiration_timestamp);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, perp_order.pos_addr_string);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, perp_order.position_effect_type);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, perp_order.order_side);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, perp_order.synthetic_token);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, perp_order.synthetic_amount);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, perp_order.collateral_amount);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, perp_order.fee_limit);
        let (res) = hash_finalize(hash_state_ptr);
        let pedersen_ptr = hash_ptr;
        return (res=res);
    }
}
