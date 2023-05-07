use std::{collections::HashMap, sync::Arc, thread::ThreadId};

use num_bigint::BigUint;
use num_traits::Zero;
use parking_lot::Mutex;

use crate::{
    server::grpc::RollbackMessage, trees::superficial_tree::SuperficialTree, utils::notes::Note,
};

use super::super::{perp_position::PerpPosition, PositionEffectType};

pub fn rollback_perp_swap(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    perpetual_state_tree_m: &Arc<Mutex<SuperficialTree>>,
    perpetual_updated_position_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    rollback_message: RollbackMessage,
    rollback_info: PerpRollbackInfo,
) {
    // ? Rollback the swap_state  updates
    let mut tree = tree_m.lock();
    let mut updated_note_hashes = updated_note_hashes_m.lock();
    let mut perp_tree = perpetual_state_tree_m.lock();
    let mut perp_updated_position_hashes = perpetual_updated_position_hashes_m.lock();

    let rollback_msg_a_id = rollback_message.notes_in_a.0;
    let rollback_msg_b_id = rollback_message.notes_in_b.0;

    let rollback_info_a_id = if rollback_info.open_order_rollback_info_a.is_some() {
        rollback_info
            .open_order_rollback_info_a
            .as_ref()
            .unwrap()
            .order_id
    } else {
        0
    };
    let rollback_info_b_id = if rollback_info.open_order_rollback_info_a.is_some() {
        rollback_info
            .open_order_rollback_info_a
            .as_ref()
            .unwrap()
            .order_id
    } else {
        0
    };

    if rollback_info.open_order_rollback_info_a.is_some() {
        // ? Rollback the swap_state_a updates

        let rollback_info_a = rollback_info.open_order_rollback_info_a.unwrap();

        if rollback_info_a.position_effect_type == PositionEffectType::Open {
            let is_first_fill = rollback_info_a.prev_pfr_note.is_none();

            if is_first_fill {
                let notes_in = if rollback_msg_a_id == rollback_info_a_id
                    || rollback_msg_b_id == rollback_info_b_id
                {
                    rollback_message.clone().notes_in_a.1.unwrap()
                } else {
                    rollback_message.clone().notes_in_b.1.unwrap()
                };
                if notes_in.len() < 2 && rollback_info_a.new_pfr_note_idx.is_some() {
                    // ?  write a zero note at the pfr_index
                    // let (proof, proof_pos) =
                    //     tree.get_proof(rollback_info_a.new_pfr_note_idx.unwrap());
                    // tree.update_node(
                    //     &BigUint::zero(),
                    //     rollback_info_a.new_pfr_note_idx.unwrap(),
                    //     &proof,
                    // );

                    tree.update_leaf_node(
                        &BigUint::zero(),
                        rollback_info_a.new_pfr_note_idx.unwrap(),
                    );
                    updated_note_hashes
                        .insert(rollback_info_a.new_pfr_note_idx.unwrap(), BigUint::zero());
                }

                // ?  Add back all other notes
                for note in notes_in.iter() {
                    // ?  Add back the note
                    // let (proof, proof_pos) = tree.get_proof(note.index);
                    // tree.update_node(&note.hash, note.index, &proof);

                    tree.update_leaf_node(&note.hash, note.index);
                    updated_note_hashes.insert(note.index, note.hash.clone());
                }

                // ?  write a zero position at the new position idx
                // let (proof, proof_pos) = perp_tree.get_proof(rollback_info.new_position_idx_a);
                // perp_tree.update_node(&BigUint::zero(), rollback_info.new_position_idx_a, &proof);

                tree.update_leaf_node(&BigUint::zero(), rollback_info.new_position_idx_a);
                perp_updated_position_hashes
                    .insert(rollback_info.new_position_idx_a, BigUint::zero());
            } else {
                // ? Add back the pfr note
                let prev_pfr_note = rollback_info_a.prev_pfr_note.unwrap();
                // let (proof, proof_pos) = tree.get_proof(prev_pfr_note.index);
                // tree.update_node(&prev_pfr_note.hash, prev_pfr_note.index, &proof);

                tree.update_leaf_node(&prev_pfr_note.hash, prev_pfr_note.index);
                updated_note_hashes.insert(prev_pfr_note.index, prev_pfr_note.hash);

                // ? Add back the prev_position
                let prev_position = rollback_info.prev_position_a.unwrap();
                // let (proof, proof_pos) = perp_tree.get_proof(prev_position.index as u64);
                // perp_tree.update_node(&prev_position.hash, prev_position.index as u64, &proof);

                perp_tree.update_leaf_node(&prev_position.hash, prev_position.index as u64);
                perp_updated_position_hashes.insert(prev_position.index as u64, prev_position.hash);
            }
        } else if rollback_info_a.position_effect_type == PositionEffectType::Close
            && rollback_info.collateral_note_idx_a.is_some()
        {
            // ? write a zero leaf at the collateral_return note index
            // let (proof, proof_pos) = tree.get_proof(rollback_info.collateral_note_idx_a.unwrap());
            // tree.update_node(
            //     &BigUint::zero(),
            //     rollback_info.collateral_note_idx_a.unwrap(),
            //     &proof,
            // );

            tree.update_leaf_node(
                &BigUint::zero(),
                rollback_info.collateral_note_idx_a.unwrap(),
            );
            updated_note_hashes.insert(
                rollback_info.collateral_note_idx_a.unwrap(),
                BigUint::zero(),
            );

            // ? write back the prev position if is_some()
            if rollback_info.prev_position_a.is_some() {
                let prev_position = rollback_info.prev_position_a.unwrap();
                // let (proof, proof_pos) = perp_tree.get_proof(prev_position.index as u64);
                // perp_tree.update_node(&prev_position.hash, prev_position.index as u64, &proof);

                perp_tree.update_leaf_node(&prev_position.hash, prev_position.index as u64);
                perp_updated_position_hashes.insert(prev_position.index as u64, prev_position.hash);
            }
        } else {
            // ? write back the prev position if is_some()
            if rollback_info.prev_position_a.is_some() {
                let prev_position = rollback_info.prev_position_a.unwrap();
                // let (proof, proof_pos) = perp_tree.get_proof(prev_position.index as u64);
                // perp_tree.update_node(&prev_position.hash, prev_position.index as u64, &proof);

                perp_tree.update_leaf_node(&prev_position.hash, prev_position.index as u64);
                perp_updated_position_hashes.insert(prev_position.index as u64, prev_position.hash);
            }
        }
    }

    if rollback_info.open_order_rollback_info_b.is_some() {
        // ? Rollback the swap_state_b updates

        let rollback_info_b = rollback_info.open_order_rollback_info_b.unwrap();

        if rollback_info_b.position_effect_type == PositionEffectType::Open {
            let is_first_fill = rollback_info_b.prev_pfr_note.is_none();

            if is_first_fill {
                let notes_in = if rollback_msg_a_id == rollback_info_a_id
                    || rollback_msg_b_id == rollback_info_b_id
                {
                    rollback_message.notes_in_b.1.unwrap()
                } else {
                    rollback_message.notes_in_a.1.unwrap()
                };
                if notes_in.len() < 2 && rollback_info_b.new_pfr_note_idx.is_some() {
                    // ?  write a zero note at the pfr_index
                    // let (proof, proof_pos) =
                    //     tree.get_proof(rollback_info_b.new_pfr_note_idx.unwrap());
                    // tree.update_node(
                    //     &BigUint::zero(),
                    //     rollback_info_b.new_pfr_note_idx.unwrap(),
                    //     &proof,
                    // );

                    tree.update_leaf_node(
                        &BigUint::zero(),
                        rollback_info_b.new_pfr_note_idx.unwrap(),
                    );
                    updated_note_hashes
                        .insert(rollback_info_b.new_pfr_note_idx.unwrap(), BigUint::zero());
                }

                // ?  Add back all other notes
                for note in notes_in.iter() {
                    // ?  Add back the note
                    // let (proof, proof_pos) = tree.get_proof(note.index);
                    // tree.update_node(&note.hash, note.index, &proof);

                    tree.update_leaf_node(&note.hash, note.index);
                    updated_note_hashes.insert(note.index, note.hash.clone());
                }

                // ?  write a zero position at the new position idx
                // let (proof, proof_pos) = perp_tree.get_proof(rollback_info.new_position_idx_b);
                // perp_tree.update_node(&BigUint::zero(), rollback_info.new_position_idx_b, &proof);

                perp_tree.update_leaf_node(&BigUint::zero(), rollback_info.new_position_idx_b);
                perp_updated_position_hashes
                    .insert(rollback_info.new_position_idx_b, BigUint::zero());
            } else {
                // ? Add back the pfr note
                let prev_pfr_note = rollback_info_b.prev_pfr_note.unwrap();
                // let (proof, proof_pos) = tree.get_proof(prev_pfr_note.index);
                // tree.update_node(&prev_pfr_note.hash, prev_pfr_note.index, &proof);

                tree.update_leaf_node(&prev_pfr_note.hash, prev_pfr_note.index);
                updated_note_hashes.insert(prev_pfr_note.index, prev_pfr_note.hash);

                // ? Add back the prev_position
                let prev_position = rollback_info.prev_position_b.unwrap();
                // let (proof, proof_pos) = perp_tree.get_proof(prev_position.index as u64);
                // perp_tree.update_node(&prev_position.hash, prev_position.index as u64, &proof);

                perp_tree.update_leaf_node(&prev_position.hash, prev_position.index as u64);
                perp_updated_position_hashes.insert(prev_position.index as u64, prev_position.hash);
            }
        } else if rollback_info_b.position_effect_type == PositionEffectType::Close
            && rollback_info.collateral_note_idx_b.is_some()
        {
            // ? write a zero leaf at the collateral_return note index
            // let (proof, proof_pos) = tree.get_proof(rollback_info.collateral_note_idx_b.unwrap());
            // tree.update_node(
            //     &BigUint::zero(),
            //     rollback_info.collateral_note_idx_b.unwrap(),
            //     &proof,
            // );

            tree.update_leaf_node(
                &BigUint::zero(),
                rollback_info.collateral_note_idx_b.unwrap(),
            );
            updated_note_hashes.insert(
                rollback_info.collateral_note_idx_b.unwrap(),
                BigUint::zero(),
            );

            // ? write back the prev position if is_some()
            if rollback_info.prev_position_b.is_some() {
                let prev_position = rollback_info.prev_position_b.unwrap();
                // let (proof, proof_pos) = perp_tree.get_proof(prev_position.index as u64);
                // perp_tree.update_node(&prev_position.hash, prev_position.index as u64, &proof);

                perp_tree.update_leaf_node(&prev_position.hash, prev_position.index as u64);
                perp_updated_position_hashes.insert(prev_position.index as u64, prev_position.hash);
            }
        } else {
            // ? write back the prev position if is_some()
            if rollback_info.prev_position_b.is_some() {
                let prev_position = rollback_info.prev_position_b.unwrap();
                // let (proof, proof_pos) = perp_tree.get_proof(prev_position.index as u64);
                // perp_tree.update_node(&prev_position.hash, prev_position.index as u64, &proof);

                perp_tree.update_leaf_node(&prev_position.hash, prev_position.index as u64);
                perp_updated_position_hashes.insert(prev_position.index as u64, prev_position.hash);
            }
        }
    }
}

