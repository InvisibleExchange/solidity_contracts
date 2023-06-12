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
from rollup.global_config import (
    token_decimals,
    price_decimals,
    get_min_partial_liquidation_size,
    GlobalConfig,
)

// * CALCULATE PRICES * #

func _get_entry_price{range_check_ptr, global_config: GlobalConfig*}(
    size: felt, initial_margin: felt, leverage: felt, synthetic_token: felt
) -> (price: felt) {
    alloc_locals;

    let (collateral_decimals) = token_decimals(global_config.collateral_token);
    let leverage_decimals = global_config.leverage_decimals;

    let (synthetic_decimals: felt) = token_decimals(synthetic_token);
    let (synthetic_price_decimals: felt) = price_decimals(synthetic_token);

    let decimal_conversion = synthetic_decimals + synthetic_price_decimals - (
        collateral_decimals + leverage_decimals
    );

    let (multiplier: felt) = pow(10, decimal_conversion);

    let (price: felt, _) = unsigned_div_rem(initial_margin * leverage * multiplier, size);

    return (price,);
}

func _get_liquidation_price{range_check_ptr, global_config: GlobalConfig*}(
    entry_price: felt,
    position_size: felt,
    margin: felt,
    order_side: felt,
    synthetic_token: felt,
    is_partial_liquidation_: felt,
) -> (price: felt) {
    alloc_locals;

    let (min_partial_liquidation_size) = get_min_partial_liquidation_size(synthetic_token);

    let size_partialy_liquidatable = is_nn(position_size - min_partial_liquidation_size - 1);
    let is_partial_liquidation = is_partial_liquidation_ * size_partialy_liquidatable;

    let mm_fraction = 3 + is_partial_liquidation;  // 3/4% of 100

    let (collateral_decimals) = token_decimals(global_config.collateral_token);

    let (synthetic_decimals: felt) = token_decimals(synthetic_token);
    let (synthetic_price_decimals: felt) = price_decimals(synthetic_token);

    let decimal_conversion = synthetic_decimals + synthetic_price_decimals - collateral_decimals;
    let (multiplier) = pow(10, decimal_conversion);

    let d1 = margin * multiplier;
    let d2 = mm_fraction * entry_price * position_size / 100;

    if (order_side == 1) {
        if (position_size == 0) {
            return (0,);
        }

        let (price_delta, _) = unsigned_div_rem(
            (d1 - d2) * 100, (100 - mm_fraction) * position_size
        );

        let liquidation_price = entry_price - price_delta;

        let is_nn_ = is_nn(liquidation_price);
        if (is_nn_ == 1) {
            return (liquidation_price,);
        } else {
            return (0,);
        }
    } else {
        if (position_size == 0) {
            let (p) = pow(10, synthetic_price_decimals);

            return (1000000000 * p,);
        }

        let (price_delta, _) = unsigned_div_rem(
            (d1 - d2) * 100, (100 + mm_fraction) * position_size
        );

        let liquidation_price = entry_price + price_delta;

        return (liquidation_price,);
    }
}

func _get_bankruptcy_price{range_check_ptr, global_config: GlobalConfig*}(
    entry_price: felt, margin: felt, size: felt, order_side: felt, synthetic_token: felt
) -> (price: felt) {
    alloc_locals;

    let (collateral_decimals) = token_decimals(global_config.collateral_token);

    let (synthetic_decimals: felt) = token_decimals(synthetic_token);
    let (synthetic_price_decimals: felt) = price_decimals(synthetic_token);

    tempvar decimal_conversion = synthetic_decimals + synthetic_price_decimals -
        collateral_decimals;
    let (multiplier: felt) = pow(10, decimal_conversion);

    if (order_side == 1) {
        if (size == 0) {
            return (0,);
        }

        let (t1: felt, _) = unsigned_div_rem(margin * multiplier, size);
        let bankruptcy_price = entry_price - t1;

        let c1: felt = is_nn(bankruptcy_price);
        if (c1 == 0) {
            return (0,);
        }

        return (bankruptcy_price,);
    } else {
        if (size == 0) {
            let (p) = pow(10, synthetic_price_decimals);

            return (1000000000 * p,);
        }

        let (t1: felt, _) = unsigned_div_rem(margin * multiplier, size);
        let bankruptcy_price = entry_price + t1;
        return (bankruptcy_price,);
    }
}
