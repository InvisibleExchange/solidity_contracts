use parking_lot::Mutex;
use std::{collections::HashMap, sync::Arc, thread::ThreadId};
use tokio::sync::mpsc::Sender as MpscSender;
use tokio::sync::oneshot::{self, Sender};

use num_bigint::BigUint;
use num_traits::Zero;

use crate::{
    server::grpc::{GrpcMessage, GrpcTxResponse, MessageType, RollbackMessage},
    trees::superficial_tree::SuperficialTree,
    utils::notes::Note,
};

// * Rollback Deposit Updates ----------------------------------------------------------

// TODO: ARE ROLLBACKS EVEN NECESSARY?? IS THERE A BETTER WAY TO GUARENTEE THAT THE TREE IS IN A VALID STATE?
// TODO: IF ROLLBACKS ARE NECESSARY, THEN WE NEED TO UPDATE THE SWAP_OUTPUT_JSON AS WELL AND REMOVE THE ADDED TRANSACTION FROM THE BATCH
// TODO: MAYBE WE CAN JUST CHECK THAT ALL UPDATES ARE VALID BEFORE WE COMMIT THEM TO THE TREE AND REMOVE ROLLBACKS COMPLETELY

/// In case of an unexpected error, this function will rollback the deposit updates
pub fn rollback_deposit_updates(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    rollback_info: RollbackInfo,
) {
    // ? Use the zero_idxs to write zero_notes into the tree at the indexes where the notes where created
    let mut tree = tree_m.lock();
    let mut updated_note_hashes = updated_note_hashes_m.lock();
    for idx in rollback_info.zero_idxs.unwrap() {
        // let (proof, proof_pos) = tree.get_proof(idx);
        // tree.update_node(&BigUint::zero(), idx, &proof);

        tree.update_leaf_node(&BigUint::zero(), idx);
        updated_note_hashes.insert(idx, BigUint::zero());
    }
    drop(tree);
    drop(updated_note_hashes);
}

// * Rollback Swap Updates ------------------------------------------------------------

