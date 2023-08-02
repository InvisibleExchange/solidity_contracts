use std::{collections::HashMap, sync::Arc};

use error_stack::Result;
use num_bigint::BigUint;
use parking_lot::Mutex;

use crate::{
    transactions::limit_order::{LimitOrder, SpotNotesInfo},
    trees::superficial_tree::SuperficialTree,
    utils::{
        errors::{send_swap_error, SwapThreadExecutionError},
        notes::Note,
    },
};

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
    note_info: &SpotNotesInfo,
    token_spent: u32,
    spent_amount_x: u64,
    idx: u64,
) -> Note {
    let new_partial_refund_amount = spend_amount_left - spent_amount_x;

    let new_partial_refund_note: Note = Note::new(
        idx,
        note_info.notes_in[0].address.clone(),
        token_spent,
        new_partial_refund_amount,
        note_info.notes_in[0].blinding.clone(),
    );

    return new_partial_refund_note;
}

/// Creates the swap note, which will be the result of the swap (received funds)
pub fn construct_new_swap_note(
    partial_fill_info: &Option<(Option<Note>, u64)>,
    tree_m: &Arc<Mutex<SuperficialTree>>,
    is_first_fill: bool,
    note_info: &SpotNotesInfo,
    token_received: u32,
    spent_amount_y: u64,
    fee_taken_x: u64,
) -> Note {
    let swap_note_a_idx: u64;
    if is_first_fill {
        if note_info.notes_in.len() > 1 {
            swap_note_a_idx = note_info.notes_in[1].index;
        } else {
            let mut tree = tree_m.lock();
            let zero_idx = tree.first_zero_idx();
            swap_note_a_idx = zero_idx;
            drop(tree);
        }
    } else {
        swap_note_a_idx = partial_fill_info
            .as_ref()
            .unwrap()
            .0
            .as_ref()
            .unwrap()
            .index;
    };

    return Note::new(
        swap_note_a_idx,
        note_info.dest_received_address.clone(),
        token_received,
        spent_amount_y - fee_taken_x,
        note_info.dest_received_blinding.clone(),
    );
}

// * ================================================================================================

// * CONSISTENCY CHECKS * //

/// checks if all the notes spent have the right token \
/// and that the sum of inputs is valid for the given swap and refund amounts
pub fn check_note_sums(order: &LimitOrder) -> Result<(), SwapThreadExecutionError> {
    let note_info = order.spot_note_info.as_ref().unwrap();

    let mut sum_notes: u64 = 0;
    for note in note_info.notes_in.iter() {
        if note.token != order.token_spent {
            return Err(send_swap_error(
                "note and order token mismatch".to_string(),
                Some(order.order_id),
                None,
            ));
        }

        sum_notes += note.amount
    }

    let refund_amount = if note_info.refund_note.is_some() {
        note_info.refund_note.as_ref().unwrap().amount
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
    // Todo: if any leftover value store it in insurance fund

    Ok(())
}

/// checks if the partial fill info is consistent with the order \
pub fn check_prev_fill_consistencies(
    partial_fill_info: &Option<(Option<Note>, u64)>,
    order: &LimitOrder,
    spend_amount_x: u64,
) -> Result<(), SwapThreadExecutionError> {
    let partial_refund_note = &partial_fill_info.as_ref().unwrap().0.as_ref().unwrap();
    let note_info = order.spot_note_info.as_ref().unwrap();

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
    if partial_refund_note.address.x != note_info.notes_in[0].address.x {
        return Err(send_swap_error(
            "pfr note address invalid".to_string(),
            Some(order.order_id),
            None,
        ));
    }

    Ok(())
}

pub fn non_tab_consistency_checks(
    order_a: &LimitOrder,
    order_b: &LimitOrder,
) -> Result<(), SwapThreadExecutionError> {
    let note_info_a = &order_a.spot_note_info;
    let note_info_b = &order_b.spot_note_info;

    // ? Check that the notes spent are all different for both orders (different indexes)
    let mut valid = true;
    let mut valid_a = true;
    let mut valid_b = true;

    let mut spent_indexes_a: Vec<u64> = Vec::new();
    let mut hashes_a: HashMap<u64, BigUint> = HashMap::new();

    if note_info_a.is_some() {
        let _ = note_info_a
            .as_ref()
            .unwrap()
            .notes_in
            .iter()
            .for_each(|note| {
                if spent_indexes_a.contains(&note.index) {
                    valid_a = false;
                }
                spent_indexes_a.push(note.index);
                hashes_a.insert(note.index, note.hash.clone());
            });
    }

    if note_info_b.is_some() {
        let mut spent_indexes_b: Vec<u64> = Vec::new();
        note_info_b
            .as_ref()
            .unwrap()
            .notes_in
            .iter()
            .for_each(|note| {
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
    }

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
