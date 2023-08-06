from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import unsigned_div_rem, signed_div_rem, assert_le
from starkware.cairo.common.math_cmp import is_not_zero, is_le
from starkware.cairo.common.pow import pow
from starkware.cairo.common.hash_state import (
    hash_init,
    hash_finalize,
    hash_update,
    hash_update_single,
)
from starkware.cairo.common.ec_point import EcPoint

from helpers.utils import Note, get_price
from rollup.global_config import token_decimals, price_decimals, GlobalConfig

from perpetuals.order.order_structs import PerpPosition, PositionHeader

from perpetuals.order.order_hash import _hash_position_internal, _hash_position_header

from perpetuals.prices.prices import PriceRange, validate_price_in_range
from perpetuals.funding.funding import FundingInfo, apply_funding

from perpetuals.order.order_helpers import (
    _get_entry_price,
    _get_liquidation_price,
    _get_bankruptcy_price,
)

// * ====================================================================================

func construct_new_position{
    range_check_ptr, pedersen_ptr: HashBuiltin*, global_config: GlobalConfig*
}(
    order_side: felt,
    synthetic_token: felt,
    collateral_token: felt,
    position_size: felt,
    margin: felt,
    leverage: felt,
    position_address: felt,
    funding_idx: felt,
    idx: felt,
    fee_taken: felt,
    allow_partial_liquidations: felt,
) -> (position: PerpPosition) {
    alloc_locals;

    let (entry_price: felt) = _get_entry_price(position_size, margin, leverage, synthetic_token);

    let (bankruptcy_price: felt) = _get_bankruptcy_price(
        entry_price, margin - fee_taken, position_size, order_side, synthetic_token
    );

    let (liquidation_price: felt) = _get_liquidation_price(
        entry_price,
        position_size,
        margin - fee_taken,
        order_side,
        synthetic_token,
        allow_partial_liquidations,
    );

    let (header_hash: felt) = _hash_position_header(
        synthetic_token, allow_partial_liquidations, position_address
    );
    let position_header: PositionHeader = PositionHeader(
        synthetic_token, position_address, allow_partial_liquidations, header_hash
    );

    let (hash: felt) = _hash_position_internal(
        header_hash, order_side, position_size, entry_price, liquidation_price, funding_idx
    );

    let position: PerpPosition = PerpPosition(
        position_header,
        order_side,
        position_size,
        margin - fee_taken,
        entry_price,
        liquidation_price,
        bankruptcy_price,
        funding_idx,
        idx,
        hash,
    );

    return (position,);
}

// * ====================================================================================

func add_margin_to_position_internal{
    range_check_ptr,
    pedersen_ptr: HashBuiltin*,
    funding_info: FundingInfo*,
    global_config: GlobalConfig*,
}(
    position: PerpPosition,
    added_margin: felt,
    added_entry_price: felt,
    added_leverage: felt,
    fee_taken: felt,
    funding_idx: felt,
) -> (position: PerpPosition) {
    alloc_locals;

    let (collateral_decimals) = token_decimals(global_config.collateral_token);
    let leverage_decimals = global_config.leverage_decimals;

    let (synthetic_decimals: felt) = token_decimals(position.position_header.synthetic_token);
    let (synthetic_price_decimals: felt) = price_decimals(position.position_header.synthetic_token);

    tempvar decimal_conversion = synthetic_decimals + synthetic_price_decimals - (
        collateral_decimals + leverage_decimals
    );
    let (multiplier: felt) = pow(10, decimal_conversion);

    let (added_size, _) = unsigned_div_rem(
        added_margin * added_leverage * multiplier, added_entry_price
    );

    let added_margin = added_margin - fee_taken;

    let prev_nominal = position.position_size * position.entry_price;
    let new_nominal = added_size * added_entry_price;

    let (average_entry_price, _) = unsigned_div_rem(
        prev_nominal + new_nominal, position.position_size + added_size
    );

    let mm_rate = 3;  // 3% of 100

    // # & apply funding
    let (margin_after_funding) = apply_funding(position, funding_idx);

    let margin = margin_after_funding + added_margin;

    let (bankruptcy_price: felt) = _get_bankruptcy_price(
        average_entry_price,
        margin,
        position.position_size + added_size,
        position.order_side,
        position.position_header.synthetic_token,
    );
    let (liquidation_price: felt) = _get_liquidation_price(
        average_entry_price,
        position.position_size + added_size,
        margin,
        position.order_side,
        position.position_header.synthetic_token,
        position.position_header.allow_partial_liquidations,
    );

    let updated_size = position.position_size + added_size;

    let (new_position_hash: felt) = _hash_position_internal(
        position.position_header.hash,
        position.order_side,
        updated_size,
        average_entry_price,
        liquidation_price,
        funding_idx,
    );

    let new_position = PerpPosition(
        position.position_header,
        position.order_side,
        updated_size,
        margin,
        average_entry_price,
        liquidation_price,
        bankruptcy_price,
        funding_idx,
        position.index,
        new_position_hash,
    );

    return (new_position,);
}