pub fn save_open_order_rollback_info(
    a: bool,
    perp_rollback_safeguard: &Arc<Mutex<HashMap<ThreadId, PerpRollbackInfo>>>,
    thread_id: ThreadId,
    order_id: u64,
    new_pfr_note: &Option<Note>,
    prev_pfr_note: &Option<Note>,
    new_position_idx: u32,
    prev_position: &Option<PerpPosition>,
) {
    // ? Right before the first modification is made activate the safeguard
    // ? If anything fails from here on out the rollback function will be called
    let mut rollback_safeguard_m = perp_rollback_safeguard.lock();
    let rollback_info__ = rollback_safeguard_m.remove(&thread_id);

    let mut rollback_info: PerpRollbackInfo;
    if a {
        if rollback_info__.is_none() {
            rollback_info = PerpRollbackInfo {
                open_order_rollback_info_a: Some(PerpOrderRollbackInfo {
                    order_id,
                    new_pfr_note_idx: if new_pfr_note.is_some() {
                        Some(new_pfr_note.as_ref().unwrap().index)
                    } else {
                        None
                    },
                    prev_pfr_note: prev_pfr_note.clone(),
                    position_effect_type: PositionEffectType::Open,
                }),
                prev_position_a: prev_position.clone(),
                new_position_idx_a: new_position_idx as u64,
                collateral_note_idx_a: None,
                collateral_note_idx_b: None,
                open_order_rollback_info_b: None,
                prev_position_b: None,
                new_position_idx_b: 0,
            };
        } else {
            rollback_info = rollback_info__.unwrap();
            rollback_info.open_order_rollback_info_a = Some(PerpOrderRollbackInfo {
                order_id,
                new_pfr_note_idx: if new_pfr_note.is_some() {
                    Some(new_pfr_note.as_ref().unwrap().index)
                } else {
                    None
                },
                prev_pfr_note: prev_pfr_note.clone(),
                position_effect_type: PositionEffectType::Open,
            });
            rollback_info.prev_position_a = prev_position.clone();
            rollback_info.new_position_idx_a = new_position_idx as u64;
        }
    } else {
        if rollback_info__.is_none() {
            rollback_info = PerpRollbackInfo {
                open_order_rollback_info_b: Some(PerpOrderRollbackInfo {
                    order_id,
                    new_pfr_note_idx: if new_pfr_note.is_some() {
                        Some(new_pfr_note.as_ref().unwrap().index)
                    } else {
                        None
                    },
                    prev_pfr_note: prev_pfr_note.clone(),
                    position_effect_type: PositionEffectType::Open,
                }),
                prev_position_b: prev_position.clone(),
                new_position_idx_b: new_position_idx as u64,
                collateral_note_idx_b: None,
                collateral_note_idx_a: None,
                open_order_rollback_info_a: None,
                prev_position_a: None,
                new_position_idx_a: 0,
            };
        } else {
            rollback_info = rollback_info__.unwrap();
            rollback_info.open_order_rollback_info_b = Some(PerpOrderRollbackInfo {
                order_id,
                new_pfr_note_idx: if new_pfr_note.is_some() {
                    Some(new_pfr_note.as_ref().unwrap().index)
                } else {
                    None
                },
                prev_pfr_note: prev_pfr_note.clone(),
                position_effect_type: PositionEffectType::Open,
            });
            rollback_info.prev_position_b = prev_position.clone();
            rollback_info.new_position_idx_b = new_position_idx as u64;
        }
    }

    rollback_safeguard_m.insert(thread_id, rollback_info);
    drop(rollback_safeguard_m);
}

