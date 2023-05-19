use std::{collections::HashMap, sync::Arc, thread::ThreadId};

use error_stack::Result;
use num_bigint::BigUint;
use parking_lot::Mutex;

use crate::{
    perpetual::DUST_AMOUNT_PER_ASSET,
    trees::superficial_tree::SuperficialTree,
    utils::{
        errors::{send_swap_error, SwapThreadExecutionError},
        notes::Note,
    },
};

use crate::utils::crypto_utils::Signature;

use super::{
    limit_order::LimitOrder,
    transaction_helpers::{
        rollbacks::RollbackInfo,
        state_updates::{update_state_after_swap_first_fill, update_state_after_swap_later_fills},
        swap_helpers::{
            block_until_prev_fill_finished, check_note_sums, check_prev_fill_consistencies,
            construct_new_swap_note, refund_partial_fill,
        },
    },
};

// * UPDATE STATE FUNCTION * ========================================================
pub fn execute_order(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    partial_fill_tracker_m: &Arc<Mutex<HashMap<u64, (Note, u64)>>>,
    blocked_order_ids_m: &Arc<Mutex<HashMap<u64, bool>>>,
    order: &LimitOrder,
    signature: &Signature,
    spent_amount_x: u64,
    spent_amount_y: u64,
    fee_taken_x: u64,
) -> Result<(bool, Note, Option<(Note, u64)>, Option<Note>, u64), SwapThreadExecutionError> {
    let partial_fill_info = block_until_prev_fill_finished(
        partial_fill_tracker_m,
        blocked_order_ids_m,
        order.order_id,
    )?;

    let is_first_fill = partial_fill_info.is_none();

    // ? This proves the transaction is valid and the state can be updated
    check_order_validity(
        tree_m,
        &partial_fill_info,
        order,
        is_first_fill,
        spent_amount_x,
        signature,
    )?;

    // ? This generates all the notes for the update
    let (
        is_partialy_filled,
        swap_note,
        new_partial_fill_info,
        prev_partial_fill_note,
        new_amount_filled,
    ) = execute_order_modifications(
        tree_m,
        &partial_fill_info,
        is_first_fill,
        order,
        spent_amount_x,
        spent_amount_y,
        fee_taken_x,
    );

    return Ok((
        is_partialy_filled,
        swap_note,
        new_partial_fill_info,
        prev_partial_fill_note,
        new_amount_filled,
    ));
}

fn execute_order_modifications(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    partial_fill_info: &Option<(Note, u64)>,
    is_first_fill: bool,
    order: &LimitOrder,
    spent_amount_x: u64,
    spent_amount_y: u64,
    fee_taken_x: u64,
) -> (bool, Note, Option<(Note, u64)>, Option<Note>, u64) {
    // ? Generate new swap notes ============================
    let swap_note: Note = construct_new_swap_note(
        partial_fill_info,
        tree_m,
        is_first_fill,
        order,
        spent_amount_y,
        fee_taken_x,
    );

    // ? Update previous and new partial fills ==========================
    let prev_amount_filled = if is_first_fill {
        0
    } else {
        partial_fill_info.as_ref().unwrap().1
    };
    let new_amount_filled = prev_amount_filled + spent_amount_y;

    let spend_amount_left = if is_first_fill {
        order.amount_spent
    } else {
        partial_fill_info.as_ref().unwrap().0.amount
    };

    let prev_partial_fill_refund_note: Option<Note>;
    let new_partial_refund_note: Option<Note>;

    let is_partially_filled =
        spend_amount_left - spent_amount_x >= DUST_AMOUNT_PER_ASSET[&order.token_spent.to_string()];
    if is_partially_filled {
        //? Order A was partially filled, we must refund the rest

        let partial_refund_idx: u64;
        if order.notes_in.len() > 2 && is_first_fill {
            partial_refund_idx = order.notes_in[2].index
        } else {
            let mut tree = tree_m.lock();
            partial_refund_idx = tree.first_zero_idx();
            drop(tree);
        };

        let new_partial_refund_note_ = refund_partial_fill(
            spend_amount_left,
            &order,
            spent_amount_x,
            partial_refund_idx,
        );
        prev_partial_fill_refund_note = if partial_fill_info.is_some() {
            Some(partial_fill_info.as_ref().unwrap().0.clone())
        } else {
            None
        };
        new_partial_refund_note = Some(new_partial_refund_note_);
    } else {
        prev_partial_fill_refund_note = if partial_fill_info.is_some() {
            Some(partial_fill_info.as_ref().unwrap().0.clone())
        } else {
            None
        };
        new_partial_refund_note = None;
    }

    let new_pratial_fill_info = if is_partially_filled {
        Some((new_partial_refund_note.unwrap(), new_amount_filled))
    } else {
        None
    };

    return (
        is_partially_filled,
        swap_note,
        new_pratial_fill_info,
        prev_partial_fill_refund_note,
        new_amount_filled,
    );
}