func increase_position_size_internal{
    range_check_ptr,
    pedersen_ptr: HashBuiltin*,
    funding_info: FundingInfo*,
    global_config: GlobalConfig*,
}(
    position: PerpPosition, added_size: felt, added_price: felt, fee_taken: felt, funding_idx: felt
) -> (position: PerpPosition) {
    alloc_locals;

    let (collateral_decimals) = token_decimals(global_config.collateral_token);

    let (synthetic_decimals: felt) = token_decimals(position.position_header.synthetic_token);
    let (synthetic_price_decimals: felt) = price_decimals(position.position_header.synthetic_token);

    let prev_nominal = position.position_size * position.entry_price;
    let new_nominal = added_size * added_price;

    let (average_entry_price, _) = unsigned_div_rem(
        prev_nominal + new_nominal, position.position_size + added_size
    );

    let mm_rate = 3;  // 2% of 100
    // let maintnance_margin = (prev_nominal + new_nominal) * mm_rate

    tempvar decimal_conversion = synthetic_decimals + synthetic_price_decimals -
        collateral_decimals;
    let (multiplier: felt) = pow(10, decimal_conversion);

    // & apply funding
    let (margin_after_funding) = apply_funding(position, funding_idx);

    let updated_size = position.position_size + added_size;

    let (bankruptcy_price: felt) = _get_bankruptcy_price(
        average_entry_price,
        margin_after_funding - fee_taken,
        updated_size,
        position.order_side,
        position.position_header.synthetic_token,
    );
    let (liquidation_price: felt) = _get_liquidation_price(
        average_entry_price,
        updated_size,
        margin_after_funding - fee_taken,
        position.order_side,
        position.position_header.synthetic_token,
        position.position_header.allow_partial_liquidations,
    );

    let (new_position_hash: felt) = _hash_position_internal(
        position.position_header.hash,
        position.order_side,
        updated_size,
        average_entry_price,
        liquidation_price,
        funding_idx,
    );

    let new_position = PerpPosition(
        position.position_header,
        position.order_side,
        updated_size,
        margin_after_funding - fee_taken,
        average_entry_price,
        liquidation_price,
        bankruptcy_price,
        funding_idx,
        position.index,
        new_position_hash,
    );

    return (new_position,);
}

func reduce_position_size_internal{
    range_check_ptr,
    pedersen_ptr: HashBuiltin*,
    funding_info: FundingInfo*,
    global_config: GlobalConfig*,
}(
    position: PerpPosition, reduction_size: felt, price: felt, fee_taken: felt, funding_idx: felt
) -> (position: PerpPosition) {
    alloc_locals;

    let (collateral_decimals) = token_decimals(global_config.collateral_token);

    let (synthetic_decimals: felt) = token_decimals(position.position_header.synthetic_token);
    let (synthetic_price_decimals: felt) = price_decimals(position.position_header.synthetic_token);

    let new_size = position.position_size - reduction_size;

    tempvar decimal_conversion = synthetic_decimals + synthetic_price_decimals -
        collateral_decimals;
    let (multiplier: felt) = pow(10, decimal_conversion);

    // ? Get realized pnl
    let (p1: felt, _) = unsigned_div_rem(reduction_size * price, multiplier);
    let (p2: felt, _) = unsigned_div_rem(reduction_size * position.entry_price, multiplier);
    let realized_pnl = p2 - p1 - 2 * position.order_side * (p2 - p1);

    // & apply funding
    let (margin_after_funding) = apply_funding(position, funding_idx);

    let updated_margin = margin_after_funding + realized_pnl - fee_taken;

    let (bankruptcy_price: felt) = _get_bankruptcy_price(
        position.entry_price,
        updated_margin,
        new_size,
        position.order_side,
        position.position_header.synthetic_token,
    );
    let (liquidation_price: felt) = _get_liquidation_price(
        position.entry_price,
        new_size,
        updated_margin,
        position.order_side,
        position.position_header.synthetic_token,
        position.position_header.allow_partial_liquidations,
    );

    let (new_position_hash: felt) = _hash_position_internal(
        position.position_header.hash,
        position.order_side,
        new_size,
        position.entry_price,
        liquidation_price,
        funding_idx,
    );

    let new_position = PerpPosition(
        position.position_header,
        position.order_side,
        new_size,
        updated_margin,
        position.entry_price,
        liquidation_price,
        bankruptcy_price,
        funding_idx,
        position.index,
        new_position_hash,
    );

    return (new_position,);
}

