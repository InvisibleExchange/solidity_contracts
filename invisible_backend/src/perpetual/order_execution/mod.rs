use std::{collections::HashMap, sync::Arc};

use error_stack::Result;
use parking_lot::Mutex;

use crate::{
    trees::superficial_tree::SuperficialTree,
    utils::errors::{send_perp_swap_error, PerpSwapExecutionError},
};

use super::perp_position::PerpPosition;

pub mod close_order;
pub mod modify_order;
pub mod open_order;

pub fn verify_position_existence(
    perpetual_state_tree__: &Arc<Mutex<SuperficialTree>>,
    partially_filled_positions: &Arc<Mutex<HashMap<String, (PerpPosition, u64)>>>,
    position: &Option<PerpPosition>,
    order_id: u64,
) -> Result<PerpPosition, PerpSwapExecutionError> {
    let perpetual_state_tree = perpetual_state_tree__.lock();

    let partially_filled_positions_m = partially_filled_positions.lock();
    if let Some((pos_, _)) = partially_filled_positions_m.get(
        &position
            .as_ref()
            .unwrap()
            .position_header
            .position_address
            .to_string(),
    ) {
        // ? Verify the position hash is valid and exists in the state
        if pos_.hash != pos_.hash_position()
            || perpetual_state_tree.get_leaf_by_index(pos_.index as u64) != pos_.hash
        {
            let pos = position.as_ref().unwrap();

            verify_existance(&perpetual_state_tree, &pos, order_id)?;

            return Ok(pos.clone());
        } else {
            return Ok(pos_.clone());
        }
    } else {
        let pos = position.as_ref().unwrap();

        verify_existance(&perpetual_state_tree, &pos, order_id)?;

        return Ok(pos.clone());
    }
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
