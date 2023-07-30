use std::sync::Arc;

use parking_lot::Mutex;
use serde_json::Value;

use crate::{
    perpetual::perp_order::CloseOrderFields,
    utils::{crypto_utils::Signature, notes::Note},
};

use super::OrderTab;

// * OPEN ORDER TAB JSON OUTPUT
pub fn open_tab_json_output(
    swap_output_json_m: &Arc<Mutex<Vec<serde_json::Map<String, Value>>>>,
    base_notes_in: &Vec<Note>,
    base_refund_note: &Option<Note>,
    quote_notes_in: &Vec<Note>,
    quote_refund_note: &Option<Note>,
    order_tab: &OrderTab,
    signature: &Signature,
) {
    let mut json_map = serde_json::map::Map::new();
    json_map.insert(
        String::from("transaction_type"),
        serde_json::to_value(&"open_order_tab").unwrap(),
    );
    json_map.insert(
        String::from("base_notes_in"),
        serde_json::to_value(&base_notes_in).unwrap(),
    );
    json_map.insert(
        String::from("base_refund_note"),
        serde_json::to_value(&base_refund_note).unwrap(),
    );
    json_map.insert(
        String::from("quote_notes_in"),
        serde_json::to_value(&quote_notes_in).unwrap(),
    );
    json_map.insert(
        String::from("quote_refund_note"),
        serde_json::to_value(&quote_refund_note).unwrap(),
    );
    json_map.insert(
        String::from("order_tab"),
        serde_json::to_value(&order_tab).unwrap(),
    );
    json_map.insert(
        String::from("signature"),
        serde_json::to_value(&signature).unwrap(),
    );

    let mut swap_output_json = swap_output_json_m.lock();
    swap_output_json.push(json_map);
    drop(swap_output_json);
}

// * CLOSE ORDER TAB JSON OUTPUT
pub fn close_tab_json_output(
    swap_output_json_m: &Arc<Mutex<Vec<serde_json::Map<String, Value>>>>,
    base_return_note: &Note,
    quote_return_note: &Note,
    base_close_order_fields: &CloseOrderFields,
    quote_close_order_fields: &CloseOrderFields,
    order_tab: &OrderTab,
    signature: &Signature,
) {
    let mut json_map = serde_json::map::Map::new();
    json_map.insert(
        String::from("transaction_type"),
        serde_json::to_value(&"close_order_tab").unwrap(),
    );
    json_map.insert(
        String::from("base_return_note_idx"),
        serde_json::to_value(&base_return_note.index).unwrap(),
    );
    json_map.insert(
        String::from("base_return_note_hash"),
        serde_json::to_value(&base_return_note.hash.to_string()).unwrap(),
    );
    json_map.insert(
        String::from("quote_return_note_idx"),
        serde_json::to_value(&quote_return_note.index).unwrap(),
    );
    json_map.insert(
        String::from("quote_return_note_hash"),
        serde_json::to_value(&quote_return_note.hash.to_string()).unwrap(),
    );
    json_map.insert(
        String::from("base_close_order_fields"),
        serde_json::to_value(&base_close_order_fields).unwrap(),
    );
    json_map.insert(
        String::from("quote_close_order_fields"),
        serde_json::to_value(&quote_close_order_fields).unwrap(),
    );
    json_map.insert(
        String::from("order_tab"),
        serde_json::to_value(&order_tab).unwrap(),
    );
    json_map.insert(
        String::from("signature"),
        serde_json::to_value(&signature).unwrap(),
    );

    let mut swap_output_json = swap_output_json_m.lock();
    swap_output_json.push(json_map);
    drop(swap_output_json);
}

// * MODIFY ORDER TAB JSON OUTPUT
pub fn modifiy_tab_json_output(
    swap_output_json_m: &Arc<Mutex<Vec<serde_json::Map<String, Value>>>>,
    is_add: bool,
    prev_order_tab: &OrderTab,
    base_notes_in: &Vec<Note>,
    base_refund_note: &Option<Note>,
    quote_notes_in: &Vec<Note>,
    quote_refund_note: &Option<Note>,
    base_close_order_fields: &Option<CloseOrderFields>,
    quote_close_order_fields: &Option<CloseOrderFields>,
    base_return_note: &Option<Note>,
    quote_return_note: &Option<Note>,
    order_tab: &OrderTab,
    signature: &Signature,
) {
    let mut json_map = serde_json::map::Map::new();
    json_map.insert(
        String::from("transaction_type"),
        serde_json::to_value(&"open_order_tab").unwrap(),
    );
    json_map.insert(
        String::from("is_add"),
        serde_json::to_value(&is_add).unwrap(),
    );
    json_map.insert(
        String::from("prev_order_tab"),
        serde_json::to_value(&prev_order_tab).unwrap(),
    );
    json_map.insert(
        String::from("new_tab_hash"),
        serde_json::to_value(&order_tab.hash.to_string()).unwrap(),
    );
    // if is_add
    json_map.insert(
        String::from("base_notes_in"),
        serde_json::to_value(&base_notes_in).unwrap(),
    );
    json_map.insert(
        String::from("base_refund_note"),
        serde_json::to_value(&base_refund_note).unwrap(),
    );
    json_map.insert(
        String::from("quote_notes_in"),
        serde_json::to_value(&quote_notes_in).unwrap(),
    );
    json_map.insert(
        String::from("quote_refund_note"),
        serde_json::to_value(&quote_refund_note).unwrap(),
    );
    // if not is_add
    json_map.insert(
        String::from("base_close_order_fields"),
        serde_json::to_value(&base_close_order_fields).unwrap(),
    );
    json_map.insert(
        String::from("quote_close_order_fields"),
        serde_json::to_value(&quote_close_order_fields).unwrap(),
    );
    let mut base_return_note_idx = 0;
    let mut quote_return_note_idx = 0;
    let mut base_return_note_hash = None;
    let mut quote_return_note_hash = None;
    if !is_add {
        base_return_note_idx = base_return_note.as_ref().unwrap().index;
        base_return_note_hash = Some(base_return_note.as_ref().unwrap().hash.to_string());
        quote_return_note_idx = quote_return_note.as_ref().unwrap().index;
        quote_return_note_hash = Some(quote_return_note.as_ref().unwrap().hash.to_string());
    }
    json_map.insert(
        String::from("base_return_note_idx"),
        serde_json::to_value(&base_return_note_idx).unwrap(),
    );
    json_map.insert(
        String::from("base_return_note_hash"),
        serde_json::to_value(&base_return_note_hash).unwrap(),
    );
    json_map.insert(
        String::from("quote_return_note_idx"),
        serde_json::to_value(&quote_return_note_idx).unwrap(),
    );
    json_map.insert(
        String::from("quote_return_note_hash"),
        serde_json::to_value(&quote_return_note_hash).unwrap(),
    );
    // signature
    json_map.insert(
        String::from("signature"),
        serde_json::to_value(&signature).unwrap(),
    );

    let mut swap_output_json = swap_output_json_m.lock();
    swap_output_json.push(json_map);
    drop(swap_output_json);
}