func flip_position_side_internal{
    range_check_ptr,
    pedersen_ptr: HashBuiltin*,
    funding_info: FundingInfo*,
    global_config: GlobalConfig*,
}(
    position: PerpPosition, reduction_size: felt, price: felt, fee_taken: felt, funding_idx: felt
) -> (position: PerpPosition) {
    alloc_locals;

    let (collateral_decimals) = token_decimals(global_config.collateral_token);

    let (synthetic_decimals: felt) = token_decimals(position.position_header.synthetic_token);
    let (synthetic_price_decimals: felt) = price_decimals(position.position_header.synthetic_token);

    let new_size = reduction_size - position.position_size;

    tempvar decimal_conversion = synthetic_decimals + synthetic_price_decimals -
        collateral_decimals;
    let (multiplier: felt) = pow(10, decimal_conversion);

    // ? Get realized pnl
    let (p1: felt, _) = unsigned_div_rem(position.position_size * price, multiplier);
    let (p2: felt, _) = unsigned_div_rem(position.position_size * position.entry_price, multiplier);
    let realized_pnl = p2 - p1 - 2 * position.order_side * (p2 - p1);

    // & apply funding
    let (margin_after_funding) = apply_funding(position, funding_idx);

    let updated_margin = margin_after_funding + realized_pnl - fee_taken;

    let new_order_side = is_not_zero(1 - position.order_side);

    let (bankruptcy_price: felt) = _get_bankruptcy_price(
        price, updated_margin, new_size, new_order_side, position.position_header.synthetic_token
    );
    let (liquidation_price: felt) = _get_liquidation_price(
        price,
        new_size,
        updated_margin,
        new_order_side,
        position.position_header.synthetic_token,
        position.position_header.allow_partial_liquidations,
    );

    let (new_position_hash: felt) = _hash_position_internal(
        position.position_header.hash,
        new_order_side,
        new_size,
        price,
        liquidation_price,
        funding_idx,
    );

    let new_position = PerpPosition(
        position.position_header,
        new_order_side,
        new_size,
        updated_margin,
        price,
        liquidation_price,
        bankruptcy_price,
        funding_idx,
        position.index,
        new_position_hash,
    );

    return (new_position,);
}

func close_position_partialy_internal{
    range_check_ptr,
    pedersen_ptr: HashBuiltin*,
    funding_info: FundingInfo*,
    global_config: GlobalConfig*,
}(
    position: PerpPosition,
    reduction_size: felt,
    close_price: felt,
    fee_taken: felt,
    funding_idx: felt,
) -> (position: PerpPosition, return_collateral: felt) {
    alloc_locals;

    let (collateral_decimals) = token_decimals(global_config.collateral_token);

    let (synthetic_decimals: felt) = token_decimals(position.position_header.synthetic_token);
    let (synthetic_price_decimals: felt) = price_decimals(position.position_header.synthetic_token);

    let updated_size = position.position_size - reduction_size;

    // & apply funding
    let (margin_after_funding) = apply_funding(position, funding_idx);

    let (reduction_margin: felt, _) = unsigned_div_rem(
        reduction_size * margin_after_funding, position.position_size
    );

    tempvar decimal_conversion = synthetic_decimals + synthetic_price_decimals -
        collateral_decimals;
    let (multiplier: felt) = pow(10, decimal_conversion);

    // ? Get realized pnl
    let (p1: felt, _) = unsigned_div_rem(reduction_size * close_price, multiplier);
    let (p2: felt, _) = unsigned_div_rem(reduction_size * position.entry_price, multiplier);
    let realized_pnl = p2 - p1 - 2 * position.order_side * (p2 - p1);

    let return_collateral = reduction_margin + realized_pnl - fee_taken;

    assert_le(0, return_collateral);

    let margin = margin_after_funding - reduction_margin;

    let (new_position_hash: felt) = _hash_position_internal(
        position.position_header.hash,
        position.order_side,
        updated_size,
        position.entry_price,
        position.liquidation_price,
        funding_idx,
    );

    let updated_position = PerpPosition(
        position.position_header,
        position.order_side,
        updated_size,
        margin,
        position.entry_price,
        position.liquidation_price,
        position.bankruptcy_price,
        funding_idx,
        position.index,
        new_position_hash,
    );

    return (updated_position, return_collateral);
}

