// * ========================================================================================

use parking_lot::Mutex;
use std::{collections::HashMap, sync::Arc, thread::sleep, time::Duration};

use crate::{
    order_tab::OrderTab,
    perpetual::{ASSETS, DECIMALS_PER_ASSET, DUST_AMOUNT_PER_ASSET},
    utils::{
        errors::{send_swap_error, SwapThreadExecutionError},
        notes::Note,
    },
};

use super::{super::limit_order::LimitOrder, helpers::non_tab_helpers::non_tab_consistency_checks};

use error_stack::Result;

// * ========================================================================================

/// This checks if another swap is already in progress for the same order. \
/// If so, it waits for the other swap to finish and rejects it, if it takes too long.
///
/// ## Returns:
/// * partial_fill_info - the partial fill info (if it's not the first fill)
///
pub fn block_until_prev_fill_finished(
    partial_fill_tracker_m: &Arc<Mutex<HashMap<u64, (Option<Note>, u64)>>>,
    blocked_order_ids_m: &Arc<Mutex<HashMap<u64, bool>>>,
    order_id: u64,
) -> Result<Option<(Option<Note>, u64)>, SwapThreadExecutionError> {
    let blocked_order_ids = blocked_order_ids_m.lock();
    let mut is_blocked = blocked_order_ids.get(&order_id).unwrap_or(&false).clone();
    drop(blocked_order_ids);

    let mut count: u8 = 0;
    while is_blocked {
        if count >= 12 {
            return Err(send_swap_error(
                "previous fill is taking too long".to_string(),
                Some(order_id),
                None,
            ));
        }

        sleep(Duration::from_millis(5));
        let blocked_order_ids = blocked_order_ids_m.lock();
        is_blocked = blocked_order_ids.get(&order_id).unwrap_or(&false).clone();
        drop(blocked_order_ids);

        count += 1;
    }

    let mut blocked_order_ids = blocked_order_ids_m.lock();
    blocked_order_ids.insert(order_id, true);
    drop(blocked_order_ids);

    // ?  Get the partial fill info for this order if it exists (if later fills)
    let mut partial_fill_tracker = partial_fill_tracker_m.lock();
    let partial_fill_info = partial_fill_tracker.remove(&order_id);
    drop(partial_fill_tracker);

    return Ok(partial_fill_info);
}

/// This finalizes the updates by inserting the new partial fill info back into the tracker \
/// and allows the next swap filling the same order to continue executing
///
pub fn finalize_updates(
    partial_fill_tracker_m: &Arc<Mutex<HashMap<u64, (Option<Note>, u64)>>>,
    blocked_order_ids_m: &Arc<Mutex<HashMap<u64, bool>>>,
    order_id: u64,
    is_tab_order: bool,
    tx_execution_output: &TxExecutionThreadOutput,
) {
    let new_partial_fill_info;
    if is_tab_order {
        if tx_execution_output.is_partially_filled {
            new_partial_fill_info = Some((None, tx_execution_output.new_amount_filled))
        } else {
            new_partial_fill_info = None
        }
    } else {
        new_partial_fill_info = tx_execution_output
            .note_info_output
            .as_ref()
            .unwrap()
            .new_partial_fill_info
            .clone()
    }

    // ?  insert the partial fill info back into the tracker
    let mut partial_fill_tracker = partial_fill_tracker_m.lock();
    if new_partial_fill_info.is_some() {
        partial_fill_tracker.insert(order_id, new_partial_fill_info.unwrap());
    }
    drop(partial_fill_tracker);

    // ? allow other threads with this order id to continue
    let mut blocked_order_ids = blocked_order_ids_m.lock();
    blocked_order_ids.remove(&order_id);
    drop(blocked_order_ids);
}

pub fn unblock_order(
    blocked_order_ids_m: &Arc<Mutex<HashMap<u64, bool>>>,
    order_id_a: u64,
    order_id_b: u64,
) {
    let mut blocked_order_ids = blocked_order_ids_m.lock();
    blocked_order_ids.remove(&order_id_a);
    blocked_order_ids.remove(&order_id_b);
    drop(blocked_order_ids);
}

// * ================================================================================================

