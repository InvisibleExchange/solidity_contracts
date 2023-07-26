use num_bigint::BigUint;
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
        // & spot_note_info_res - (prev_pfr_note, swap_note_idx, new_pfr_idx)
        spot_note_info_res_a: &Option<(Option<Note>, u64, u64)>,
        spot_note_info_res_b: &Option<(Option<Note>, u64, u64)>,
        updated_tab_hash_a: &Option<BigUint>,
        updated_tab_hash_b: &Option<BigUint>,
    ) -> serde_json::map::Map<String, Value> {
        let mut json_map = serde_json::map::Map::new();

        let swap_json1 = serde_json::to_value(&self.swap).unwrap();

        // TODO:
        let is_tab_order_a = spot_note_info_res_a.is_none();
        let is_tab_order_b = spot_note_info_res_b.is_none();

        // ? If this is a non-tab order get the relevant info for the cairo input
        let mut indexes_a = None;
        if let Some((prev_pfr, swap_idx, pfr_idx)) = spot_note_info_res_a {
            let pfr_note_a_json = serde_json::to_value(prev_pfr).unwrap();
            json_map.insert(String::from("prev_pfr_note_a"), pfr_note_a_json);

            indexes_a = Some(json!({
                "swap_note_idx": swap_idx,
                "partial_fill_idx": pfr_idx,
            }));
        }
        let mut indexes_b = None;
        if let Some((prev_pfr, swap_idx, pfr_idx)) = spot_note_info_res_b {
            let pfr_note_b_json = serde_json::to_value(prev_pfr).unwrap();
            json_map.insert(String::from("prev_pfr_note_b"), pfr_note_b_json);

            indexes_b = Some(json!({
                "swap_note_idx": swap_idx,
                "partial_fill_idx": pfr_idx,
            }));
        }
        let indexes_json = json!({
            "order_a": indexes_a,
            "order_b": indexes_b
        });

        json_map.insert(
            String::from("transaction_type"),
            serde_json::to_value(&"swap").unwrap(),
        );
        json_map.insert(
            String::from("is_tab_order_a"),
            serde_json::to_value(&is_tab_order_a).unwrap(),
        );
        json_map.insert(
            String::from("is_tab_order_b"),
            serde_json::to_value(&is_tab_order_b).unwrap(),
        );
        json_map.insert(
            String::from("updated_tab_hash_a"),
            serde_json::to_value(&updated_tab_hash_a.as_ref().map(|h| h.to_string())).unwrap(),
        );
        json_map.insert(
            String::from("updated_tab_hash_b"),
            serde_json::to_value(&updated_tab_hash_b.as_ref().map(|h| h.to_string())).unwrap(),
        );
        json_map.insert(String::from("swap_data"), swap_json1);
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
