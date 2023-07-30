use std::{collections::HashMap, sync::Arc};

use num_bigint::BigUint;
use num_traits::Zero;
use parking_lot::Mutex;

use crate::{trees::superficial_tree::SuperficialTree, utils::notes::Note};

use super::OrderTab;

// * Open Tab State Updates  -----------------------------------------------------------------------
pub fn open_tab_state_updates(
    state_tree: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes: &Arc<Mutex<HashMap<u64, BigUint>>>,
    order_tabs_state_tree: &Arc<Mutex<SuperficialTree>>,
    updated_tab_hashes: &Arc<Mutex<HashMap<u32, BigUint>>>,
    order_tab: OrderTab,
    base_notes_in: Vec<Note>,
    quote_notes_in: Vec<Note>,
    base_refund_note: Option<Note>,
    quote_refund_note: Option<Note>,
) {
    // ? Remove the notes from the state tree and add the refund notes ------------------
    let mut state_tree_m = state_tree.lock();
    let mut updated_note_hashes_m = updated_note_hashes.lock();
    for note in base_notes_in.into_iter() {
        state_tree_m.update_leaf_node(&BigUint::zero(), note.index);
        updated_note_hashes_m.insert(note.index, note.hash);
    }
    for note in quote_notes_in.into_iter() {
        state_tree_m.update_leaf_node(&BigUint::zero(), note.index);
        updated_note_hashes_m.insert(note.index, note.hash);
    }
    if let Some(note) = base_refund_note {
        state_tree_m.update_leaf_node(&note.hash, note.index);
        updated_note_hashes_m.insert(note.index, note.hash);
    }
    if let Some(note) = quote_refund_note {
        state_tree_m.update_leaf_node(&note.hash, note.index);
        updated_note_hashes_m.insert(note.index, note.hash);
    }
    drop(state_tree_m);
    drop(updated_note_hashes_m);

    // ? add it to the order tabs state
    let mut tabs_tree = order_tabs_state_tree.lock();
    let mut updated_tab_hashes_m = updated_tab_hashes.lock();

    tabs_tree.update_leaf_node(&order_tab.hash, order_tab.tab_idx as u64);
    updated_tab_hashes_m.insert(order_tab.tab_idx, order_tab.hash);

    drop(tabs_tree);
    drop(updated_tab_hashes_m);
}

// * Close Tab State Updates -----------------------------------------------------------------------
pub fn close_tab_state_updates(
    state_tree: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes: &Arc<Mutex<HashMap<u64, BigUint>>>,
    order_tabs_state_tree: &Arc<Mutex<SuperficialTree>>,
    updated_tab_hashes: &Arc<Mutex<HashMap<u32, BigUint>>>,
    order_tab: &OrderTab,
    base_return_note: Note,
    quote_return_note: Note,
) {
    // ? remove the tab from the state
    let mut tabs_tree = order_tabs_state_tree.lock();
    let mut updated_tab_hashes_m = updated_tab_hashes.lock();

    tabs_tree.update_leaf_node(&BigUint::zero(), order_tab.tab_idx as u64);
    updated_tab_hashes_m.insert(order_tab.tab_idx, BigUint::zero());

    drop(tabs_tree);
    drop(updated_tab_hashes_m);

    // ? add the return notes to the state
    let mut state_tree_m = state_tree.lock();
    let mut updated_note_hashes_m = updated_note_hashes.lock();

    state_tree_m.update_leaf_node(&base_return_note.hash, base_return_note.index);
    updated_note_hashes_m.insert(base_return_note.index, base_return_note.hash);

    state_tree_m.update_leaf_node(&quote_return_note.hash, quote_return_note.index);
    updated_note_hashes_m.insert(quote_return_note.index, quote_return_note.hash);

    drop(state_tree_m);
    drop(updated_note_hashes_m);
}

// * Open Tab State Updates  -----------------------------------------------------------------------
pub fn modify_tab_state_updates(
    state_tree: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes: &Arc<Mutex<HashMap<u64, BigUint>>>,
    order_tabs_state_tree: &Arc<Mutex<SuperficialTree>>,
    updated_tab_hashes: &Arc<Mutex<HashMap<u32, BigUint>>>,
    is_add: bool,
    order_tab: OrderTab,
    // if is_add is true, then the notes are removed from the state tree
    base_notes_in: Vec<Note>,
    quote_notes_in: Vec<Note>,
    base_refund_note: Option<Note>,
    quote_refund_note: Option<Note>,
    // if is_add is false, then the return notes are added to the state tree
    base_return_note: Option<Note>,
    quote_return_note: Option<Note>,
) {
    let mut state_tree_m = state_tree.lock();
    let mut updated_note_hashes_m = updated_note_hashes.lock();
    let mut tabs_tree = order_tabs_state_tree.lock();
    let mut updated_tab_hashes_m = updated_tab_hashes.lock();

    if is_add {
        // ? Remove the notes from the state tree and add the refund notes ------------------
        for note in base_notes_in.into_iter() {
            state_tree_m.update_leaf_node(&BigUint::zero(), note.index);
            updated_note_hashes_m.insert(note.index, note.hash);
        }
        for note in quote_notes_in.into_iter() {
            state_tree_m.update_leaf_node(&BigUint::zero(), note.index);
            updated_note_hashes_m.insert(note.index, note.hash);
        }
        if let Some(note) = base_refund_note {
            state_tree_m.update_leaf_node(&note.hash, note.index);
            updated_note_hashes_m.insert(note.index, note.hash);
        }
        if let Some(note) = quote_refund_note {
            state_tree_m.update_leaf_node(&note.hash, note.index);
            updated_note_hashes_m.insert(note.index, note.hash);
        }
    } else {
        // ? add the return notes to the state
        let base_return_note = base_return_note.unwrap();
        state_tree_m.update_leaf_node(&base_return_note.hash, base_return_note.index);
        updated_note_hashes_m.insert(base_return_note.index, base_return_note.hash);

        let quote_return_note = quote_return_note.unwrap();
        state_tree_m.update_leaf_node(&quote_return_note.hash, quote_return_note.index);
        updated_note_hashes_m.insert(quote_return_note.index, quote_return_note.hash);
    }

    // ? update the order tabs state
    tabs_tree.update_leaf_node(&order_tab.hash, order_tab.tab_idx as u64);
    updated_tab_hashes_m.insert(order_tab.tab_idx, order_tab.hash);

    drop(state_tree_m);
    drop(updated_note_hashes_m);

    drop(tabs_tree);
    drop(updated_tab_hashes_m);
}