/// ## Checks:
/// * Checks that the order ids are set and different
/// * Checks that the tokens are valid
/// * Checks that the order amounts are valid
/// * Checks that the tokens swapped match
/// * Checks for over spending
/// * Checks that the fees are not to large
/// * Checks that the amounts swapped are consistent with the order amounts
/// * Checks that the notes spent are all unique
pub fn consistency_checks(
    order_a: &LimitOrder,
    order_b: &LimitOrder,
    spent_amount_a: u64,
    spent_amount_b: u64,
    fee_taken_a: u64,
    fee_taken_b: u64,
) -> Result<(), SwapThreadExecutionError> {
    // ? Check that the order contain either the spot_note_info or the order_tab
    let p_a = order_a.spot_note_info.is_some();
    let q_a = order_a.order_tab.is_some();
    let res_a = (p_a || q_a) && !(p_a && q_a);

    if !res_a {
        return Err(send_swap_error(
            "order can only have spot_note_info or order_tab defined, not both.".to_string(),
            Some(order_a.order_id),
            None,
        ));
    }

    let p_b: bool = order_b.spot_note_info.is_some();
    let q_b = order_b.order_tab.is_some();
    let res_b = (p_b || q_b) && !(p_b && q_b);
    if !res_b {
        return Err(send_swap_error(
            "order can only have spot_note_info or order_tab defined, not both.".to_string(),
            Some(order_b.order_id),
            None,
        ));
    }

    non_tab_consistency_checks(order_a, order_b)?;

    if order_a.order_id == 0 || order_b.order_id == 0 {
        return Err(send_swap_error(
            "order_id should not be 0".to_string(),
            None,
            None,
        ));
    }

    // ? Check that the tokens are valid
    if !ASSETS.contains(&order_a.token_spent) {
        return Err(send_swap_error(
            "tokens swapped are invalid".to_string(),
            Some(order_a.order_id),
            None,
        ));
    } else if !ASSETS.contains(&order_a.token_received) {
        return Err(send_swap_error(
            "tokens swapped are invalid".to_string(),
            Some(order_b.order_id),
            None,
        ));
    }

    // ? Check that the tokens swapped match
    if order_a.token_spent != order_b.token_received
        || order_a.token_received != order_b.token_spent
    {
        return Err(send_swap_error(
            "Tokens swapped do not match".to_string(),
            None,
            Some(format!(
                "tokens mismatch: \n{:?} != {:?}  or \n{:?} != {:?}",
                order_a.token_spent,
                order_b.token_received,
                order_a.token_received,
                order_b.token_spent
            )),
        ));
    }

    // ? Check that the amounts swapped don't exceed the order amounts
    let dust_amount_a: u64 = DUST_AMOUNT_PER_ASSET[&order_a.token_spent.to_string()];
    let dust_amount_b: u64 = DUST_AMOUNT_PER_ASSET[&order_b.token_spent.to_string()];
    if order_a.amount_spent < spent_amount_a - dust_amount_a
        || order_b.amount_spent < spent_amount_b - dust_amount_b
    {
        return Err(send_swap_error(
            "Amounts swapped exceed order amounts".to_string(),
            None,
            Some(format!(
                "overspending: \n{:?} < {:?}  or \n{:?} < {:?}",
                order_a.amount_spent, spent_amount_a, order_b.amount_spent, spent_amount_b
            )),
        ));
    }

    // ? Check that the fees taken dont exceed the order fees
    if fee_taken_a as u128 * order_a.amount_received as u128
        > order_a.fee_limit as u128 * spent_amount_b as u128
        || fee_taken_b as u128 * order_b.amount_received as u128
            > order_b.fee_limit as u128 * spent_amount_a as u128
    {
        return Err(send_swap_error(
            "Fees taken exceed order fees".to_string(),
            None,
            None,
        ));
    }

    // ? Verify consistency of amounts swapped
    // ? Check the price is consistent to 0.01% (1/10000)
    let a1: u128 = spent_amount_a as u128 * order_a.amount_received as u128 * 10000;
    let a2 = spent_amount_b as u128 * order_a.amount_spent as u128 * 10001;

    let b1 = spent_amount_b as u128 * order_b.amount_received as u128 * 10000;
    let b2 = spent_amount_a as u128 * order_b.amount_spent as u128 * 10001;

    if a1 > a2 || b1 > b2 {
        return Err(send_swap_error(
            "Amount swapped ratios are inconsistent".to_string(),
            None,
            None,
        ));
    }

    // ? Check that the order_ids are different
    if order_a.order_id == order_b.order_id {
        return Err(send_swap_error(
            "Order ids are the same".to_string(),
            None,
            Some(format!("order ids are the same: {:?}", order_a.order_id)),
        ));
    }

    // ? Check that the notes spent are all different for both orders (different indexes)
    let mut valid = true;
    let mut valid_a = true;
    let mut valid_b = true;
    let mut spent_indexes: Vec<u64> = Vec::new();

    if let Some(note_info) = &order_a.spot_note_info {
        note_info.notes_in.iter().for_each(|note| {
            if spent_indexes.contains(&note.index) {
                valid_a = false;
            }
            spent_indexes.push(note.index);
        });
    }
    if let Some(note_info) = &order_b.spot_note_info {
        let mut spent_indexes_b = spent_indexes.clone();
        note_info.notes_in.iter().for_each(|note| {
            if spent_indexes_b.contains(&note.index) {
                valid_b = false;
            }

            if spent_indexes.contains(&note.index) {
                valid = false;
            }
            spent_indexes.push(note.index);
            spent_indexes_b.push(note.index);
        });
    }

    if !valid || !valid_a || !valid_b {
        let invalid_order_id = if !valid_a {
            Some(order_a.order_id)
        } else if !valid_b {
            Some(order_b.order_id)
        } else {
            None
        };

        return Err(send_swap_error(
            "note indexes are not unique".to_string(),
            invalid_order_id,
            None,
        ));
    }

    // ? Check that the order tabs are different if they are not None
    if order_a.order_tab.is_some() && order_b.order_tab.is_some() {
        let tab_a = order_a.order_tab.as_ref().unwrap().lock();
        let order_hash_a = tab_a.hash.clone();
        drop(tab_a);
        let tab_b = order_b.order_tab.as_ref().unwrap().lock();
        let order_hash_b = tab_b.hash.clone();
        drop(tab_b);

        if order_hash_a == order_hash_b {
            return Err(send_swap_error(
                "order tabs are the same".to_string(),
                None,
                None,
            ));
        }
    }

    Ok(())
}

// * ================================================================================================
#[derive(Clone, Debug)]
pub struct TxExecutionThreadOutput {
    pub is_partially_filled: bool,
    pub note_info_output: Option<NoteInfoExecutionOutput>,
    pub updated_order_tab: Option<OrderTab>,
    pub new_amount_filled: u64,
}

#[derive(Clone, Debug)]
pub struct NoteInfoExecutionOutput {
    pub swap_note: Note,
    pub new_partial_fill_info: Option<(Option<Note>, u64)>,
    pub prev_partial_fill_refund_note: Option<Note>,
}
