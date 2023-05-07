from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import unsigned_div_rem, signed_div_rem, assert_le
from starkware.cairo.common.math_cmp import is_nn
from starkware.cairo.common.pow import pow
from starkware.cairo.common.hash_state import (
    hash_init,
    hash_finalize,
    hash_update,
    hash_update_single,
)

from helpers.utils import Note, hash_note, hash_notes_array, get_price
from rollup.global_config import token_decimals, price_decimals, GlobalConfig

// * CALCULATE PRICES * #

func _get_entry_price{range_check_ptr, global_config: GlobalConfig*}(
    size: felt, initial_margin: felt, leverage: felt, synthetic_token: felt
) -> (price: felt) {
    alloc_locals;

    let collateral_decimals = 6;  // Hardcoded for now
    let leverage_decimals = 6;  // Hardcoded for now

    let (synthetic_decimals: felt) = token_decimals(synthetic_token);
    let (synthetic_price_decimals: felt) = price_decimals(synthetic_token);

    let decimal_conversion = synthetic_decimals + synthetic_price_decimals - (
        collateral_decimals + leverage_decimals
    );

    let (multiplier: felt) = pow(10, decimal_conversion);

    let (price: felt, _) = unsigned_div_rem(initial_margin * leverage * multiplier, size);

    return (price,);
}

func _get_liquidation_price{range_check_ptr}(
    entry_price: felt, bankruptcy_price: felt, order_side: felt
) -> (price: felt) {
    alloc_locals;

    if (bankruptcy_price == 0) {
        return (0,);
    }

    let mm_rate = 3;  // 2% of 100

    if (order_side == 0) {
        let (t1: felt, _) = unsigned_div_rem(mm_rate * entry_price, 100);
        let liquidation_price = bankruptcy_price + t1;
        return (liquidation_price,);
    } else {
        let (t1: felt, _) = unsigned_div_rem(mm_rate * entry_price, 100);
        let liquidation_price = bankruptcy_price - t1;
        return (liquidation_price,);
    }
}

func _get_bankruptcy_price{range_check_ptr, global_config: GlobalConfig*}(
    entry_price: felt, margin: felt, size: felt, order_side: felt, synthetic_token: felt
) -> (price: felt) {
    alloc_locals;

    let collateral_decimals = 6;  // Hardcoded for now

    let (synthetic_decimals: felt) = token_decimals(synthetic_token);
    let (synthetic_price_decimals: felt) = price_decimals(synthetic_token);

    tempvar decimal_conversion = synthetic_decimals + synthetic_price_decimals -
        collateral_decimals;
    let (multiplier: felt) = pow(10, decimal_conversion);

    if (order_side == 0) {
        let (t1: felt, _) = unsigned_div_rem(margin * multiplier, size);
        let bankruptcy_price = entry_price - t1;

        let c1: felt = is_nn(bankruptcy_price);
        if (c1 == 0) {
            return (0,);
        }

        return (bankruptcy_price,);
    } else {
        let (t1: felt, _) = unsigned_div_rem(margin * multiplier, size);
        let bankruptcy_price = entry_price + t1;
        return (bankruptcy_price,);
    }
}
