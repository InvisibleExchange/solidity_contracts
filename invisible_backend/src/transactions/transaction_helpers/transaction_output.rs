use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::utils::notes::Note;

use super::super::swap::Swap;

pub struct TransactionOutptut<'a> {
    pub swap: &'a Swap,
    // pub order_a: &'a LimitOrder,
    // pub order_b: &'a LimitOrder,
}

impl TransactionOutptut<'_> {
    pub fn new<'a>(swap: &'a Swap) -> TransactionOutptut<'a> {
        TransactionOutptut { swap }
    }

    pub fn wrap_output(
        &self,
        prev_pfr_note_a: &Option<Note>,
        prev_pfr_note_b: &Option<Note>,
        swap_note_idx_a: u64,
        swap_note_idx_b: u64,
        new_pfr_idx_a: u64,
        new_pfr_idx_b: u64,
    ) -> serde_json::map::Map<String, Value> {
        let swap_json1 = serde_json::to_value(&self.swap).unwrap();
        let pfr_note_a_json = serde_json::to_value(prev_pfr_note_a).unwrap();
        let pfr_note_b_json2 = serde_json::to_value(prev_pfr_note_b).unwrap();

        let indexes_json = json!({
            "order_a": {
                "swap_note_idx": swap_note_idx_a,
                "partial_fill_idx": new_pfr_idx_a,
            },
            "order_b": {
                "swap_note_idx": swap_note_idx_b,
                "partial_fill_idx": new_pfr_idx_b,
            },
        });

        let mut json_map = serde_json::map::Map::new();

        json_map.insert(
            String::from("transaction_type"),
            serde_json::to_value(&"swap").unwrap(),
        );
        json_map.insert(String::from("swap_data"), swap_json1);
        json_map.insert(String::from("prev_pfr_note_a"), pfr_note_a_json);
        json_map.insert(String::from("prev_pfr_note_b"), pfr_note_b_json2);
        json_map.insert(String::from("indexes"), indexes_json);

        return json_map;
    }
}

#[derive(Serialize, Deserialize, Debug)]
pub struct FillInfo {
    pub user_id_a: String,
    pub user_id_b: String,
    pub amount: u64,
    pub price: u64,
    pub timestamp: u64,
    pub base_token: u64,
    pub quote_token: u64,
    pub is_buy: bool,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct PerpFillInfo {
    pub user_id_a: String,
    pub user_id_b: String,
    pub amount: u64,
    pub price: u64,
    pub timestamp: u64,
    pub synthetic_token: u64,
    pub is_buy: bool,
}
