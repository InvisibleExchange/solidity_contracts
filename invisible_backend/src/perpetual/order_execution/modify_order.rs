use std::{collections::HashMap, sync::Arc};

use crate::{
    perpetual::{
        get_price,
        perp_helpers::perp_swap_helpers::{block_until_prev_fill_finished, get_max_leverage},
        perp_order::PerpOrder,
        perp_position::PerpPosition,
        DUST_AMOUNT_PER_ASSET,
    },
    transaction_batch::tx_batch_structs::SwapFundingInfo,
    trees::superficial_tree::SuperficialTree,
    utils::{
        errors::{send_perp_swap_error, PerpSwapExecutionError},
        notes::Note,
    },
};
use error_stack::Result;
use parking_lot::Mutex;

use crate::utils::crypto_utils::Signature;

pub fn execute_modify_order(
    swap_funding_info: &SwapFundingInfo,
    index_price: u64,
    fee_taken: u64,
    partialy_filled_positions_m: &Arc<Mutex<HashMap<String, (PerpPosition, u64)>>>,
    perpetual_partial_fill_tracker_m: &Arc<Mutex<HashMap<u64, (Option<Note>, u64, u64)>>>,
    blocked_perp_order_ids_m: &Arc<Mutex<HashMap<u64, bool>>>,
    order: &PerpOrder,
    signature: &Signature,
    spent_collateral: u64,
    spent_synthetic: u64,
) -> Result<
    (
        PerpPosition,
        PerpPosition,
        (Option<Note>, u64, u64),
        u64,
        u32,
        bool,
    ),
    PerpSwapExecutionError,
> {
    // ? In case of sequential partial fills block threads updating the same order id untill previous thread is finsihed and fetch the previous partial fill info
    let partial_fill_info = block_until_prev_fill_finished(
        perpetual_partial_fill_tracker_m,
        blocked_perp_order_ids_m,
        order.order_id,
    )?;

    // TODO: IS this necessary: If the order was partially filled and the server crashed than we reject the order
    // if partial_fill_info.is_some()
    //     && partial_fill_info.as_ref().unwrap().1 == 69
    //     && partial_fill_info.as_ref().unwrap().2 == 69
    // {
    //     return Err(send_perp_swap_error(
    //         "Order rejected".to_string(),
    //         Some(order.order_id),
    //         None,
    //     ));
    // }

    // ? Get the new total amount filled after this swap
    let new_amount_filled = if partial_fill_info.is_some() {
        partial_fill_info.as_ref().unwrap().1 + spent_synthetic
    } else {
        spent_synthetic
    };

    let is_fully_filled = new_amount_filled
        >= order.synthetic_amount - DUST_AMOUNT_PER_ASSET[&order.synthetic_token.to_string()];

    let (prev_position, position, new_spent_synthetic) = modify_position(
        partialy_filled_positions_m,
        index_price,
        swap_funding_info,
        order,
        signature,
        fee_taken,
        spent_collateral,
        spent_synthetic,
    )?;

    let prev_funding_idx = prev_position.last_funding_idx;

    let new_partial_fill_info: (Option<Note>, u64, u64) = (None, new_amount_filled, 0);

    return Ok((
        prev_position,
        position,
        new_partial_fill_info,
        new_spent_synthetic,
        prev_funding_idx,
        is_fully_filled,
    ));
}

// * ======================================================================================================
// * ======================================================================================================

