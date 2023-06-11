// * ========================================================================================

use num_bigint::BigUint;
use parking_lot::Mutex;
use std::{collections::HashMap, sync::Arc, thread::sleep, time::Duration};

use crate::{
    perpetual::{DECIMALS_PER_ASSET, DUST_AMOUNT_PER_ASSET, TOKENS, VALID_COLLATERAL_TOKENS},
    trees::superficial_tree::SuperficialTree,
    utils::{
        errors::{send_swap_error, SwapThreadExecutionError},
        notes::Note,
    },
};

use super::super::limit_order::LimitOrder;

use error_stack::Result;

// * ========================================================================================

/// This function constructs the new partial refund (pfr) note
///
/// # Arguments
/// spend_amount_left - the amount left to spend at the beginning of the swap
/// order - the order that is being filled
/// pub_key - the sum of input public keys for the order (used for partial fill refunds)
/// spent_amount_x - the amount of token x being spent in the swap
/// idx - the index where the new pfr note will be placed the tree
pub fn refund_partial_fill(
    spend_amount_left: u64,
    order: &LimitOrder,
    spent_amount_x: u64,
    idx: u64,
) -> Note {
    let new_partial_refund_amount = spend_amount_left - spent_amount_x;

    let new_partial_refund_note: Note = Note::new(
        idx,
        order.notes_in[0].address.clone(),
        order.token_spent,
        new_partial_refund_amount,
        order.notes_in[0].blinding.clone(),
    );

    return new_partial_refund_note;
}

/// Creates the swap note, which will be the result of the swap (received funds)
pub fn construct_new_swap_note(
    partial_fill_info: &Option<(Note, u64)>,
    tree_m: &Arc<Mutex<SuperficialTree>>,
    is_first_fill: bool,
    order: &LimitOrder,
    spent_amount_y: u64,
    fee_taken_x: u64,
) -> Note {
    let swap_note_a_idx: u64;
    if is_first_fill {
        if order.notes_in.len() > 1 {
            swap_note_a_idx = order.notes_in[1].index;
        } else {
            let mut tree = tree_m.lock();
            let zero_idx = tree.first_zero_idx();
            swap_note_a_idx = zero_idx;
            drop(tree);
        }
    } else {
        swap_note_a_idx = partial_fill_info.as_ref().unwrap().0.index;
    };

    return Note::new(
        swap_note_a_idx,
        order.dest_received_address.clone(),
        order.token_received,
        spent_amount_y - fee_taken_x,
        order.dest_received_blinding.clone(),
    );
}

// * ================================================================================================

