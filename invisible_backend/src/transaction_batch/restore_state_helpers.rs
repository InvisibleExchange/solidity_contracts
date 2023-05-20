use num_bigint::{BigInt, BigUint};
use num_traits::Zero;
use parking_lot::Mutex;
use serde_json::{Map, Value};
use std::{collections::HashMap, str::FromStr, sync::Arc};

use crate::{
    perpetual::DUST_AMOUNT_PER_ASSET, trees::superficial_tree::SuperficialTree,
    utils::crypto_utils::EcPoint, utils::notes::Note,
};

pub fn restore_spot_order_execution(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    transaction: &Map<String, Value>,
    is_a: bool,
) {
    let swap_note = rebuild_swap_note(&transaction, is_a);
    let pfr_note = restore_partial_fill_refund_note(&transaction, is_a);

    if transaction
        .get(if is_a {
            "prev_pfr_note_a"
        } else {
            "prev_pfr_note_b"
        })
        .unwrap()
        .is_null()
    {
        // ? First fill
        let order = transaction
            .get("swap_data")
            .unwrap()
            .get(if is_a { "order_a" } else { "order_b" })
            .unwrap();
        let notes_in = order.get("notes_in").unwrap().as_array().unwrap();
        let refund_note = order.get("refund_note");

        restore_after_swap_first_fill(
            tree_m,
            updated_note_hashes_m,
            &notes_in,
            refund_note,
            swap_note,
            pfr_note,
        );
    } else {
        // ? Second fill

        restore_after_swap_later_fills(tree_m, updated_note_hashes_m, swap_note, pfr_note);
    }
}

// * ======
// * =========
// * ======

pub fn restore_perp_order_execution(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    perpetual_state_tree_m: &Arc<Mutex<SuperficialTree>>,
    perpetual_updated_position_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    perpetual_partial_fill_tracker_m: &Arc<Mutex<HashMap<u64, (Option<Note>, u64, u64)>>>,
    transaction: &Map<String, Value>,
    is_a: bool,
) {
    let order = transaction
        .get(if is_a { "order_a" } else { "order_b" })
        .unwrap();

    match order.get("position_effect_type").unwrap().as_str().unwrap() {
        "Open" => {
            if transaction
                .get(if is_a {
                    "prev_pfr_note_a"
                } else {
                    "prev_pfr_note_b"
                })
                .unwrap()
                .is_null()
            {
                // ? First fill

                let notes_in = order
                    .get("open_order_fields")
                    .unwrap()
                    .get("notes_in")
                    .unwrap()
                    .as_array()
                    .unwrap();
                let refund_note = order.get("open_order_fields").unwrap().get("refund_note");

                restore_after_perp_swap_first_fill(
                    tree_m,
                    updated_note_hashes_m,
                    perpetual_partial_fill_tracker_m,
                    order.get("order_id").unwrap().as_u64().unwrap(),
                    notes_in,
                    refund_note,
                    &transaction
                        .get("indexes")
                        .unwrap()
                        .get(if is_a { "order_a" } else { "order_b" })
                        .unwrap()
                        .get("new_pfr_idx"),
                    &transaction.get(if is_a {
                        "new_pfr_note_hash_a"
                    } else {
                        "new_pfr_note_hash_b"
                    }),
                )
            } else {
                restore_after_perp_swap_later_fills(
                    tree_m,
                    updated_note_hashes_m,
                    perpetual_partial_fill_tracker_m,
                    order.get("order_id").unwrap().as_u64().unwrap(),
                    &transaction
                        .get("indexes")
                        .unwrap()
                        .get(if is_a { "order_a" } else { "order_b" })
                        .unwrap()
                        .get("new_pfr_idx"),
                    &transaction.get(if is_a {
                        "new_pfr_note_hash_a"
                    } else {
                        "new_pfr_note_hash_b"
                    }),
                )
            }
        }
        "Close" => {
            // ? Close position
            restore_return_collateral_note(
                tree_m,
                updated_note_hashes_m,
                &transaction
                    .get("indexes")
                    .unwrap()
                    .get(if is_a { "order_a" } else { "order_b" })
                    .unwrap()
                    .get("return_collateral_idx")
                    .unwrap(),
                &transaction
                    .get(if is_a {
                        "return_collateral_hash_a"
                    } else {
                        "return_collateral_hash_b"
                    })
                    .unwrap(),
            );
        }
        "Liquidate" => {

            // TODO: IMPLEMENT THIS FOR LIQUIDATIONS
        }
        _ => {}
    }

    restore_perpetual_state(
        perpetual_state_tree_m,
        perpetual_updated_position_hashes_m,
        &transaction
            .get("indexes")
            .unwrap()
            .get(if is_a { "order_a" } else { "order_b" })
            .unwrap()
            .get("position_idx"),
        transaction.get(if is_a {
            "new_position_hash_a"
        } else {
            "new_position_hash_b"
        }),
    );
}