func close_position_internal{
    range_check_ptr, funding_info: FundingInfo*, global_config: GlobalConfig*
}(position: PerpPosition, close_price: felt, fee_taken: felt, funding_idx: felt) -> (
    collateral_returned: felt
) {
    alloc_locals;

    let (collateral_decimals) = token_decimals(global_config.collateral_token);

    let (synthetic_decimals: felt) = token_decimals(position.position_header.synthetic_token);
    let (synthetic_price_decimals: felt) = price_decimals(position.position_header.synthetic_token);

    tempvar decimal_conversion = synthetic_decimals + synthetic_price_decimals -
        collateral_decimals;
    let (multiplier: felt) = pow(10, decimal_conversion);

    // & apply funding
    let (margin_after_funding) = apply_funding(position, funding_idx);

    let (p1: felt, _) = unsigned_div_rem(position.position_size * close_price, multiplier);
    let (p2: felt, _) = unsigned_div_rem(position.position_size * position.entry_price, multiplier);
    let realized_pnl = p2 - p1 - 2 * position.order_side * (p2 - p1) - fee_taken;

    return (margin_after_funding + realized_pnl,);
}

// * ====================================================================================

func is_position_liquidatable{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    funding_info: FundingInfo*,
    global_config: GlobalConfig*,
}(position: PerpPosition, market_price: felt, index_price: felt) -> (
    position: PerpPosition, leftover_value: felt
) {
    alloc_locals;

    // & if market_price is greater than the bankruptcy price, the leftover collateral goes to the insurance fund
    let (index_above_liq_price) = is_le(position.liquidation_price, index_price + 1);
    let (index_below_liq_price) = is_le(index_price, position.liquidation_price + 1);
    if (position.order_side == 1) {
        if (index_above_liq_price == 1) {
            return (position, 0);
        }
    }
    if (position.order_side == 0) {
        if (index_below_liq_price == 1) {
            return (position, 0);
        }
    }

    let min_liq_size = 1;  // TODO
    let (liq_cond) = is_le(position.position_size, min_liq_size + 1);
    if (position.is_position_liquidatable == 1) {
        if (liq_cond == 0) {
            return (position.position_size);
        }

        let (collateral_decimals) = token_decimals(global_config.collateral_token);

        let (synthetic_decimals: felt) = token_decimals(position.position_header.synthetic_token);
        let (synthetic_price_decimals: felt) = price_decimals(
            position.position_header.synthetic_token
        );

        tempvar decimal_conversion = synthetic_decimals + synthetic_price_decimals -
            collateral_decimals;
        let (multiplier: felt) = pow(10, decimal_conversion);

        let price_delta = market_price - position.entry_price + 2 * position.order_side *
            position.entry_price - 2 * position.order_side * market_price;

        let im_rate = 67;  // 6.7 %
        let liquidator_fee_rate = 5;  // 0.5 %

        let s1 = position.margin * multiplier;
        let s2 = position.position_size * price_delta;

        let new_size = unsigned_div_rem(s1 - s2, market_price * (im_rate + liquidator_fee_rate)) /
            1000;

        let liquidatable_size = position.position_size - new_size;

        return (liquidatable_size,);
    } else {
        return (position.position_size,);
    }
}

// -----------------------------------------------------------------------

