from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import assert_le, assert_lt, unsigned_div_rem
from starkware.cairo.common.pow import pow

from unshielded_swaps.constants import MAX_AMOUNT, MAX_NONCE, MAX_EXPIRATION_TIMESTAMP
from rollup.global_config import price_decimals, token_decimals, GlobalConfig, get_dust_amount
from helpers.utils import Note, check_index_uniqueness, validate_fee_taken

from invisible_swaps.order.invisible_order import Invisibl3Order

// TODO: ALL OF THIS IS NOT THE BEST
func range_checks_{range_check_ptr}(
    invisibl3_order: Invisibl3Order, refund_note: Note, spend_amount: felt
) {
    alloc_locals;

    assert_lt(invisibl3_order.amount_spent, MAX_AMOUNT);
    assert_lt(invisibl3_order.amount_received, MAX_AMOUNT);

    // todo new_filled_amount = prev_filled_amount + spent_amount  (only in later fills)
    // todo assert_le(new_filled_amount, limit_order.amount_spent)

    assert_lt(invisibl3_order.order_id, MAX_NONCE);

    // todo let global_expiration_timestamp = ...?
    // todo assert_lt(global_expiration_timestamp, limit_order.expiration_timestamp)
    assert_lt(invisibl3_order.expiration_timestamp, MAX_EXPIRATION_TIMESTAMP);

    assert_le(0, refund_note.amount);
    assert_le(spend_amount, invisibl3_order.amount_spent);

    return ();
}

// --------------------------------------------------------------------------------------------------

func consistency_checks{range_check_ptr, global_config: GlobalConfig*}(
    invisibl3_order_A: Invisibl3Order,
    invisibl3_order_B: Invisibl3Order,
    spend_amountA: felt,
    spend_amountB: felt,
    fee_takenA: felt,
    fee_takenB: felt,
    notes_in_A_len: felt,
    notes_in_A: Note*,
    notes_in_B_len: felt,
    notes_in_B: Note*,
) {
    alloc_locals;
    // todo: Check the tokens are valid

    // ? Check that the tokens swapped match
    assert invisibl3_order_A.token_spent = invisibl3_order_B.token_received;
    assert invisibl3_order_A.token_received = invisibl3_order_B.token_spent;

    // ? Check that the amounts swapped dont exceed the order amounts
    let (dust_amount_a) = get_dust_amount(invisibl3_order_A.token_spent);
    let (dust_amount_b) = get_dust_amount(invisibl3_order_B.token_spent);
    assert_le(spend_amountA - dust_amount_a, invisibl3_order_A.amount_spent);
    assert_le(spend_amountB - dust_amount_b, invisibl3_order_B.amount_spent);

    // ? Verify consistency of amounts swaped
    let (dec1) = token_decimals(invisibl3_order_A.token_spent);
    let (dec2) = token_decimals(invisibl3_order_B.token_spent);
    // ? Check the price is consistent to 0.01% (1/10000)
    let (multiplier) = pow(10, dec1 + dec2 - 4);

    let a1_ = spend_amountA * invisibl3_order_A.amount_received;
    let a2_ = spend_amountB * invisibl3_order_A.amount_spent;
    let b1_ = spend_amountB * invisibl3_order_B.amount_received;
    let b2_ = spend_amountA * invisibl3_order_B.amount_spent;

    let (a1, _) = unsigned_div_rem(a1_, multiplier);
    let (a2, _) = unsigned_div_rem(a2_, multiplier);
    let (b1, _) = unsigned_div_rem(b1_, multiplier);
    let (b2, _) = unsigned_div_rem(b2_, multiplier);

    assert_le(a1, a2);
    assert_le(b1, b2);

    // ? Verify the fee taken is consistent with the order
    validate_fee_taken(
        fee_takenA, invisibl3_order_A.fee_limit, spend_amountB, invisibl3_order_A.amount_received
    );
    validate_fee_taken(
        fee_takenB, invisibl3_order_B.fee_limit, spend_amountA, invisibl3_order_B.amount_received
    );

    // ? Verify note uniqueness
    check_index_uniqueness(notes_in_A_len, notes_in_A);
    check_index_uniqueness(notes_in_B_len, notes_in_B);

    return ();
}