// * ======
// * =========
// * ======

pub fn restore_liquidation_order_execution(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    perpetual_state_tree_m: &Arc<Mutex<SuperficialTree>>,
    perpetual_updated_position_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    transaction: &Map<String, Value>,
) {
    let liquidation_order = transaction.get("liquidation_order").unwrap();

    let mut tree = tree_m.lock();
    let mut updated_note_hashes = updated_note_hashes_m.lock();

    let open_order_fields = liquidation_order.get("open_order_fields").unwrap();

    let notes_in = open_order_fields
        .get("notes_in")
        .unwrap()
        .as_array()
        .unwrap();
    let refund_note = open_order_fields.get("refund_note");

    let refund_idx = notes_in[0].get("index").unwrap().as_u64().unwrap();
    let refund_note_hash = if refund_note.unwrap().is_null() {
        BigUint::zero()
    } else {
        BigUint::from_str(refund_note.unwrap().get("hash").unwrap().as_str().unwrap()).unwrap()
    };

    tree.update_leaf_node(&refund_note_hash, refund_idx);
    updated_note_hashes.insert(refund_idx, refund_note_hash);

    // ========

    for i in 1..notes_in.len() {
        let idx = notes_in[i].get("index").unwrap().as_u64().unwrap();

        tree.update_leaf_node(&BigUint::zero(), idx);
        updated_note_hashes.insert(idx, BigUint::zero());
    }

    drop(tree);
    drop(updated_note_hashes);

    // & Update Perpetual State Tree

    let new_position_idx = transaction
        .get("indexes")
        .unwrap()
        .get("new_position_index")
        .unwrap()
        .as_u64()
        .unwrap();
    let new_liquidated_position_idx = transaction
        .get("prev_liquidated_position")
        .unwrap()
        .get("index")
        .unwrap()
        .as_u64()
        .unwrap();

    let new_position_hash = transaction
        .get("new_position_hash")
        .unwrap()
        .as_str()
        .unwrap();
    let new_liquidated_position_hash = transaction
        .get("new_liquidated_position_hash")
        .unwrap()
        .as_str()
        .unwrap();

    let mut perpetual_state_tree = perpetual_state_tree_m.lock();
    let mut perpetual_updated_position_hashes = perpetual_updated_position_hashes_m.lock();

    perpetual_state_tree.update_leaf_node(
        &BigUint::from_str(new_position_hash).unwrap(),
        new_position_idx,
    );
    perpetual_updated_position_hashes.insert(
        new_position_idx,
        BigUint::from_str(new_position_hash).unwrap(),
    );

    let hash = BigUint::from_str(new_liquidated_position_hash).unwrap();
    if hash != BigUint::zero() {
        perpetual_state_tree.update_leaf_node(&hash, new_liquidated_position_idx);
        perpetual_updated_position_hashes.insert(new_liquidated_position_idx, hash);
    }
}

// * =============================================================================================================
// * =============================================================================================================
// * =============================================================================================================

// * SPOT STATE RESTORE FUNCTIONS ================================================================================

pub fn restore_deposit_update(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    notes: &Vec<Value>,
) {
    // ? Upadte the state by adding the note hashes to the merkle tree

    let mut tree = tree_m.lock();
    let mut updated_note_hashes = updated_note_hashes_m.lock();

    for note in notes.iter() {
        let idx = note.get("index").unwrap().as_u64().unwrap();
        let hash = BigUint::from_str(note.get("hash").unwrap().as_str().unwrap()).unwrap();

        tree.update_leaf_node(&hash, idx);
        updated_note_hashes.insert(idx, hash);
    }
    drop(tree);
}

