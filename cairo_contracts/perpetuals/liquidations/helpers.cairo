from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin, BitwiseBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.dict import dict_new, dict_write, dict_update, dict_squash, dict_read
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import unsigned_div_rem, assert_le, assert_not_equal
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.pow import pow
from starkware.cairo.common.bitwise import bitwise_xor, bitwise_and
from starkware.cairo.common.hash_state import (
    hash_init,
    hash_finalize,
    hash_update,
    hash_update_single,
)

from helpers.utils import Note, check_index_uniqueness, sum_notes, get_price
from helpers.spot_helpers.dict_updates import _update_multi_inner

from unshielded_swaps.constants import MAX_AMOUNT, MAX_ORDER_ID, MAX_NONCE, MAX_EXPIRATION_TIMESTAMP

from perpetuals.order.order_structs import OpenOrderFields, PerpPosition
from perpetuals.liquidations.liquidation_order import LiquidationOrder

from rollup.global_config import get_dust_amount, GlobalConfig, token_decimals

func liquidation_consistency_checks{range_check_ptr, global_config: GlobalConfig*}(
    liquidation_order: LiquidationOrder,
    position: PerpPosition,
    open_order_fields: OpenOrderFields,
    market_price: felt,
) {
    alloc_locals;

    // TODO: Check that collateral and synthetic tokens are valid

    // ? Check that the synthetic tokens are the same for both orders
    let synthetic_token = position.position_header.synthetic_token;
    assert synthetic_token = liquidation_order.synthetic_token;

    assert liquidation_order.order_side = position.order_side;

    // ? Check that note indexes are unique
    check_index_uniqueness(open_order_fields.notes_in_len, open_order_fields.notes_in);

    // ? Check that the notes_in and refund note have valid tokens and amounts
    let (notes_in_sum) = sum_notes(
        open_order_fields.notes_in_len,
        open_order_fields.notes_in,
        global_config.collateral_token,
        0,
    );
    if (open_order_fields.refund_note.hash != 0) {
        assert open_order_fields.refund_note.token = global_config.collateral_token;
    }

    // ? Check that the amount of collateral is enough to cover the initial_margin
    assert notes_in_sum - open_order_fields.refund_note.amount = open_order_fields.initial_margin;

    // ? assert the market price is atleaset as good as the order price

    let (order_price: felt) = get_price(
        synthetic_token, liquidation_order.collateral_amount, liquidation_order.synthetic_amount
    );

    // ? Check that the market price is at least as good as the order price
    if (liquidation_order.order_side == 1) {
        assert_le(market_price, order_price);
    } else {
        assert_le(order_price, market_price);
    }

    return ();
}

func liquidation_note_state_updates{
    pedersen_ptr: HashBuiltin*, state_dict: DictAccess*, note_updates: Note*
}(open_order_fields: OpenOrderFields, new_position: PerpPosition) {
    alloc_locals;

    // ? Add the new position to the state
    let state_dict_ptr = state_dict;
    assert state_dict_ptr.key = new_position.index;
    assert state_dict_ptr.prev_value = 0;
    assert state_dict_ptr.new_value = new_position.hash;

    let state_dict = state_dict + DictAccess.SIZE;
    %{ leaf_node_types[ids.new_position.index] = "position" %}

    %{ store_output_position(ids.new_position.address_, ids.new_position.index) %}

    // ? Remove the notes from the state
    _update_multi_inner(open_order_fields.notes_in_len, open_order_fields.notes_in);

    let pedersen_tmp = pedersen_ptr;

    let refund_note = open_order_fields.refund_note;
    if (refund_note.hash != 0) {
        let state_dict_ptr = state_dict;
        assert state_dict_ptr.key = refund_note.index;
        assert state_dict_ptr.prev_value = 0;
        assert state_dict_ptr.new_value = refund_note.hash;

        let state_dict = state_dict + DictAccess.SIZE;

        assert note_updates[0] = refund_note;
        let note_updates = &note_updates[1];

        // ? store to an array used for program outputs
        %{ leaf_node_types[ids.refund_note.index] = "note" %}
        %{
            note_output_idxs[ids.refund_note.index] = note_outputs_len 
            note_outputs_len += 1
        %}

        
        let pedersen_ptr = pedersen_tmp;
        return ();
    } else {
        let pedersen_ptr = pedersen_tmp;
        return ();
    }
}
