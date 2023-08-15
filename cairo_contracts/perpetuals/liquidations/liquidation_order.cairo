from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.hash_state import (
    hash_init,
    hash_finalize,
    hash_update,
    hash_update_single,
)

from perpetuals.order.order_structs import PerpPosition, OpenOrderFields
from perpetuals.order.order_hash import _hash_open_order_fields

struct LiquidationOrder {
    order_side: felt,
    synthetic_token: felt,
    synthetic_amount: felt,
    collateral_amount: felt,
    //
    hash: felt,
}

func verify_liquidation_order_hash{pedersen_ptr: HashBuiltin*}(
    liquidation_order: LiquidationOrder, open_order_fields: OpenOrderFields, position: PerpPosition
) {
    let (fields_hash: felt) = _hash_open_order_fields(open_order_fields);

    let hash = hash_liquidation_order(
        position.position_header.position_address,
        liquidation_order.order_side,
        liquidation_order.synthetic_token,
        liquidation_order.synthetic_amount,
        liquidation_order.collateral_amount,
        fields_hash,
    );

    assert hash = liquidation_order.hash;

    return ();
}

func hash_liquidation_order{pedersen_ptr: HashBuiltin*}(
    position_address: felt,
    order_side: felt,
    synthetic_token: felt,
    synthetic_amount: felt,
    collateral_amount: felt,
    open_order_fields_hash: felt,
) -> felt {
    alloc_locals;

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state_ptr) = hash_init();
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, position_address);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, order_side);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, synthetic_token);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, synthetic_amount);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, collateral_amount);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, open_order_fields_hash);
        let (res) = hash_finalize(hash_state_ptr);
        let pedersen_ptr = hash_ptr;
        return res;
    }
}