pub fn restore_withdrawal_update(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    notes_in: &Vec<Value>,
    refund_note: Option<&Value>,
) {
    // ? Upadte the state by adding the note hashes to the merkle tree

    let mut tree = tree_m.lock();
    let mut updated_note_hashes = updated_note_hashes_m.lock();

    let refund_idx = notes_in[0].get("index").unwrap().as_u64().unwrap();
    let refund_note_hash = if refund_note.unwrap().is_null() {
        BigUint::zero()
    } else {
        BigUint::from_str(refund_note.unwrap().get("hash").unwrap().as_str().unwrap()).unwrap()
    };
    tree.update_leaf_node(&refund_note_hash, refund_idx);
    updated_note_hashes.insert(refund_idx, refund_note_hash);

    for note in notes_in.iter().skip(1) {
        let idx = note.get("index").unwrap().as_u64().unwrap();

        tree.update_leaf_node(&BigUint::zero(), idx);
        updated_note_hashes.insert(idx, BigUint::zero());
    }
    drop(tree);
}

fn restore_after_swap_first_fill(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    notes_in: &Vec<Value>,
    refund_note: Option<&Value>,
    swap_note: Note,
    partial_fill_refund_note: Option<Note>,
) {
    let mut tree = tree_m.lock();
    let mut updated_note_hashes = updated_note_hashes_m.lock();

    let refund_idx = notes_in[0].get("index").unwrap().as_u64().unwrap();
    let refund_note_hash = if refund_note.unwrap().is_null() {
        BigUint::zero()
    } else {
        BigUint::from_str(refund_note.unwrap().get("hash").unwrap().as_str().unwrap()).unwrap()
    };

    tree.update_leaf_node(&refund_note_hash, refund_idx);
    updated_note_hashes.insert(refund_idx, refund_note_hash);

    let swap_idx = swap_note.index;
    let swap_hash = swap_note.hash;
    tree.update_leaf_node(&swap_hash, swap_idx);
    updated_note_hashes.insert(swap_idx, swap_hash);

    if partial_fill_refund_note.is_some() {
        //

        let idx: u64 = partial_fill_refund_note.as_ref().unwrap().index;
        let hash = partial_fill_refund_note.unwrap().hash;

        tree.update_leaf_node(&hash, idx);
        updated_note_hashes.insert(idx, hash);
        //
    } else if notes_in.len() > 2 {
        //
        let idx = notes_in[2].get("index").unwrap().as_u64().unwrap();

        tree.update_leaf_node(&BigUint::zero(), idx);
        updated_note_hashes.insert(idx, BigUint::zero());
        //
    }

    for i in 3..notes_in.len() {
        let idx = notes_in[i].get("index").unwrap().as_u64().unwrap();

        tree.update_leaf_node(&BigUint::zero(), idx);
        updated_note_hashes.insert(idx, BigUint::zero());
    }

    drop(tree);
    drop(updated_note_hashes);
}

fn restore_after_swap_later_fills(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    swap_note: Note,
    partial_fill_refund_note: Option<Note>,
) {
    let mut tree = tree_m.lock();
    let mut updated_note_hashes = updated_note_hashes_m.lock();

    // ? Update the state tree
    let swap_idx = swap_note.index;
    let swap_hash = swap_note.hash;
    tree.update_leaf_node(&swap_hash, swap_idx);
    updated_note_hashes.insert(swap_idx, swap_hash);

    if partial_fill_refund_note.is_some() {
        let idx: u64 = partial_fill_refund_note.as_ref().unwrap().index;
        let hash = partial_fill_refund_note.unwrap().hash;

        tree.update_leaf_node(&hash, idx);
        updated_note_hashes.insert(idx, hash);
    }

    drop(updated_note_hashes);
    drop(tree);
}