fn modify_position(
    partialy_filled_positions_m: &Arc<Mutex<HashMap<String, (PerpPosition, u64)>>>,
    index_price: u64,
    swap_funding_info: &SwapFundingInfo,
    order: &PerpOrder,
    signature: &Signature,
    fee_taken: u64,
    spent_collateral: u64,
    spent_synthetic: u64,
) -> Result<(PerpPosition, PerpPosition, u64), PerpSwapExecutionError> {
    let mut position: PerpPosition;
    let prev_spent_synthetic: u64 = 0;

    if let Some(pos) = &order.position {
        let mut pf_positions = partialy_filled_positions_m.lock();
        let pf_pos = pf_positions.remove(&pos.position_address.to_string());

        if let Some(position_) = pf_pos {
            position = position_.0;
        } else {
            position = pos.clone();
        }
    } else {
        return Err(send_perp_swap_error(
            "Position not defined in modify order".to_string(),
            Some(order.order_id),
            None,
        ));
    }

    order.verify_order_signature(signature, Some(&position.position_address))?;

    let prev_position: PerpPosition = position.clone();

    // ? Check that order token matches synthetic token
    if prev_position.synthetic_token != order.synthetic_token {
        return Err(send_perp_swap_error(
            "Position and order should have same synthetic token".to_string(),
            Some(order.order_id),
            None,
        ));
    }

    let price: u64 = get_price(order.synthetic_token, spent_collateral, spent_synthetic);

    if position.order_side == order.order_side {
        let idx_diff = position.last_funding_idx - swap_funding_info.min_swap_funding_idx;

        let applicable_funding_rates = &swap_funding_info.swap_funding_rates[idx_diff as usize..];
        let applicable_funding_prices =
            &swap_funding_info.swap_funding_prices[position.last_funding_idx as usize..];

        // ? Apply funding to position
        position.apply_funding(
            applicable_funding_rates.to_vec(),
            applicable_funding_prices.to_vec(),
        );

        // & Increasing the position size
        position.increase_position_size(
            spent_synthetic,
            price,
            fee_taken,
            swap_funding_info.current_funding_idx,
        );

        let leverage = prev_position.get_current_leverage(index_price)?;

        // ? Check that leverage is valid relative to the notional position size after increasing size
        if get_max_leverage(order.synthetic_token, order.synthetic_amount) < leverage {
            return Err(send_perp_swap_error(
                "Leverage would be too high".to_string(),
                Some(order.order_id),
                None,
            ));
        }
    } else {
        let idx_diff = position.last_funding_idx - swap_funding_info.min_swap_funding_idx;

        let applicable_funding_rates = &swap_funding_info.swap_funding_rates[idx_diff as usize..];
        let applicable_funding_prices = &swap_funding_info.swap_funding_prices[idx_diff as usize..];

        // ? Apply funding to position
        position.apply_funding(
            applicable_funding_rates.to_vec(),
            applicable_funding_prices.to_vec(),
        );

        if spent_synthetic
            >= position.position_size - DUST_AMOUNT_PER_ASSET[&order.synthetic_token.to_string()]
        {
            // & Flipping the position side
            position.flip_position_side(
                spent_synthetic,
                price,
                fee_taken,
                swap_funding_info.current_funding_idx,
            );
        } else {
            // & Decreasing the position size
            position.reduce_position_size(
                spent_synthetic,
                price,
                fee_taken,
                swap_funding_info.current_funding_idx,
            );
        }
    }

    let new_spent_synthetic = spent_synthetic + prev_spent_synthetic;

    return Ok((prev_position, position, new_spent_synthetic));
}

// * ======================================================================================================

pub fn verify_position_existence(
    perpetual_state_tree__: &Arc<Mutex<SuperficialTree>>,
    partialy_filled_positions: &Arc<Mutex<HashMap<String, (PerpPosition, u64)>>>,
    position: &Option<PerpPosition>,
    order_id: u64,
) -> Result<(), PerpSwapExecutionError> {
    let perpetual_state_tree = perpetual_state_tree__.lock();

    let partialy_filled_positions_m = partialy_filled_positions.lock();
    if let Some((pos_, _)) =
        partialy_filled_positions_m.get(&position.as_ref().unwrap().position_address.to_string())
    {
        // ? Verify the position hash is valid and exists in the state
        if pos_.hash != pos_.hash_position()
            || perpetual_state_tree.get_leaf_by_index(pos_.index as u64) != pos_.hash
        {
            let pos = position.as_ref().unwrap();
            return verify_existance(&perpetual_state_tree, &pos, order_id);
        }
    } else {
        let pos = position.as_ref().unwrap();
        return verify_existance(&perpetual_state_tree, &pos, order_id);
    }

    Ok(())
}

fn verify_existance(
    state_tree: &SuperficialTree,
    position: &PerpPosition,
    order_id: u64,
) -> Result<(), PerpSwapExecutionError> {
    // ? Verify the position hash is valid and exists in the state
    if position.hash != position.hash_position() {
        return Err(send_perp_swap_error(
            "position hash not valid".to_string(),
            Some(order_id),
            None,
        ));
    }

    // ? Check that the position being updated exists in the state
    if state_tree.get_leaf_by_index(position.index as u64) != position.hash {
        return Err(send_perp_swap_error(
            "position does not exist in the state".to_string(),
            Some(order_id),
            None,
        ));
    }
    return Ok(());
}
