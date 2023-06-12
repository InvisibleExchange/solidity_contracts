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

from helpers.utils import Note, check_index_uniqueness

from unshielded_swaps.constants import MAX_AMOUNT, MAX_ORDER_ID, MAX_NONCE, MAX_EXPIRATION_TIMESTAMP

from perpetuals.order.order_structs import PerpOrder, OpenOrderFields

from rollup.global_config import get_dust_amount, GlobalConfig, token_decimals

func consistency_checks{range_check_ptr, global_config: GlobalConfig*}(
    order_a: PerpOrder,
    order_b: PerpOrder,
    spent_collateral: felt,
    spent_synthetic: felt,
    fee_taken_a: felt,
    fee_taken_b: felt,
) {
    alloc_locals;

    // TODO: Check that collateral and synthetic tokens are valid

    // ? Check that the synthetic and collateral tokens are the same for both orders
    assert order_a.synthetic_token = order_b.synthetic_token;

    // ? for simplicity, we require order_a to be the "buyer" and order_b to be the "seller"
    assert order_a.order_side = 1;  // Long Order
    assert order_b.order_side = 0;  // Short Order

    // ? Check that the amounts swapped don't exceed the order amounts
    let (dust_amount1) = get_dust_amount(order_a.synthetic_token);
    let (dust_amount2) = get_dust_amount(global_config.collateral_token);
    assert_le(spent_collateral - dust_amount2, order_a.collateral_amount);
    assert_le(spent_synthetic - dust_amount1, order_b.synthetic_amount);

    // & If the order is short than more collateral and less synthetic is good (higher price)
    // & If the order is long than more synthetic and less collateral is good (lower price)
    // ? Verify consistency of amounts swaped
    let (dec1) = token_decimals(order_a.synthetic_token);
    let (dec2) = token_decimals(global_config.collateral_token);
    // ? Check the price is consistent to 0.01% (1/10000)
    let (multiplier) = pow(10, dec1 + dec2 - 4);

    let a1_ = spent_collateral * order_a.synthetic_amount;
    let a2_ = spent_synthetic * order_a.collateral_amount;
    let b1_ = spent_synthetic * order_b.collateral_amount;
    let b2_ = spent_collateral * order_b.synthetic_amount;

    let (a1, _) = unsigned_div_rem(a1_, multiplier);
    let (a2, _) = unsigned_div_rem(a2_, multiplier);
    let (b1, _) = unsigned_div_rem(b1_, multiplier);
    let (b2, _) = unsigned_div_rem(b2_, multiplier);

    assert_le(a1, a2);
    assert_le(b1, b2);

    // ? Verify the fee taken is consistent with the order
    validate_fee_taken(fee_taken_a, order_a, spent_collateral);
    validate_fee_taken(fee_taken_b, order_b, spent_collateral);

    return ();
}

func validate_fee_taken{range_check_ptr}(
    fee_taken: felt, order: PerpOrder, spent_collateral: felt
) {
    // ? Check that the fees taken don't exceed the order fees
    assert_le(fee_taken * order.collateral_amount, order.fee_limit * spent_collateral);

    return ();
}

func checks_prev_fill_consistencies{range_check_ptr}(
    order: PerpOrder, open_order_fields: OpenOrderFields, init_margin: felt, pfr_note: Note
) {
    // TODO: Check that collateral token is valid (or the same as previous one?)
    // assert pfr_note.token = order.collateral_token;

    assert pfr_note.token = open_order_fields.collateral_token;

    assert_le(init_margin, pfr_note.amount);

    assert pfr_note.address.x = open_order_fields.notes_in[0].address.x;

    return ();
}

func range_checks{range_check_ptr}(order_a: PerpOrder, order_b: PerpOrder) {
    assert_le(order_a.collateral_amount, MAX_AMOUNT);
    assert_le(order_a.synthetic_amount, MAX_AMOUNT);
    assert_le(order_b.collateral_amount, MAX_AMOUNT);
    assert_le(order_b.synthetic_amount, MAX_AMOUNT);

    assert_le(order_a.expiration_timestamp, MAX_EXPIRATION_TIMESTAMP);
    assert_le(order_b.expiration_timestamp, MAX_EXPIRATION_TIMESTAMP);

    assert_le(order_a.position_effect_type, 3);
    assert_le(order_b.position_effect_type, 3);

    assert_le(order_a.order_side, 1);
    assert_le(order_b.order_side, 1);

    return ();
}

func open_order_specific_checks{range_check_ptr}(
    order: PerpOrder,
    open_order_fields: OpenOrderFields,
    spent_synthetic: felt,
    init_margin: felt,
    fee_taken: felt,
) {
    // // ? Check that the init_margin ratio is good enough
    // assert_le(
    //     init_margin * order.synthetic_amount, open_order_fields.initial_margin * spent_synthetic
    // );

    // ? Check that note indexes are unique
    check_index_uniqueness(open_order_fields.notes_in_len, open_order_fields.notes_in);

    // Todo: Maybe check max leverage consistency

    return ();
}