// * PERP STATE RESTORE FUNCTIONS ================================================================================
fn restore_after_perp_swap_first_fill(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    perpetual_partial_fill_tracker_m: &Arc<Mutex<HashMap<u64, (Option<Note>, u64, u64)>>>,
    order_id: u64,
    notes_in: &Vec<Value>,
    refund_note: Option<&Value>,
    new_pfr_idx: &Option<&Value>,
    new_pfr_hash: &Option<&Value>,
) {
    let mut tree = tree_m.lock();
    let mut updated_note_hashes = updated_note_hashes_m.lock();

    let refund_idx = notes_in[0].get("index").unwrap().as_u64().unwrap();
    let refund_note_hash = if refund_note.unwrap().is_null() {
        BigUint::zero()
    } else {
        BigUint::from_str(refund_note.unwrap().get("hash").unwrap().as_str().unwrap()).unwrap()
    };
    tree.update_leaf_node(&refund_note_hash, refund_idx);
    updated_note_hashes.insert(refund_idx, refund_note_hash);

    if !new_pfr_hash.unwrap().is_null() {
        //
        let idx: u64 = new_pfr_idx.unwrap().as_u64().unwrap();
        let hash = BigUint::from_str(new_pfr_hash.unwrap().as_str().unwrap()).unwrap();

        tree.update_leaf_node(&hash, idx);
        updated_note_hashes.insert(idx, hash);

        // Set this so that the partiall fill fails in case it tries to fill again (to pervent unexpected behaviour)
        let mut pft = perpetual_partial_fill_tracker_m.lock();
        pft.insert(order_id, (None, 69, 69));
        drop(pft);

        //
    } else {
        if notes_in.len() > 1 {
            let idx = notes_in[1].get("index").unwrap().as_u64().unwrap();

            tree.update_leaf_node(&BigUint::zero(), idx);
            updated_note_hashes.insert(idx, BigUint::zero());
        }

        let mut pft = perpetual_partial_fill_tracker_m.lock();
        pft.remove(&order_id);
        drop(pft);
    }

    for i in 2..notes_in.len() {
        let idx = notes_in[i].get("index").unwrap().as_u64().unwrap();

        tree.update_leaf_node(&BigUint::zero(), idx);
        updated_note_hashes.insert(idx, BigUint::zero());
    }

    drop(tree);
    drop(updated_note_hashes);
}

fn restore_after_perp_swap_later_fills(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    perpetual_partial_fill_tracker_m: &Arc<Mutex<HashMap<u64, (Option<Note>, u64, u64)>>>,
    order_id: u64,
    new_pfr_idx: &Option<&Value>,
    new_pfr_hash: &Option<&Value>,
) {
    let mut tree = tree_m.lock();
    let mut updated_note_hashes = updated_note_hashes_m.lock();

    if !new_pfr_hash.unwrap().is_null() {
        let idx: u64 = new_pfr_idx.unwrap().as_u64().unwrap();
        let hash = BigUint::from_str(new_pfr_hash.unwrap().as_str().unwrap()).unwrap();

        tree.update_leaf_node(&hash, idx);
        updated_note_hashes.insert(idx, hash);

        // Set this so that the partiall fill fails in case it tries to fill again (to pervent unexpected behaviour)
        let mut pft = perpetual_partial_fill_tracker_m.lock();
        pft.insert(order_id, (None, 69, 69));
        drop(pft);
    } else {
        let mut pft = perpetual_partial_fill_tracker_m.lock();
        pft.remove(&order_id);
        drop(pft);
    }

    drop(updated_note_hashes);
    drop(tree);
}

fn restore_return_collateral_note(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    ret_collatera_note_idx: &Value,
    ret_collatera_note_hash: &Value,
) {
    let mut tree = tree_m.lock();
    let mut updated_note_hashes = updated_note_hashes_m.lock();

    let idx = ret_collatera_note_idx.as_u64().unwrap();
    let hash = BigUint::from_str(ret_collatera_note_hash.as_str().unwrap()).unwrap();

    tree.update_leaf_node(&hash, idx);
    updated_note_hashes.insert(idx, hash);

    drop(updated_note_hashes);
    drop(tree);
}

// ! UPDATING PERPETUAL STATE ! // ============================================
pub fn restore_perpetual_state(
    perpetual_state_tree_m: &Arc<Mutex<SuperficialTree>>,
    perpetual_updated_position_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    position_index: &Option<&Value>,
    position_hash: Option<&Value>,
) {
    //

    let mut perpetual_state_tree = perpetual_state_tree_m.lock();
    let mut perpetual_updated_position_hashes = perpetual_updated_position_hashes_m.lock();
    if !position_hash.unwrap().is_null() {
        let idx = position_index.unwrap().as_u64().unwrap();
        let hash = BigUint::from_str(position_hash.unwrap().as_str().unwrap()).unwrap();

        perpetual_state_tree.update_leaf_node(&hash, idx);
        perpetual_updated_position_hashes.insert(idx, hash);
    } else {
        let idx = position_index.unwrap().as_u64().unwrap();

        perpetual_state_tree.update_leaf_node(&BigUint::zero(), idx);
        perpetual_updated_position_hashes.insert(idx, BigUint::zero());
    }
    drop(perpetual_state_tree);
    drop(perpetual_updated_position_hashes);
}

