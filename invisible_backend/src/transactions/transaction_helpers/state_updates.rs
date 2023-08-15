use parking_lot::Mutex;
use std::{collections::HashMap, sync::Arc, thread::ThreadId};

use error_stack::Result;
use num_bigint::BigUint;
use num_traits::Zero;

use crate::{
    transaction_batch::LeafNodeType,
    trees::superficial_tree::SuperficialTree,
    utils::{
        errors::{
            send_withdrawal_error, DepositThreadExecutionError, WithdrawalThreadExecutionError,
        },
        notes::Note,
    },
};

use super::rollbacks::{OrderRollbackInfo, RollbackInfo};

// * ================================================================================================================================================
// * Swap state updates -----------------------------------------------------------------------------------------------------------------------------

// ! FIRST FILL ! // ==================

pub fn update_state_after_swap_first_fill(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_state_hashes_m: &Arc<Mutex<HashMap<u64, (LeafNodeType, BigUint)>>>,
    rollback_safeguard: &Arc<Mutex<HashMap<ThreadId, RollbackInfo>>>,
    thread_id: ThreadId,
    order_id: u64,
    notes_in: &Vec<Note>,
    refund_note: &Option<Note>,
    swap_note: &Note,
    partial_fill_refund_note: &Option<&Note>,
) {
    //

    // ? Right before the first modification is made activate the safeguard
    // ? If anything fails from here on out the rollback function will be called
    let mut rollback_safeguard_m = rollback_safeguard.lock();
    let rollback_info__ = rollback_safeguard_m.remove(&thread_id);
    let mut rollback_info: RollbackInfo;
    if rollback_info__.is_some() {
        rollback_info = rollback_info__.unwrap();
        rollback_info.swap_rollback_info_b = Some(OrderRollbackInfo {
            order_id,
            new_pfr_note_idx: if partial_fill_refund_note.is_some() {
                Some(partial_fill_refund_note.unwrap().index)
            } else {
                None
            },
            prev_pfr_note: None,
            swap_note_idx: swap_note.index,
        });
    } else {
        rollback_info = RollbackInfo {
            zero_idxs: None,
            swap_rollback_info_a: Some(OrderRollbackInfo {
                order_id,
                new_pfr_note_idx: if partial_fill_refund_note.is_some() {
                    Some(partial_fill_refund_note.unwrap().index)
                } else {
                    None
                },
                prev_pfr_note: None,
                swap_note_idx: swap_note.index,
            }),
            swap_rollback_info_b: None,
        };
    }

    rollback_safeguard_m.insert(thread_id, rollback_info);
    drop(rollback_safeguard_m);

    // ? Get lock to mutable values
    let mut tree = tree_m.lock();
    let mut updated_state_hashes = updated_state_hashes_m.lock();

    // ? Update the state tree -———————————————————————————————————
    let refund_idx = notes_in[0].index;
    let refund_hash = if refund_note.is_some() {
        refund_note.as_ref().unwrap().hash.clone()
    } else {
        BigUint::zero()
    };

    tree.update_leaf_node(&refund_hash, refund_idx);
    updated_state_hashes.insert(refund_idx, (LeafNodeType::Note, refund_hash));

    let swap_idx = swap_note.index;

    tree.update_leaf_node(&swap_note.hash, swap_idx);
    updated_state_hashes.insert(swap_idx, (LeafNodeType::Note, swap_note.hash.clone()));

    if partial_fill_refund_note.is_some() {
        //
        let note = partial_fill_refund_note.unwrap();
        let idx: u64 = note.index;

        tree.update_leaf_node(&note.hash, idx);
        updated_state_hashes.insert(idx, (LeafNodeType::Note, note.hash.clone()));
        //
    } else if notes_in.len() > 2 {
        //
        let idx = notes_in[2].index;

        tree.update_leaf_node(&BigUint::zero(), idx);
        updated_state_hashes.insert(idx, (LeafNodeType::Note, BigUint::zero()));
        //
    }

    for i in 3..notes_in.len() {
        let idx = notes_in[i].index;

        tree.update_leaf_node(&BigUint::zero(), idx);
        updated_state_hashes.insert(idx, (LeafNodeType::Note, BigUint::zero()));
    }

    drop(updated_state_hashes);
    drop(tree);
}

// ! LATER FILLS ! // =================

