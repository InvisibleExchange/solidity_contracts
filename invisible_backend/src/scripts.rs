//

//

use std::collections::HashMap;

use invisible_backend::{perpetual::VALID_COLLATERAL_TOKENS, utils::storage::MainStorage};

pub fn _calculate_fees() {
    let storage = MainStorage::new();

    let swap_output_json = storage.read_storage(0);

    let mut fee_map: HashMap<u64, u64> = HashMap::new();

    for transaction in swap_output_json {
        let transaction_type = transaction
            .get("transaction_type")
            .unwrap()
            .as_str()
            .unwrap();
        match transaction_type {
            "swap" => {
                let fee_taken_a = transaction
                    .get("swap_data")
                    .unwrap()
                    .get("fee_taken_a")
                    .unwrap()
                    .as_u64()
                    .unwrap();
                let fee_taken_b = transaction
                    .get("swap_data")
                    .unwrap()
                    .get("fee_taken_b")
                    .unwrap()
                    .as_u64()
                    .unwrap();
                let token_received_a = transaction
                    .get("swap_data")
                    .unwrap()
                    .get("order_a")
                    .unwrap()
                    .get("token_received")
                    .unwrap()
                    .as_u64()
                    .unwrap();
                let token_received_b = transaction
                    .get("swap_data")
                    .unwrap()
                    .get("order_b")
                    .unwrap()
                    .get("token_received")
                    .unwrap()
                    .as_u64()
                    .unwrap();

                let current_fee_a = fee_map.get(&token_received_a).unwrap_or(&0);
                let current_fee_b = fee_map.get(&token_received_b).unwrap_or(&0);

                let new_fee_a = current_fee_a + fee_taken_a;
                let new_fee_b = current_fee_b + fee_taken_b;

                fee_map.insert(token_received_a, new_fee_a);
                fee_map.insert(token_received_b, new_fee_b);
            }
            "perpetual_swap" => {
                let fee_taken_a = transaction
                    .get("swap_data")
                    .unwrap()
                    .get("fee_taken_a")
                    .unwrap()
                    .as_u64()
                    .unwrap();
                let fee_taken_b = transaction
                    .get("swap_data")
                    .unwrap()
                    .get("fee_taken_b")
                    .unwrap()
                    .as_u64()
                    .unwrap();

                let current_fee = fee_map.get(&VALID_COLLATERAL_TOKENS[0]).unwrap_or(&0);

                let new_fee = current_fee + fee_taken_a + fee_taken_b;
                fee_map.insert(VALID_COLLATERAL_TOKENS[0], new_fee);
            }
            _ => {}
        }
    }

    println!("fee map: {:?}", fee_map);
}