// * HELPER FUNCTIONS ============================================================================================

pub fn rebuild_swap_note(transaction: &Map<String, Value>, is_a: bool) -> Note {
    let order_indexes_json = transaction
        .get("indexes")
        .unwrap()
        .get(if is_a { "order_a" } else { "order_b" })
        .unwrap();

    let swap_idx = order_indexes_json
        .get("swap_note_idx")
        .unwrap()
        .as_u64()
        .unwrap();

    let order_json = transaction
        .get("swap_data")
        .unwrap()
        .get(if is_a { "order_a" } else { "order_b" })
        .unwrap();
    let address = EcPoint {
        x: BigInt::from_str(
            order_json
                .get("dest_received_address")
                .unwrap()
                .get("x")
                .unwrap()
                .as_str()
                .unwrap(),
        )
        .unwrap(),
        y: BigInt::from_str(
            order_json
                .get("dest_received_address")
                .unwrap()
                .get("y")
                .unwrap()
                .as_str()
                .unwrap(),
        )
        .unwrap(),
    };

    let dest_received_blinding = BigUint::from_str(
        order_json
            .get("dest_received_blinding")
            .unwrap()
            .as_str()
            .unwrap(),
    )
    .unwrap();

    let spent_amount_y = transaction
        .get("swap_data")
        .unwrap()
        .get(if is_a {
            "spent_amount_b"
        } else {
            "spent_amount_a"
        })
        .unwrap()
        .as_u64()
        .unwrap();

    let fee_taken_x = transaction
        .get("swap_data")
        .unwrap()
        .get(if is_a { "fee_taken_a" } else { "fee_taken_b" })
        .unwrap()
        .as_u64()
        .unwrap();

    let token_received = order_json.get("token_received").unwrap().as_u64().unwrap();

    return Note::new(
        swap_idx,
        address,
        token_received,
        spent_amount_y - fee_taken_x,
        dest_received_blinding,
    );
}

pub fn restore_partial_fill_refund_note(
    transaction: &Map<String, Value>,
    is_a: bool,
) -> Option<Note> {
    let order = transaction
        .get("swap_data")
        .unwrap()
        .get(if is_a { "order_a" } else { "order_b" })
        .unwrap();

    let prev_pfr_note = transaction.get(if is_a {
        "prev_pfr_note_a"
    } else {
        "prev_pfr_note_b"
    });

    let new_partial_refund_amount = if !prev_pfr_note.unwrap().is_null() {
        prev_pfr_note
            .unwrap()
            .get("amount")
            .unwrap()
            .as_u64()
            .unwrap()
            - transaction
                .get("swap_data")
                .unwrap()
                .get(if is_a {
                    "spent_amount_a"
                } else {
                    "spent_amount_b"
                })
                .unwrap()
                .as_u64()
                .unwrap()
    } else {
        order.get("amount_spent").unwrap().as_u64().unwrap()
            - transaction
                .get("swap_data")
                .unwrap()
                .get(if is_a {
                    "spent_amount_a"
                } else {
                    "spent_amount_b"
                })
                .unwrap()
                .as_u64()
                .unwrap()
    };

    if new_partial_refund_amount
        <= DUST_AMOUNT_PER_ASSET[&order
            .get("token_spent")
            .unwrap()
            .as_u64()
            .unwrap()
            .to_string()]
    {
        return None;
    }

    let idx = transaction
        .get("indexes")
        .unwrap()
        .get(if is_a { "order_a" } else { "order_b" })
        .unwrap()
        .get("partial_fill_idx")
        .unwrap()
        .as_u64()
        .unwrap();

    let note0 = &order.get("notes_in").unwrap().as_array().unwrap()[0];

    return Some(Note::new(
        idx,
        EcPoint::new(
            &BigUint::from_str(
                note0
                    .get("address")
                    .unwrap()
                    .get("x")
                    .unwrap()
                    .as_str()
                    .unwrap(),
            )
            .unwrap(),
            &BigUint::from_str(
                note0
                    .get("address")
                    .unwrap()
                    .get("y")
                    .unwrap()
                    .as_str()
                    .unwrap(),
            )
            .unwrap(),
        ),
        order.get("token_spent").unwrap().as_u64().unwrap(),
        new_partial_refund_amount,
        BigUint::from_str(note0.get("blinding").unwrap().as_str().unwrap()).unwrap(),
    ));
}