pub fn update_state_after_swap_later_fills(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_state_hashes_m: &Arc<Mutex<HashMap<u64, (LeafNodeType, BigUint)>>>,
    rollback_safeguard: &Arc<Mutex<HashMap<ThreadId, RollbackInfo>>>,
    thread_id: ThreadId,
    order_id: u64,
    prev_partial_fill_refund_note: &Note,
    swap_note: &Note,
    new_partial_fill_refund_note: &Option<&Note>,
) {
    //

    // ? Right before the first modification is made activate the safeguard
    // ? If anything fails from here on out the rollback function will be called
    let mut rollback_safeguard_m = rollback_safeguard.lock();
    let rollback_info__ = rollback_safeguard_m.remove(&thread_id);
    let mut rollback_info: RollbackInfo;
    if rollback_info__.is_some() {
        rollback_info = rollback_info__.unwrap();
        rollback_info.swap_rollback_info_b = Some(OrderRollbackInfo {
            order_id,
            new_pfr_note_idx: if new_partial_fill_refund_note.is_some() {
                Some(new_partial_fill_refund_note.unwrap().index)
            } else {
                None
            },
            prev_pfr_note: Some(prev_partial_fill_refund_note.clone()),
            swap_note_idx: swap_note.index,
        });
    } else {
        rollback_info = RollbackInfo {
            zero_idxs: None,
            swap_rollback_info_a: Some(OrderRollbackInfo {
                order_id,
                new_pfr_note_idx: if new_partial_fill_refund_note.is_some() {
                    Some(new_partial_fill_refund_note.unwrap().index)
                } else {
                    None
                },
                prev_pfr_note: Some(prev_partial_fill_refund_note.clone()),
                swap_note_idx: swap_note.index,
            }),
            swap_rollback_info_b: None,
        };
    }

    rollback_safeguard_m.insert(thread_id, rollback_info);
    drop(rollback_safeguard_m);

    // ? Get mutable pointer locks
    let mut tree = tree_m.lock();
    let mut updated_state_hashes = updated_state_hashes_m.lock();

    // ? Update the state tree
    let swap_idx = swap_note.index;

    tree.update_leaf_node(&swap_note.hash, swap_idx);
    updated_state_hashes.insert(swap_idx, (LeafNodeType::Note, swap_note.hash.clone()));

    if new_partial_fill_refund_note.is_some() {
        let pfr_note: &Note = new_partial_fill_refund_note.as_ref().unwrap();
        let pfr_idx = pfr_note.index;

        tree.update_leaf_node(&pfr_note.hash, pfr_idx);
        updated_state_hashes.insert(pfr_idx, (LeafNodeType::Note, pfr_note.hash.clone()));
    }

    drop(updated_state_hashes);
    drop(tree);
}

// * Deposit state updates ----------------------------------------------------------------------------------------------------------------------

/// Adds the new notes to the state
pub fn update_state_after_deposit(
    tree: &mut SuperficialTree,
    updated_state_hashes_m: &Arc<Mutex<HashMap<u64, (LeafNodeType, BigUint)>>>,
    rollback_safeguard: &Arc<Mutex<HashMap<ThreadId, RollbackInfo>>>,
    notes: &Vec<Note>,
) -> Result<(), DepositThreadExecutionError> {
    //

    // ? Right before the first modification is made activate the safeguard
    // ? If anything fails from here on out the rollback function will be called
    let mut rollback_safeguard_m = rollback_safeguard.lock();
    rollback_safeguard_m.insert(
        std::thread::current().id(),
        RollbackInfo {
            zero_idxs: Some(notes.iter().map(|n| n.index).collect()),
            swap_rollback_info_a: None,
            swap_rollback_info_b: None,
        },
    );
    drop(rollback_safeguard_m);

    // ? Upadte the state by adding the note hashes to the merkle tree
    let mut updated_state_hashes = updated_state_hashes_m.lock();
    for note in notes.iter() {
        let idx = note.index;
        // let (proof, proof_pos) = tree.get_proof(idx);
        // tree.update_node(&note.hash, idx, &proof);

        tree.update_leaf_node(&note.hash, idx);
        updated_state_hashes.insert(idx, (LeafNodeType::Note, note.hash.clone()));
    }
    drop(updated_state_hashes);

    Ok(())
}

// * ===============================================================================================================================================
// * Withdrawal state updates ----------------------------------------------------------------------------------------------------------------------

pub fn update_state_after_withdrawal(
    tree: &mut SuperficialTree,
    updated_state_hashes: &mut HashMap<u64, (LeafNodeType, BigUint)>,
    rollback_safeguard: &Arc<Mutex<HashMap<ThreadId, RollbackInfo>>>,
    notes_in: &Vec<Note>,
    refund_note: &Option<Note>,
) -> Result<(), WithdrawalThreadExecutionError> {
    //

    // ? Right before the first modification is made activate the safeguard
    // ? If anything fails from here on out the rollback function will be called
    let mut rollback_safeguard_m = rollback_safeguard.lock();
    rollback_safeguard_m.insert(
        std::thread::current().id(),
        RollbackInfo {
            zero_idxs: None,
            swap_rollback_info_a: None,
            swap_rollback_info_b: None,
        },
    );
    drop(rollback_safeguard_m);

    // ? Remove the notes_in from the tree and add the refund note
    let refund_idx = notes_in[0].index;
    let z = BigUint::zero();
    let refund_note_hash = if refund_note.is_some() {
        &refund_note.as_ref().unwrap().hash
    } else {
        &z
    };
    let leaf_hash = tree.get_leaf_by_index(refund_idx);
    if leaf_hash != notes_in[0].hash {
        return Err(send_withdrawal_error(
            "note withdrawn does not exist in the state".to_string(),
            None,
        ));
    }

    tree.update_leaf_node(refund_note_hash, refund_idx);
    updated_state_hashes.insert(refund_idx, (LeafNodeType::Note, refund_note_hash.clone()));

    for note in notes_in.iter().skip(1) {
        let idx = note.index;

        // ?verify notes exist in the tree
        let leaf_hash = tree.get_leaf_by_index(idx);
        if leaf_hash != note.hash {
            return Err(send_withdrawal_error(
                "note withdrawn does not exist in the state".to_string(),
                None,
            ));
        }

        tree.update_leaf_node(&BigUint::zero(), idx);
        updated_state_hashes.insert(idx, (LeafNodeType::Note, BigUint::zero()));
    }

    Ok(())
}