// Todo: Liquidate position  (use validate_price_in_range)
func liquidate_position_partialy_internal{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    funding_info: FundingInfo*,
    global_config: GlobalConfig*,
}(position: PerpPosition, liquidation_size: felt, close_price: felt, funding_idx: felt) -> (
    position: PerpPosition, leftover_value: felt
) {
    alloc_locals;

    let (collateral_decimals) = token_decimals(global_config.collateral_token);

    let (synthetic_decimals: felt) = token_decimals(position.position_header.synthetic_token);
    let (synthetic_price_decimals: felt) = price_decimals(position.position_header.synthetic_token);

    tempvar decimal_conversion = synthetic_decimals + synthetic_price_decimals -
        collateral_decimals;
    let (multiplier: felt) = pow(10, decimal_conversion);

    let updated_size = position.position_size - liquidation_size;

    // & apply funding
    let (margin_after_funding) = apply_funding(position, funding_idx);

    let (reduction_margin: felt, _) = unsigned_div_rem(
        liquidation_size * margin_after_funding, position.position_size
    );

    let (p1: felt, _) = unsigned_div_rem(liquidation_size * close_price, multiplier);
    let (p2: felt, _) = unsigned_div_rem(liquidation_size * position.bankruptcy_price, multiplier);
    let leftover_value = p2 - p1 - 2 * position.order_side * (p2 - p1);

    // ? if this is less than zero it should come out of the insurance fund else add it to insurance fund

    let margin = margin_after_funding - reduction_margin;

    let (new_position_hash: felt) = _hash_position_internal(
        position.position_header.hash,
        position.order_side,
        updated_size,
        position.entry_price,
        position.liquidation_price,
        funding_idx,
    );

    let updated_position = PerpPosition(
        position.position_header,
        position.order_side,
        updated_size,
        margin,
        position.entry_price,
        position.liquidation_price,
        position.bankruptcy_price,
        funding_idx,
        position.index,
        new_position_hash,
    );

    return (updated_position, leftover_value);
}

func liquidate_position_internal{
    range_check_ptr, funding_info: FundingInfo*, global_config: GlobalConfig*
}(position: PerpPosition, close_price: felt, funding_idx: felt) -> (leftover_value: felt) {
    alloc_locals;

    let (collateral_decimals) = token_decimals(global_config.collateral_token);

    let (synthetic_decimals: felt) = token_decimals(position.position_header.synthetic_token);
    let (synthetic_price_decimals: felt) = price_decimals(position.position_header.synthetic_token);

    tempvar decimal_conversion = synthetic_decimals + synthetic_price_decimals -
        collateral_decimals;
    let (multiplier: felt) = pow(10, decimal_conversion);

    let (p1: felt, _) = unsigned_div_rem(position.position_size * close_price, multiplier);
    let (p2: felt, _) = unsigned_div_rem(
        position.position_size * position.bankruptcy_price, multiplier
    );
    let leftover_value = p2 - p1 - 2 * position.order_side * (p2 - p1);

    // ? if this is less than zero it should come out of the insurance fund else add it to insurance fund

    return (leftover_value,);
}

// -----------------------------------------------------------------------

func modify_margin{range_check_ptr, pedersen_ptr: HashBuiltin*, global_config: GlobalConfig*}(
    position: PerpPosition, margin_change: felt
) -> (position: PerpPosition) {
    alloc_locals;

    // Todo: Maybe have a constant fee here (like 5 cents or something)

    let margin = position.margin + margin_change;

    assert_le(1, margin);

    let (bankruptcy_price: felt) = _get_bankruptcy_price(
        position.entry_price,
        margin,
        position.position_size,
        position.order_side,
        position.position_header.synthetic_token,
    );

    let (liquidation_price: felt) = _get_liquidation_price(
        position.entry_price,
        position.position_size,
        margin,
        position.order_side,
        position.position_header.synthetic_token,
        position.position_header.allow_partial_liquidations,
    );

    let (new_position_hash: felt) = _hash_position_internal(
        position.position_header.hash,
        position.order_side,
        position.position_size,
        position.entry_price,
        liquidation_price,
        position.last_funding_idx,
    );

    let new_position = PerpPosition(
        position.position_header,
        position.order_side,
        position.position_size,
        margin,
        position.entry_price,
        liquidation_price,
        bankruptcy_price,
        position.last_funding_idx,
        position.index,
        new_position_hash,
    );

    return (new_position,);
}