// fn sum_pub_keys(notes_in_: &Value) -> EcPoint {
//     let notes_in = notes_in_.as_array().unwrap();
//     let mut pub_key_sum: AffinePoint = AffinePoint::identity();
//     for note in notes_in {
//         let point = AffinePoint {
//             x: FieldElement::from_dec_str(
//                 note.get("address")
//                     .unwrap()
//                     .get("x")
//                     .unwrap()
//                     .as_str()
//                     .unwrap(),
//             )
//             .unwrap(),
//             y: FieldElement::from_dec_str(
//                 note.get("address")
//                     .unwrap()
//                     .get("y")
//                     .unwrap()
//                     .as_str()
//                     .unwrap(),
//             )
//             .unwrap(),
//             infinity: false,
//         };
//         pub_key_sum = &pub_key_sum + &point;
//     }
//     return EcPoint::from(&pub_key_sum);
// }

// * UPDATE MARGIN RESTORE FUNCTIONS ================================================================================

pub fn restore_margin_update(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    perpetual_state_tree_m: &Arc<Mutex<SuperficialTree>>,
    perpetual_updated_position_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    transaction: &Map<String, Value>,
) {
    let mut tree = tree_m.lock();
    let mut updated_note_hashes = updated_note_hashes_m.lock();
    let mut perp_tree = perpetual_state_tree_m.lock();
    let mut updated_position_hashes = perpetual_updated_position_hashes_m.lock();

    let pos_index = transaction
        .get("margin_change")
        .unwrap()
        .get("position")
        .unwrap()
        .get("index")
        .unwrap()
        .as_u64()
        .unwrap();
    let new_position_hash = BigUint::from_str(
        transaction
            .get("new_position_hash")
            .unwrap()
            .as_str()
            .unwrap(),
    )
    .unwrap();

    if !transaction
        .get("margin_change")
        .unwrap()
        .get("notes_in")
        .unwrap()
        .is_null()
    {
        // * Adding margin ---- ---- ---- ----

        let notes_in = transaction
            .get("margin_change")
            .unwrap()
            .get("notes_in")
            .unwrap()
            .as_array()
            .unwrap();
        let refund_note = transaction.get("margin_change").unwrap().get("refund_note");

        let refund_idx: u64;
        let refund_note_hash: BigUint;
        if !refund_note.unwrap().is_null() {
            refund_idx = refund_note.unwrap().get("index").unwrap().as_u64().unwrap();
            refund_note_hash =
                BigUint::from_str(refund_note.unwrap().get("hash").unwrap().as_str().unwrap())
                    .unwrap();
        } else {
            refund_idx = notes_in[0].get("index").unwrap().as_u64().unwrap();
            refund_note_hash = BigUint::zero();
        };

        tree.update_leaf_node(&refund_note_hash, refund_idx);
        updated_note_hashes.insert(refund_idx, refund_note_hash);

        for note in notes_in.iter().skip(1) {
            let idx = note.get("index").unwrap().as_u64().unwrap();
            let note_hash = BigUint::from_str(note.get("hash").unwrap().as_str().unwrap()).unwrap();

            tree.update_leaf_node(&note_hash, idx);
            updated_note_hashes.insert(idx, note_hash);
        }
        drop(tree);
        drop(updated_note_hashes);

        perp_tree.update_leaf_node(&new_position_hash, pos_index);
        updated_position_hashes.insert(pos_index, new_position_hash);

        drop(perp_tree);
        drop(updated_position_hashes);
    } else {
        // * Removing margin ---- ---- ---- ----

        let return_collateral_note = rebuild_return_collateral_note(transaction);

        tree.update_leaf_node(&return_collateral_note.hash, return_collateral_note.index);
        updated_note_hashes.insert(return_collateral_note.index, return_collateral_note.hash);

        drop(tree);
        drop(updated_note_hashes);

        perp_tree.update_leaf_node(&new_position_hash, pos_index);
        updated_position_hashes.insert(pos_index, new_position_hash);
    }
}