pub fn rollback_swap_updates(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    rollback_message: RollbackMessage,
    rollback_info: RollbackInfo,
) {
    // ? Rollback the swap_state  updates
    let mut tree = tree_m.lock();
    let mut updated_note_hashes = updated_note_hashes_m.lock();

    let rollback_msg_a_id = rollback_message.notes_in_a.0;
    let rollback_msg_b_id = rollback_message.notes_in_b.0;

    let rollback_info_a_id = if rollback_info.swap_rollback_info_a.is_some() {
        rollback_info
            .swap_rollback_info_a
            .as_ref()
            .unwrap()
            .order_id
    } else {
        0
    };
    let rollback_info_b_id = if rollback_info.swap_rollback_info_b.is_some() {
        rollback_info
            .swap_rollback_info_b
            .as_ref()
            .unwrap()
            .order_id
    } else {
        0
    };

    if rollback_info.swap_rollback_info_a.is_some() {
        // ? Rollback the swap_state_a updates

        let rollback_info_a = rollback_info.swap_rollback_info_a.unwrap();

        let is_first_fill = rollback_info_a.prev_pfr_note.is_none();

        if is_first_fill {
            let notes_in = if rollback_msg_a_id == rollback_info_a_id
                || rollback_msg_b_id == rollback_info_b_id
            {
                rollback_message.clone().notes_in_a.1.unwrap()
            } else {
                rollback_message.clone().notes_in_b.1.unwrap()
            };
            if notes_in.len() < 2 {
                let swap_note_idx = rollback_info_a.swap_note_idx;
                // ? set a zero leaf at the swap_note_idx in the tree
                // let (proof, proof_pos) = tree.get_proof(swap_note_idx);
                // tree.update_node(&BigUint::zero(), swap_note_idx, &proof);

                tree.update_leaf_node(&BigUint::zero(), swap_note_idx);
                updated_note_hashes.insert(swap_note_idx, BigUint::zero());
            }
            let new_pfr_note_idx = rollback_info_a.new_pfr_note_idx;
            if notes_in.len() < 3 && new_pfr_note_idx.is_some() {
                // ? set a zero leaf at the pfr_note_idx in the tree

                let pfr_index = new_pfr_note_idx.unwrap();
                // let (proof, proof_pos) = tree.get_proof(pfr_index);
                // tree.update_node(&BigUint::zero(), pfr_index, &proof);

                tree.update_leaf_node(&BigUint::zero(), pfr_index);
                updated_note_hashes.insert(pfr_index, BigUint::zero());
            }

            for note in notes_in {
                // ? insert all the notes_in back into the state
                // let (proof, proof_pos) = tree.get_proof(note.index);
                // tree.update_node(&note.hash, note.index, &proof);

                tree.update_leaf_node(&note.hash, note.index);
                updated_note_hashes.insert(note.index, note.hash.clone());
            }
        } else {
            let prev_pfr_note = rollback_info_a.prev_pfr_note;
            // ? insert the pfr_note back into the state (at the swap_note_idx)
            let prev_pfr_note = prev_pfr_note.unwrap();
            // let (proof, proof_pos) = tree.get_proof(prev_pfr_note.index);
            // tree.update_node(&prev_pfr_note.hash, prev_pfr_note.index, &proof);

            tree.update_leaf_node(&prev_pfr_note.hash, prev_pfr_note.index);
            updated_note_hashes.insert(prev_pfr_note.index, prev_pfr_note.hash.clone());

            let new_pfr_note_idx = rollback_info_a.new_pfr_note_idx;
            if new_pfr_note_idx.is_some() {
                // ? insert a zero leaf back into the state at the new_pfr_note_idx
                let new_pfr_note_idx = new_pfr_note_idx.unwrap();
                // let (proof, proof_pos) = tree.get_proof(new_pfr_note_idx);
                // tree.update_node(&BigUint::zero(), new_pfr_note_idx, &proof);

                tree.update_leaf_node(&BigUint::zero(), new_pfr_note_idx);
                updated_note_hashes.insert(new_pfr_note_idx, BigUint::zero());
            }
        }
    }

    if rollback_info.swap_rollback_info_b.is_some() {
        // ? Rollback the swap_state_b updates

        let rollback_info_b = rollback_info.swap_rollback_info_b.unwrap();

        let is_first_fill = rollback_info_b.prev_pfr_note.as_ref().is_none();

        if is_first_fill {
            let notes_in = if rollback_msg_a_id == rollback_info_a_id
                || rollback_msg_b_id == rollback_info_b_id
            {
                rollback_message.notes_in_b.1.unwrap()
            } else {
                rollback_message.notes_in_a.1.unwrap()
            };
            if notes_in.len() < 2 {
                let swap_note_idx = rollback_info_b.swap_note_idx;
                // ? set a zero leaf at the swap_note_idx in the tree
                // let (proof, proof_pos) = tree.get_proof(swap_note_idx);
                // tree.update_node(&BigUint::zero(), swap_note_idx, &proof);

                tree.update_leaf_node(&BigUint::zero(), swap_note_idx);
                updated_note_hashes.insert(swap_note_idx, BigUint::zero());
            }
            let new_pfr_note_idx = rollback_info_b.new_pfr_note_idx;
            if notes_in.len() < 3 && new_pfr_note_idx.is_some() {
                // ? set a zero leaf at the pfr_note_idx in the tree

                let pfr_index = new_pfr_note_idx.unwrap();
                // let (proof, proof_pos) = tree.get_proof(pfr_index);
                // tree.update_node(&BigUint::zero(), pfr_index, &proof);

                tree.update_leaf_node(&BigUint::zero(), pfr_index);
                updated_note_hashes.insert(pfr_index, BigUint::zero());
            }

            for note in notes_in {
                // ? insert all the notes_in back into the state
                // let (proof, proof_pos) = tree.get_proof(note.index);
                // tree.update_node(&note.hash, note.index, &proof);

                tree.update_leaf_node(&note.hash, note.index);
                updated_note_hashes.insert(note.index, note.hash.clone());
            }
        } else {
            let prev_pfr_note = rollback_info_b.prev_pfr_note;
            // ? insert the pfr_note back into the state (at the swap_note_idx)
            let prev_pfr_note = prev_pfr_note.unwrap();
            // let (proof, proof_pos) = tree.get_proof(prev_pfr_note.index);
            // tree.update_node(&prev_pfr_note.hash, prev_pfr_note.index, &proof);

            tree.update_leaf_node(&prev_pfr_note.hash, prev_pfr_note.index);
            updated_note_hashes.insert(prev_pfr_note.index, prev_pfr_note.hash.clone());

            let new_pfr_note_idx = rollback_info_b.new_pfr_note_idx;
            if new_pfr_note_idx.is_some() {
                // ? insert a zero leaf back into the state at the new_pfr_note_idx
                let new_pfr_note_idx = new_pfr_note_idx.unwrap();
                // let (proof, proof_pos) = tree.get_proof(new_pfr_note_idx);
                // tree.update_node(&BigUint::zero(), new_pfr_note_idx, &proof);

                tree.update_leaf_node(&BigUint::zero(), new_pfr_note_idx);
                updated_note_hashes.insert(new_pfr_note_idx, BigUint::zero());
            }
        }
    }
}

// * Rollback Withdrawal Updates ------------------------------------------------------

pub fn rollback_withdrawal_updates(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    rollback_message: RollbackMessage,
) {
    // ? Insert the note hashes back into the tree

    let mut tree = tree_m.lock();
    let mut updated_note_hashes = updated_note_hashes_m.lock();
    for note in rollback_message.notes_in_a.1.unwrap() {
        // let (proof, proof_pos) = tree.get_proof(note.index);
        // tree.update_node(&note.hash, note.index, &proof);

        tree.update_leaf_node(&note.hash, note.index);
        updated_note_hashes.insert(note.index, note.hash);
    }
    drop(tree);
    drop(updated_note_hashes);
}

// ======================================================================================

pub async fn initiate_rollback(
    transaction_mpsc_tx: MpscSender<(GrpcMessage, Sender<GrpcTxResponse>)>,
    thread_id: ThreadId,
    rollback_message: RollbackMessage,
) {
    let (resp_tx, resp_rx) = oneshot::channel();

    let mut grpc_message = GrpcMessage::new();
    grpc_message.msg_type = MessageType::Rollback;
    grpc_message.rollback_info_message = Some((thread_id, rollback_message));

    transaction_mpsc_tx
        .send((grpc_message, resp_tx))
        .await
        .ok()
        .unwrap();
    resp_rx.await.unwrap();

    println!("Rollback successful");
}

pub struct RollbackInfo {
    pub zero_idxs: Option<Vec<u64>>,
    pub swap_rollback_info_a: Option<OrderRollbackInfo>,
    pub swap_rollback_info_b: Option<OrderRollbackInfo>,
}

pub struct OrderRollbackInfo {
    pub order_id: u64,
    pub prev_pfr_note: Option<Note>,
    pub new_pfr_note_idx: Option<u64>,
    pub swap_note_idx: u64,
}