pub fn save_close_order_rollback_info(
    a: bool,
    perp_rollback_safeguard: &Arc<Mutex<HashMap<ThreadId, PerpRollbackInfo>>>,
    thread_id: ThreadId,
    collateral_idx: u64,
    prev_position: &Option<PerpPosition>,
) {
    // ? Right before the first modification is made activate the safeguard
    // ? If anything fails from here on out the rollback function will be called
    let mut rollback_safeguard_m = perp_rollback_safeguard.lock();
    let rollback_info__ = rollback_safeguard_m.remove(&thread_id);

    let mut rollback_info: PerpRollbackInfo;
    if a {
        if rollback_info__.is_none() {
            rollback_info = PerpRollbackInfo {
                open_order_rollback_info_a: None,
                prev_position_a: prev_position.clone(),
                new_position_idx_a: 0,
                collateral_note_idx_a: Some(collateral_idx),
                open_order_rollback_info_b: None,
                prev_position_b: None,
                new_position_idx_b: 0,
                collateral_note_idx_b: None,
            };
        } else {
            rollback_info = rollback_info__.unwrap();
            rollback_info.prev_position_a = prev_position.clone();
            rollback_info.collateral_note_idx_a = Some(collateral_idx);
        }
    } else {
        if rollback_info__.is_none() {
            rollback_info = PerpRollbackInfo {
                open_order_rollback_info_b: None,
                prev_position_b: prev_position.clone(),
                new_position_idx_b: 0,
                collateral_note_idx_b: Some(collateral_idx),
                open_order_rollback_info_a: None,
                prev_position_a: None,
                new_position_idx_a: 0,
                collateral_note_idx_a: None,
            };
        } else {
            rollback_info = rollback_info__.unwrap();
            rollback_info.prev_position_b = prev_position.clone();
            rollback_info.collateral_note_idx_b = Some(collateral_idx);
        }
    }

    rollback_safeguard_m.insert(thread_id, rollback_info);
    drop(rollback_safeguard_m);
}

pub struct PerpRollbackInfo {
    pub open_order_rollback_info_a: Option<PerpOrderRollbackInfo>,
    pub open_order_rollback_info_b: Option<PerpOrderRollbackInfo>,
    pub collateral_note_idx_a: Option<u64>,
    pub collateral_note_idx_b: Option<u64>,
    pub prev_position_a: Option<PerpPosition>,
    pub new_position_idx_a: u64,
    pub prev_position_b: Option<PerpPosition>,
    pub new_position_idx_b: u64,
}

pub struct PerpOrderRollbackInfo {
    pub order_id: u64,
    pub position_effect_type: PositionEffectType,
    pub prev_pfr_note: Option<Note>,
    pub new_pfr_note_idx: Option<u64>,
}