fn check_order_validity(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    partial_fill_info: &Option<(Note, u64)>,
    // partial_fill_tracker_m: &Arc<Mutex<HashMap<u64, (Note, u64)>>>,
    order: &LimitOrder,
    is_first_fill: bool,
    spent_amount: u64,
    signature: &Signature,
) -> Result<(), SwapThreadExecutionError> {
    //

    // ? Verify that the order were signed correctly
    order.verify_order_signature(signature)?;

    // ? Check the sum of notes in matches refund and output amounts
    if is_first_fill {
        // ? if this is the first fill
        check_note_sums(&order)?;

        if let Some(rf_note) = &order.refund_note {
            if order.notes_in[0].index != rf_note.index {
                return Err(send_swap_error(
                    "refund note index is not the same as the first note index".to_string(),
                    Some(order.order_id),
                    None,
                ));
            }
        }
    } else {
        // ? if order was partially filled befor
        check_prev_fill_consistencies(partial_fill_info, &order, spent_amount)?;
    }

    // ? Verify the notes exist in the state
    let tree = tree_m.lock();
    if is_first_fill {
        for note in order.notes_in.iter() {
            let leaf_hash = tree.get_leaf_by_index(note.index);

            if leaf_hash != note.hash {
                return Err(send_swap_error(
                    "note spent for swap does not exist in the state".to_string(),
                    Some(order.order_id),
                    Some(format!(
                        "note spent for swap does not exist in the state: hash={:?}",
                        note.hash,
                    )),
                ));
            }
        }
    } else {
        let pfr_note = &partial_fill_info.as_ref().unwrap().0;
        let leaf_hash = tree.get_leaf_by_index(pfr_note.index);
        if leaf_hash != pfr_note.hash {
            return Err(send_swap_error(
                "prev partial refund note used in swap does not exist in the state".to_string(),
                Some(order.order_id),
                Some(format!(
                    "prev partial refund note used in swap does not exist in the state: hash={:?}",
                    pfr_note.hash,
                )),
            ));
        }
    }
    drop(tree);

    return Ok(());
}

pub fn update_state_after_order(
    tree: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes: &Arc<Mutex<HashMap<u64, BigUint>>>,
    rollback_safeguard: &Arc<Mutex<HashMap<ThreadId, RollbackInfo>>>,
    thread_id: ThreadId,
    is_first_fill: bool,
    order_id: u64,
    notes_in: &Vec<Note>,
    refund_note: &Option<Note>,
    swap_note: &Note,
    new_partial_fill_info: &Option<(Note, u64)>,
    prev_partial_refund_note: &Option<Note>,
) -> Result<(), SwapThreadExecutionError> {
    let mut new_partial_refund_note: Option<Note> = None;
    if let Some(new_pfr_note) = new_partial_fill_info.as_ref() {
        new_partial_refund_note = Some(new_pfr_note.0.clone());
    }

    // ? Update the state for order a
    if is_first_fill {
        update_state_after_swap_first_fill(
            tree,
            updated_note_hashes,
            rollback_safeguard,
            thread_id,
            order_id,
            notes_in,
            refund_note,
            &swap_note,
            &new_partial_refund_note.as_ref(),
        )?;
    } else {
        update_state_after_swap_later_fills(
            tree,
            updated_note_hashes,
            rollback_safeguard,
            thread_id,
            order_id,
            prev_partial_refund_note.as_ref().unwrap(),
            swap_note,
            &new_partial_refund_note.as_ref(),
        )?;
    }

    Ok(())
}
