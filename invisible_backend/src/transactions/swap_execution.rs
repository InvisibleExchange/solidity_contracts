use std::{collections::HashMap, sync::Arc, thread::ThreadId};

use error_stack::Result;
use num_bigint::BigUint;
use parking_lot::Mutex;

use crate::{
    order_tab::OrderTab,
    trees::superficial_tree::SuperficialTree,
    utils::{errors::SwapThreadExecutionError, notes::Note},
};

use crate::utils::crypto_utils::Signature;

use super::{
    limit_order::{LimitOrder, SpotNotesInfo},
    transaction_helpers::{
        helpers::{
            non_tab_orders::{
                check_non_tab_order_validity, execute_non_tab_order_modifications,
                update_state_after_non_tab_order,
            },
            tab_orders::{
                check_tab_order_validity, execute_tab_order_modifications,
                update_state_after_tab_order,
            },
        },
        rollbacks::RollbackInfo,
        swap_helpers::{block_until_prev_fill_finished, NoteInfoExecutionOutput},
    },
};

// * UPDATE STATE FUNCTION * ========================================================
pub fn execute_order(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    tabs_state_tree: &Arc<Mutex<SuperficialTree>>,
    partial_fill_tracker_m: &Arc<Mutex<HashMap<u64, (Option<Note>, u64)>>>,
    blocked_order_ids_m: &Arc<Mutex<HashMap<u64, bool>>>,
    order: &LimitOrder,
    signature: &Signature,
    spent_amount_x: u64,
    spent_amount_y: u64,
    fee_taken_x: u64,
) -> Result<(bool, Option<NoteInfoExecutionOutput>, Option<OrderTab>, u64), SwapThreadExecutionError>
{
    let partial_fill_info = block_until_prev_fill_finished(
        partial_fill_tracker_m,
        blocked_order_ids_m,
        order.order_id,
    )?;

    let is_first_fill = partial_fill_info.is_none();

    // ? This proves the transaction is valid and the state can be updated
    check_order_validity(
        tree_m,
        tabs_state_tree,
        &partial_fill_info,
        order,
        is_first_fill,
        spent_amount_x,
        signature,
    )?;

    // ? This generates all the notes for the update
    let (is_partialy_filled, note_info_output, updated_order_tab, new_amount_filled) =
        execute_order_modifications(
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
        note_info_output,
        updated_order_tab,
        new_amount_filled,
    ));
}

fn execute_order_modifications(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    partial_fill_info: &Option<(Option<Note>, u64)>,
    is_first_fill: bool,
    order: &LimitOrder,
    spent_amount_x: u64,
    spent_amount_y: u64,
    fee_taken_x: u64,
) -> (bool, Option<NoteInfoExecutionOutput>, Option<OrderTab>, u64) {
    if order.spot_note_info.is_some() {
        let (
            is_partialy_filled,
            swap_note,
            new_partial_fill_info,
            prev_partial_fill_refund_note,
            new_amount_filled,
        ) = execute_non_tab_order_modifications(
            tree_m,
            partial_fill_info,
            is_first_fill,
            order,
            spent_amount_x,
            spent_amount_y,
            fee_taken_x,
        );

        let note_info_output = NoteInfoExecutionOutput {
            new_partial_fill_info,
            prev_partial_fill_refund_note,
            swap_note,
        };

        return (
            is_partialy_filled,
            Some(note_info_output),
            None,
            new_amount_filled,
        );
    } else {
        let tab_lock = order.order_tab.as_ref().unwrap().lock();
        let order_tab = tab_lock.clone();
        drop(tab_lock);

        let prev_filled_amount = if partial_fill_info.is_some() {
            partial_fill_info.as_ref().unwrap().1
        } else {
            0
        };

        let (is_partially_filled, updated_order_tab, new_amount_filled) =
            execute_tab_order_modifications(
                prev_filled_amount,
                order,
                order_tab,
                spent_amount_x,
                spent_amount_y,
                fee_taken_x,
            );

        return (
            is_partially_filled,
            None,
            Some(updated_order_tab),
            new_amount_filled,
        );
    }
}

fn check_order_validity(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    tabs_state_tree: &Arc<Mutex<SuperficialTree>>,
    partial_fill_info: &Option<(Option<Note>, u64)>,
    order: &LimitOrder,
    is_first_fill: bool,
    spent_amount: u64,
    signature: &Signature,
) -> Result<(), SwapThreadExecutionError> {
    //

    // ? Verify that the order were signed correctly
    order.verify_order_signature(signature)?;

    if order.spot_note_info.is_some() {
        check_non_tab_order_validity(
            tree_m,
            partial_fill_info,
            order,
            is_first_fill,
            spent_amount,
        )?;
    } else {
        // let prev_filled_amount = if partial_fill_info.is_some() {
        //     partial_fill_info.as_ref().unwrap().1
        // } else {
        //     0
        // };

        check_tab_order_validity(tabs_state_tree, order, spent_amount)?;
    }

    return Ok(());
}

pub fn update_state_after_order(
    tree: &Arc<Mutex<SuperficialTree>>,
    tabs_state_tree: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes: &Arc<Mutex<HashMap<u64, BigUint>>>,
    updated_tab_hashes: &Arc<Mutex<HashMap<u32, BigUint>>>,
    rollback_safeguard: &Arc<Mutex<HashMap<ThreadId, RollbackInfo>>>,
    thread_id: ThreadId,
    order: &LimitOrder,
    spot_note_info: &Option<SpotNotesInfo>,
    note_info_output: &Option<NoteInfoExecutionOutput>,
    updated_order_tab: &Option<OrderTab>,
) -> Result<(), SwapThreadExecutionError> {
    if spot_note_info.is_some() {
        let notes_in = &spot_note_info.as_ref().unwrap().notes_in;
        let refund_note = &spot_note_info.as_ref().unwrap().refund_note;
        let swap_note = &note_info_output.as_ref().unwrap().swap_note;
        let new_partial_fill_info = &note_info_output.as_ref().unwrap().new_partial_fill_info;
        let prev_partial_refund_note = &note_info_output
            .as_ref()
            .unwrap()
            .prev_partial_fill_refund_note;

        let is_first_fill = prev_partial_refund_note.is_none();

        update_state_after_non_tab_order(
            tree,
            updated_note_hashes,
            rollback_safeguard,
            thread_id,
            is_first_fill,
            order.order_id,
            notes_in,
            refund_note,
            swap_note,
            new_partial_fill_info,
            prev_partial_refund_note,
        )?
    } else {
        let updated_order_tab = updated_order_tab.as_ref().unwrap();

        update_state_after_tab_order(
            tabs_state_tree,
            updated_tab_hashes,
            order,
            updated_order_tab,
        )?;
    }

    Ok(())
}
