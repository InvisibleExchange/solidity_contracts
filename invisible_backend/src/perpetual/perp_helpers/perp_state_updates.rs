// * ==============================================================================
// * STATE UPDATE FUNCTIONS * //

use std::{collections::HashMap, sync::Arc};

use num_bigint::BigUint;
use num_traits::Zero;
use parking_lot::Mutex;

use crate::utils::crypto_utils::EcPoint;
use crate::{
    trees::superficial_tree::SuperficialTree,
    utils::{
        errors::{send_perp_swap_error, PerpSwapExecutionError},
        notes::Note,
    },
};

use super::super::{perp_position::PerpPosition, PositionEffectType};
use error_stack::Result;

// ! FIRST FILL ! // ===================== (OPEN ORDERS) =====================
pub fn update_state_after_swap_first_fill(
    //
    state_tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    notes_in: &Vec<Note>,
    refund_note: &Option<Note>,
    partial_fill_refund_note: Option<&Note>,
    order_id: u64,
) -> Result<(), PerpSwapExecutionError> {
    let mut tree = state_tree_m.lock();
    let mut updated_note_hashes = updated_note_hashes_m.lock();

    //  ? verify notes exist in the tree
    for note in notes_in.iter() {
        let leaf_hash = tree.get_leaf_by_index(note.index);

        if leaf_hash != note.hash {
            return Err(send_perp_swap_error(
                "note spent for swap does not exist in the state".to_string(),
                Some(order_id),
                None,
            ));
        }
    }

    // ? Update the state tree
    let refund_idx = notes_in[0].index;
    let refund_hash = if refund_note.is_some() {
        refund_note.as_ref().unwrap().hash.clone()
    } else {
        BigUint::zero()
    };

    tree.update_leaf_node(&refund_hash, refund_idx);
    updated_note_hashes.insert(refund_idx, refund_hash);

    if partial_fill_refund_note.is_some() {
        //

        let note = partial_fill_refund_note.unwrap();
        let idx: u64 = note.index;

        tree.update_leaf_node(&note.hash, idx);
        updated_note_hashes.insert(idx, note.hash.clone());
        //
    } else if notes_in.len() > 1 {
        //
        let idx = notes_in[1].index;

        tree.update_leaf_node(&BigUint::zero(), idx);
        updated_note_hashes.insert(idx, BigUint::zero());
        //
    }

    for i in 2..notes_in.len() {
        let idx = notes_in[i].index;

        tree.update_leaf_node(&BigUint::zero(), idx);
        updated_note_hashes.insert(idx, BigUint::zero());
    }
    drop(tree);
    drop(updated_note_hashes);

    Ok(())
}

// ! LATER FILL ! // ===================== (OPEN ORDERS) =====================
pub fn update_state_after_swap_later_fills(
    state_tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    prev_partial_fill_refund_note: Note,
    new_partial_fill_refund_note: Option<&Note>,
) -> Result<(), PerpSwapExecutionError> {
    let mut tree = state_tree_m.lock();
    let mut updated_note_hashes = updated_note_hashes_m.lock();

    if new_partial_fill_refund_note.is_some() {
        let pfr_note: &Note = new_partial_fill_refund_note.as_ref().unwrap();
        let pfr_idx = pfr_note.index;

        tree.update_leaf_node(&pfr_note.hash, pfr_idx);
        updated_note_hashes.insert(pfr_idx, pfr_note.hash.clone());
    } else {
        let pfr_idx = prev_partial_fill_refund_note.index;

        tree.update_leaf_node(&BigUint::zero(), pfr_idx);
        updated_note_hashes.insert(pfr_idx, BigUint::zero());
    }

    drop(tree);
    drop(updated_note_hashes);

    Ok(())
}

// ! UPDATING PERPETUAL STATE ! // ============================================
pub fn update_perpetual_state(
    perpetual_state_tree_m: &Arc<Mutex<SuperficialTree>>,
    perpetual_updated_position_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    position_effect_type: &PositionEffectType,
    position_idx: u32,
    position: Option<&PerpPosition>,
    prev_position: Option<&PerpPosition>,
) -> Result<(), PerpSwapExecutionError> {
    //

    // TODO: SHould check that the position exists in the tree

    let mut perpetual_state_tree = perpetual_state_tree_m.lock();
    let mut perpetual_updated_position_hashes = perpetual_updated_position_hashes_m.lock();
    if *position_effect_type == PositionEffectType::Open {
        let position = position.unwrap();

        perpetual_state_tree.update_leaf_node(&position.hash, position.index as u64);
        perpetual_updated_position_hashes.insert(position.index as u64, position.hash.clone());
    } else {
        if let None = prev_position {
            return Err(send_perp_swap_error(
                "position to update does not exist in the state".to_string(),
                None,
                None,
            ));
        }

        let leaf_hash = perpetual_state_tree.get_leaf_by_index(prev_position.unwrap().index as u64);

        if prev_position.as_ref().unwrap().hash != leaf_hash {
            return Err(send_perp_swap_error(
                "position to update does not exist in the state".to_string(),
                None,
                None,
            ));
        }

        let position_hash: BigUint;
        if position.is_some() {
            position_hash = position.unwrap().hash.clone();
        } else {
            position_hash = BigUint::zero()
        };

        perpetual_state_tree.update_leaf_node(&position_hash, position_idx as u64);
        perpetual_updated_position_hashes.insert(position_idx as u64, position_hash);
    }
    drop(perpetual_state_tree);
    drop(perpetual_updated_position_hashes);

    Ok(())
}

// ! RETURN COLLATERAL ON POSITION CLOSE ! // =======
pub fn return_collateral_on_position_close(
    state_tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    idx: u64,
    collateral_return_amount: u64,
    collateral_token: u64,
    collateral_returned_address: &EcPoint,
    collateral_returned_blinding: &BigUint,
) -> Result<Note, PerpSwapExecutionError> {
    let return_collateral_note = Note::new(
        idx,
        collateral_returned_address.clone(),
        collateral_token,
        collateral_return_amount,
        collateral_returned_blinding.clone(),
    );

    let mut tree = state_tree_m.lock();
    let mut updated_note_hashes = updated_note_hashes_m.lock();

    tree.update_leaf_node(&return_collateral_note.hash, idx);
    updated_note_hashes.insert(idx, return_collateral_note.hash.clone());
    drop(tree);
    drop(updated_note_hashes);

    return Ok(return_collateral_note);
}