fn rebuild_return_collateral_note(transaction: &Map<String, Value>) -> Note {
    let index = transaction.get("zero_idx").unwrap().as_u64().unwrap();
    let addr = EcPoint {
        x: BigInt::from_str(
            transaction
                .get("margin_change")
                .unwrap()
                .get("close_order_fields")
                .unwrap()
                .get("dest_received_address")
                .unwrap()
                .get("x")
                .unwrap()
                .as_str()
                .unwrap(),
        )
        .unwrap(),
        y: BigInt::from_str(
            transaction
                .get("margin_change")
                .unwrap()
                .get("close_order_fields")
                .unwrap()
                .get("dest_received_address")
                .unwrap()
                .get("y")
                .unwrap()
                .as_str()
                .unwrap(),
        )
        .unwrap(),
    };
    let token = transaction
        .get("margin_change")
        .unwrap()
        .get("position")
        .unwrap()
        .get("collateral_token")
        .unwrap()
        .as_u64()
        .unwrap();
    let amount = transaction
        .get("margin_change")
        .unwrap()
        .get("margin_change")
        .unwrap()
        .as_i64()
        .unwrap()
        .abs() as u64;
    let blinding = BigUint::from_str(
        transaction
            .get("margin_change")
            .unwrap()
            .get("close_order_fields")
            .unwrap()
            .get("dest_received_blinding")
            .unwrap()
            .as_str()
            .unwrap(),
    )
    .unwrap();

    Note::new(index, addr, token, amount, blinding)
}

pub fn restore_note_split(
    tree_m: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes_m: &Arc<Mutex<HashMap<u64, BigUint>>>,
    transaction: &Map<String, Value>,
) {
    let mut state_tree = tree_m.lock();
    let mut updated_note_hashes = updated_note_hashes_m.lock();

    let notes_in = transaction
        .get("note_split")
        .unwrap()
        .get("notes_in")
        .unwrap()
        .as_array()
        .unwrap();
    let notes_out = transaction
        .get("note_split")
        .unwrap()
        .get("notes_out")
        .unwrap()
        .as_array()
        .unwrap();
    let zero_idxs = transaction
        .get("note_split")
        .unwrap()
        .get("zero_idxs")
        .unwrap()
        .as_array()
        .unwrap();

    if notes_in.len() > notes_out.len() {
        for i in 0..notes_out.len() {
            let idx = notes_in[i].get("index").unwrap().as_u64().unwrap();
            let note_out_hash =
                BigUint::from_str(notes_out[i].get("hash").unwrap().as_str().unwrap()).unwrap();

            state_tree.update_leaf_node(&note_out_hash, idx);
            updated_note_hashes.insert(idx, note_out_hash);
        }

        for i in notes_out.len()..notes_in.len() {
            let idx = notes_in[i].get("index").unwrap().as_u64().unwrap();
            state_tree.update_leaf_node(&BigUint::zero(), idx);
            updated_note_hashes.insert(idx, BigUint::zero());
        }
    } else if notes_in.len() == notes_out.len() {
        for i in 0..notes_out.len() {
            let idx = notes_in[i].get("index").unwrap().as_u64().unwrap();
            let note_out_hash =
                BigUint::from_str(notes_out[i].get("hash").unwrap().as_str().unwrap()).unwrap();

            state_tree.update_leaf_node(&note_out_hash, idx);
            updated_note_hashes.insert(idx, note_out_hash);
        }
    } else {
        for i in 0..notes_in.len() {
            let idx = notes_in[i].get("index").unwrap().as_u64().unwrap();
            let note_out_hash =
                BigUint::from_str(notes_out[i].get("hash").unwrap().as_str().unwrap()).unwrap();

            state_tree.update_leaf_node(&note_out_hash, idx);
            updated_note_hashes.insert(idx, note_out_hash);
        }

        for i in notes_in.len()..notes_out.len() {
            let idx = zero_idxs[i].as_u64().unwrap();
            let note_out_hash =
                BigUint::from_str(notes_out[i].get("hash").unwrap().as_str().unwrap()).unwrap();

            state_tree.update_leaf_node(&note_out_hash, idx);
            updated_note_hashes.insert(idx, note_out_hash);
        }
    }

    drop(state_tree);
    drop(updated_note_hashes);
}
