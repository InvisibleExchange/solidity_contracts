use std::sync::Arc;

use num_bigint::BigUint;
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
    add_only: bool,
    prev_order_tab: &Option<OrderTab>, // & prev_order_tab in case of modify and new_order_tab in case of open
    new_order_tab: &OrderTab,
    signature: &Signature,
) {
    let mut json_map = serde_json::map::Map::new();
    json_map.insert(
        String::from("transaction_type"),
        serde_json::to_value(&"open_order_tab").unwrap(),
    );
    json_map.insert(
        String::from("is_onchain_interaction"),
        serde_json::to_value(&false).unwrap(),
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
        String::from("add_only"),
        serde_json::to_value(&add_only).unwrap(),
    );
    json_map.insert(
        String::from("order_tab"),
        serde_json::to_value(if add_only {
            prev_order_tab.as_ref().unwrap()
        } else {
            &new_order_tab
        })
        .unwrap(),
    );
    json_map.insert(
        String::from("updated_tab_hash"),
        serde_json::to_value(&new_order_tab.hash.to_string()).unwrap(),
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
    base_amount_change: u64,
    quote_amount_change: u64,
    base_return_note: &Note,
    quote_return_note: &Note,
    base_close_order_fields: &CloseOrderFields,
    quote_close_order_fields: &CloseOrderFields,
    prev_order_tab: &OrderTab,
    updated_order_tab: &Option<OrderTab>,
    signature: &Signature,
) {
    let mut json_map = serde_json::map::Map::new();
    json_map.insert(
        String::from("transaction_type"),
        serde_json::to_value(&"close_order_tab").unwrap(),
    );
    json_map.insert(
        String::from("is_onchain_interaction"),
        serde_json::to_value(&false).unwrap(),
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
        String::from("base_amount_change"),
        serde_json::to_value(&base_amount_change).unwrap(),
    );
    json_map.insert(
        String::from("quote_amount_change"),
        serde_json::to_value(&quote_amount_change).unwrap(),
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
        serde_json::to_value(&prev_order_tab).unwrap(),
    );
    let updated_tab_hash = if updated_order_tab.is_some() {
        updated_order_tab.as_ref().unwrap().hash.to_string()
    } else {
        "0".to_string()
    };
    json_map.insert(
        String::from("updated_tab_hash"),
        serde_json::to_value(&updated_tab_hash).unwrap(),
    );
    json_map.insert(
        String::from("signature"),
        serde_json::to_value(&signature).unwrap(),
    );

    let mut swap_output_json = swap_output_json_m.lock();
    swap_output_json.push(json_map);
    drop(swap_output_json);
}

// * ONCHAIN INTERACTIONS ===========================================================================
// * ================================================================================================

// * ONCHAIN OPEN ORDER TAB JSON OUTPUT
pub fn onchain_open_tab_json_output(
    swap_output_json_m: &Arc<Mutex<Vec<serde_json::Map<String, Value>>>>,
    order_tab: &OrderTab,
    vlp_close_order_fields: &CloseOrderFields,
    vlp_note: &Note,
    signature: &Signature,
) {
    let mut json_map = serde_json::map::Map::new();
    json_map.insert(
        String::from("transaction_type"),
        serde_json::to_value(&"open_order_tab").unwrap(),
    );
    json_map.insert(
        String::from("is_onchain_interaction"),
        serde_json::to_value(&true).unwrap(),
    );
    json_map.insert(
        String::from("order_tab"),
        serde_json::to_value(order_tab).unwrap(),
    );
    json_map.insert(
        String::from("vlp_close_order_fields"),
        serde_json::to_value(&vlp_close_order_fields).unwrap(),
    );
    json_map.insert(
        String::from("vlp_token"),
        serde_json::to_value(&vlp_note.token).unwrap(),
    );
    json_map.insert(
        String::from("vlp_note_idx"),
        serde_json::to_value(&vlp_note.index).unwrap(),
    );
    json_map.insert(
        String::from("vlp_note_hash"),
        serde_json::to_value(&vlp_note.hash.to_string()).unwrap(),
    );
    json_map.insert(
        String::from("signature"),
        serde_json::to_value(&signature).unwrap(),
    );

    let mut swap_output_json = swap_output_json_m.lock();
    swap_output_json.push(json_map);
    drop(swap_output_json);
}

// * ONCHAIN OPEN ORDER TAB JSON OUTPUT
pub fn onchain_add_liquidity_json_output(
    swap_output_json_m: &Arc<Mutex<Vec<serde_json::Map<String, Value>>>>,
    prev_order_tab: &OrderTab,
    base_notes_in: &Vec<Note>,
    base_refund_note: &Option<Note>,
    quote_notes_in: &Vec<Note>,
    quote_refund_note: &Option<Note>,
    new_order_tab_hash: &BigUint,
    vlp_close_order_fields: &CloseOrderFields,
    vlp_note: &Note,
    signature: &Signature,
) {
    let mut json_map = serde_json::map::Map::new();
    json_map.insert(
        String::from("transaction_type"),
        serde_json::to_value(&"add_liquidity_to_order_tab").unwrap(),
    );
    json_map.insert(
        String::from("is_smart_contract_tab"),
        serde_json::to_value(&true).unwrap(),
    );
    json_map.insert(
        String::from("prev_order_tab"),
        serde_json::to_value(prev_order_tab).unwrap(),
    );
    json_map.insert(
        String::from("new_order_tab_hash"),
        serde_json::to_value(&new_order_tab_hash.to_string()).unwrap(),
    );
    json_map.insert(
        String::from("vlp_close_order_fields"),
        serde_json::to_value(&vlp_close_order_fields).unwrap(),
    );
    //
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
    //
    json_map.insert(
        String::from("vlp_note_idx"),
        serde_json::to_value(&vlp_note.index).unwrap(),
    );
    json_map.insert(
        String::from("vlp_note_hash"),
        serde_json::to_value(&vlp_note.hash.to_string()).unwrap(),
    );
    json_map.insert(
        String::from("signature"),
        serde_json::to_value(&signature).unwrap(),
    );

    let mut swap_output_json = swap_output_json_m.lock();
    swap_output_json.push(json_map);
    drop(swap_output_json);
}

// repeated GrpcNote vlp_notes_in = 1;
// uint64 index_price = 2;
// uint32 slippage = 3; // 100 = 1%
// GrpcCloseOrderFields base_close_order_fields = 4;
// GrpcCloseOrderFields quote_close_order_fields = 5;
// // as well as tab pub key
// // off chain fields
// GrpcOrderTab order_tab = 6;
// uint64 base_return_amount = 7;
// Signature signature = 9;

// * ONCHAIN OPEN ORDER TAB JSON OUTPUT
pub fn onchain_remove_liquidity_json_output(
    swap_output_json_m: &Arc<Mutex<Vec<serde_json::Map<String, Value>>>>,
    //
    vlp_notes_in: &Vec<Note>,
    user_index_price: u64,
    slippage: u32,
    base_close_order_fields: &CloseOrderFields,
    quote_close_order_fields: &CloseOrderFields,
    //
    base_return_amount: u64,
    index_price: u64,
    prev_order_tab: &OrderTab,
    new_order_tab: &Option<OrderTab>,
    base_return_note: &Note,
    quote_return_note: &Note,
    signature: &Signature,
) {
    let mut json_map = serde_json::map::Map::new();
    json_map.insert(
        String::from("transaction_type"),
        serde_json::to_value(&"add_liquidity_to_order_tab").unwrap(),
    );
    json_map.insert(
        String::from("is_onchain_interaction"),
        serde_json::to_value(&true).unwrap(),
    );
    //
    json_map.insert(
        String::from("vlp_notes_in"),
        serde_json::to_value(&vlp_notes_in).unwrap(),
    );
    json_map.insert(
        String::from("user_index_price"),
        serde_json::to_value(&user_index_price).unwrap(),
    );
    json_map.insert(
        String::from("slippage"),
        serde_json::to_value(&slippage).unwrap(),
    );
    json_map.insert(
        String::from("base_close_order_fields"),
        serde_json::to_value(&base_close_order_fields).unwrap(),
    );
    json_map.insert(
        String::from("quote_close_order_fields"),
        serde_json::to_value(&quote_close_order_fields).unwrap(),
    );
    //
    json_map.insert(
        String::from("base_return_amount"),
        serde_json::to_value(&base_return_amount).unwrap(),
    );
    json_map.insert(
        String::from("index_price"),
        serde_json::to_value(&index_price).unwrap(),
    );
    json_map.insert(
        String::from("signature"),
        serde_json::to_value(&signature).unwrap(),
    );
    //
    json_map.insert(
        String::from("prev_order_tab"),
        serde_json::to_value(prev_order_tab).unwrap(),
    );
    let new_order_tab_hash = new_order_tab.as_ref().map(|tab| tab.hash.to_string());
    json_map.insert(
        String::from("new_order_tab_hash"),
        serde_json::to_value(&new_order_tab_hash).unwrap(),
    );
    json_map.insert(
        String::from("base_return_note_index"),
        serde_json::to_value(base_return_note.index).unwrap(),
    );
    json_map.insert(
        String::from("base_return_note_hash"),
        serde_json::to_value(&base_return_note.hash.to_string()).unwrap(),
    );
    json_map.insert(
        String::from("quote_return_note_index"),
        serde_json::to_value(quote_return_note.index).unwrap(),
    );
    json_map.insert(
        String::from("quote_return_note_hash"),
        serde_json::to_value(&quote_return_note.hash.to_string()).unwrap(),
    );

    let mut swap_output_json = swap_output_json_m.lock();
    swap_output_json.push(json_map);
    drop(swap_output_json);
}