/// This checks if another swap is already in progress for the same order. \
/// If so, it waits for the other swap to finish and rejects it, if it takes too long.
///
/// ## Returns:
/// * partial_fill_info - the partial fill info (if it's not the first fill)
///
pub fn block_until_prev_fill_finished(
    partial_fill_tracker_m: &Arc<Mutex<HashMap<u64, (Note, u64)>>>,
    blocked_order_ids_m: &Arc<Mutex<HashMap<u64, bool>>>,
    order_id: u64,
) -> Result<Option<(Note, u64)>, SwapThreadExecutionError> {
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
    partial_fill_tracker_m: &Arc<Mutex<HashMap<u64, (Note, u64)>>>,
    blocked_order_ids_m: &Arc<Mutex<HashMap<u64, bool>>>,
    order_id: u64,
    new_partial_fill_info: &Option<(Note, u64)>,
) {
    // ?  insert the partial fill info back into the tracker
    let mut partial_fill_tracker = partial_fill_tracker_m.lock();
    if new_partial_fill_info.is_some() {
        partial_fill_tracker.insert(order_id, new_partial_fill_info.as_ref().unwrap().clone());
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
// * CONSISTENCY CHECKS * //

/// checks if all the notes spent have the right token \
/// and that the sum of inputs is valid for the given swap and refund amounts
pub fn check_note_sums(order: &LimitOrder) -> Result<(), SwapThreadExecutionError> {
    let mut sum_notes: u64 = 0;
    for note in order.notes_in.iter() {
        if note.token != order.token_spent {
            return Err(send_swap_error(
                "note and order token missmatch".to_string(),
                Some(order.order_id),
                None,
            ));
        }

        sum_notes += note.amount
    }

    let refund_amount = if order.refund_note.is_some() {
        order.refund_note.as_ref().unwrap().amount
    } else {
        0
    };

    if sum_notes < refund_amount + order.amount_spent {
        return Err(send_swap_error(
            "sum of inputs is to small for this order".to_string(),
            Some(order.order_id),
            None,
        ));
    }

    Ok(())
}

/// checks if the partial fill info is consistent with the order \
pub fn check_prev_fill_consistencies(
    partial_fill_info: &Option<(Note, u64)>,
    order: &LimitOrder,
    spend_amount_x: u64,
) -> Result<(), SwapThreadExecutionError> {
    let partial_refund_note = &partial_fill_info.as_ref().unwrap().0;

    // ? Check that the partial refund note has the right token, amount, and address
    if partial_refund_note.token != order.token_spent {
        return Err(send_swap_error(
            "spending wrong token".to_string(),
            Some(order.order_id),
            None,
        ));
    }

    if partial_refund_note.amount < spend_amount_x {
        return Err(send_swap_error(
            "refund note amount is to small for this swap".to_string(),
            Some(order.order_id),
            None,
        ));
    }

    // ? Assumption: If you know the sum of private keys you know the individual private keys
    if partial_refund_note.address.x != order.notes_in[0].address.x {
        return Err(send_swap_error(
            "pfr note address invalid".to_string(),
            Some(order.order_id),
            None,
        ));
    }

    Ok(())
}

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
    if order_a.order_id == 0 || order_b.order_id == 0 {
        return Err(send_swap_error(
            "order_id should not be 0".to_string(),
            None,
            None,
        ));
    }

    // ? Check that the tokens are valid
    if !TOKENS.contains(&order_a.token_spent)
        && !VALID_COLLATERAL_TOKENS.contains(&order_a.token_spent)
    {
        return Err(send_swap_error(
            "tokens swapped are invalid".to_string(),
            Some(order_a.order_id),
            None,
        ));
    } else if !TOKENS.contains(&order_a.token_received)
        && !VALID_COLLATERAL_TOKENS.contains(&order_a.token_received)
    {
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

    let dec_sum: u8 = DECIMALS_PER_ASSET[order_a.token_spent.to_string().as_str()]
        + DECIMALS_PER_ASSET[order_b.token_spent.to_string().as_str()];
    // ? Verify consistency of amounts swapped

    // ? Check the price is consistent to 0.01% (1/10000)
    let multiplier = 10u128.pow(dec_sum as u32 - 4);
    let a1 = spent_amount_a as u128 * order_a.amount_received as u128;
    let a2 = spent_amount_b as u128 * order_a.amount_spent as u128;
    let b1 = spent_amount_b as u128 * order_b.amount_received as u128;
    let b2 = spent_amount_a as u128 * order_b.amount_spent as u128;

    if a1 / multiplier > a2 / multiplier || b1 / multiplier > b2 / multiplier {
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

    let mut spent_indexes_a: Vec<u64> = Vec::new();
    let mut hashes_a: HashMap<u64, BigUint> = HashMap::new();
    let _ = order_a.notes_in.iter().for_each(|note| {
        if spent_indexes_a.contains(&note.index) {
            valid_a = false;
        }
        spent_indexes_a.push(note.index);
        hashes_a.insert(note.index, note.hash.clone());
    });

    let mut spent_indexes_b: Vec<u64> = Vec::new();
    order_b.notes_in.iter().for_each(|note| {
        if spent_indexes_b.contains(&note.index) {
            valid_b = false;
        }
        spent_indexes_b.push(note.index);

        if spent_indexes_a.contains(&note.index) {
            if hashes_a.get(&note.index).unwrap() == &note.hash {
                valid = false;
            }
        }
    });

    if !valid_a || !valid_b || !valid {
        let invalid_order_id = if !valid_a {
            Some(order_a.order_id)
        } else if !valid_b {
            Some(order_b.order_id)
        } else {
            None
        };

        return Err(send_swap_error(
            "Notes spent are not unique".to_string(),
            invalid_order_id,
            None,
        ));
    }

    Ok(())
}

// * ================================================================================================
#[derive(Clone, Debug)]
pub struct TxExecutionThreadOutput {
    pub is_partially_filled: bool,
    pub swap_note: Note,
    pub new_partial_fill_info: Option<(Note, u64)>,
    pub prev_partial_fill_refund_note: Option<Note>,
    pub new_amount_filled: u64,
}
