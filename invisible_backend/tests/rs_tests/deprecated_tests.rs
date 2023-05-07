// use core::panic;
// use std::{collections::HashMap, fmt::Debug, str::FromStr};

// use invisible_backend::perpetual::{perp_order::PerpOrder, OrderSide, PositionEffectType};
// use invisible_backend::transactions::{
//     deposit::Deposit,
//     limit_order::LimitOrder,
//     swap::Swap,
//     transaction_batch::{self, OracleUpdate},
//     withdrawal::{self, Withdrawal},
// };
// use invisible_backend::utils::notes::Note;
// use invisible_backend::utils::users::biguint_to_32vec;
// use num_bigint::{BigInt, BigUint};
// use num_traits::{One, Zero};

// use invisible_backend::starkware_crypto::{EcPoint, Signature};

// use invisible_backend::{
//     perpetual::{
//         perp_order,
//         perp_swap::{self, PerpSwap},
//         perp_swap_outptut::PerpSwapOutptut,
//     },
//     transactions::transaction_batch::{FundingInfo, TransactionBatch},
//     trees::Tree,
// };

// use std::path::Path;

// #[test]
// fn test_perpetual_order_types() {
//     let (batch_init_tree, note, refund_note) = build_dummy_init_state_tree();

//     let perpetual_init_tree = Tree::new(3);

//     let mut transaction_batch = TransactionBatch::new(batch_init_tree, perpetual_init_tree);

//     // & OPEN ORDER SWAPS ==================================================================================
//     // & ===================================================================================================

//     let (perp_order1, sig1, perp_order2, sig2, perp_order3, sig3) = get_dummy_open_orders();

//     let perp_swap1 = PerpSwap::new(
//         perp_order1.order_id,
//         perp_order2.order_id,
//         Some(sig1.clone()),
//         Some(sig2),
//         20000 * 10_u64.pow(6),
//         20 * 10_u64.pow(6),
//         2 * 10_u64.pow(6),
//         2 * 10_u64.pow(6) / 2,
//     );

//     let perp_swap2 = PerpSwap::new(
//         perp_order1.order_id,
//         perp_order3.order_id,
//         Some(sig1.clone()),
//         Some(sig3),
//         10000 * 10_u64.pow(6),
//         10 * 10_u64.pow(6),
//         1 * 10_u64.pow(6),
//         1 * 10_u64.pow(6) / 2,
//     );

//     transaction_batch.submit_perpetual_order(perp_order1);
//     transaction_batch.submit_perpetual_order(perp_order2);
//     transaction_batch.submit_perpetual_order(perp_order3);

//     transaction_batch.execute_perpetual_transaction(perp_swap1);
//     transaction_batch.execute_perpetual_transaction(perp_swap2);

//     // println!(
//     //     "perp state tree leaves {:#?}",
//     //     transaction_batch.perpetual_state_tree.leaf_nodes
//     // );
//     // println!("==============\n\n");

//     //

//     // & INCREASE POSITION SIZE SWAPS ==================================================================================
//     // & ===================================================================================================

//     let (perp_order4, sig4, perp_order5, sig5, perp_order6, sig6) =
//         get_dummy_increase_size_orders(&transaction_batch);

//     let perp_swap3 = PerpSwap::new(
//         perp_order4.order_id,
//         perp_order5.order_id,
//         Some(sig4.clone()),
//         Some(sig5),
//         5000 * 10_u64.pow(6),
//         5 * 10_u64.pow(6),
//         1 * 10_u64.pow(6) / 2,
//         1 * 10_u64.pow(6) / 4,
//     );

//     let perp_swap4 = PerpSwap::new(
//         perp_order4.order_id,
//         perp_order6.order_id,
//         Some(sig4.clone()),
//         Some(sig6),
//         5000 * 10_u64.pow(6),
//         5 * 10_u64.pow(6),
//         1 * 10_u64.pow(6) / 2,
//         1 * 10_u64.pow(6) / 4,
//     );

//     transaction_batch.submit_perpetual_order(perp_order4);
//     transaction_batch.submit_perpetual_order(perp_order5);
//     transaction_batch.submit_perpetual_order(perp_order6);

//     transaction_batch.execute_perpetual_transaction(perp_swap3);
//     transaction_batch.execute_perpetual_transaction(perp_swap4);

//     // println!(
//     //     "perp state tree leaves {:#?}",
//     //     transaction_batch.perpetual_state_tree.leaf_nodes
//     // );
//     // println!("==============\n\n");

//     //

//     // & DECREASE POSITION SIZE SWAPS ==================================================================================
//     // & ===================================================================================================

//     let (perp_order7, sig7, perp_order8, sig8, perp_order9, sig9) =
//         get_dummy_reduce_size_orders(&transaction_batch);

//     let perp_swap5 = PerpSwap::new(
//         perp_order8.order_id,
//         perp_order7.order_id,
//         Some(sig8),
//         Some(sig7.clone()),
//         5000 * 10_u64.pow(6),
//         5 * 10_u64.pow(6),
//         1 * 10_u64.pow(6) / 2,
//         1 * 10_u64.pow(6) / 4,
//     );

//     let perp_swap6 = PerpSwap::new(
//         perp_order9.order_id,
//         perp_order7.order_id,
//         Some(sig9),
//         Some(sig7.clone()),
//         5000 * 10_u64.pow(6),
//         5 * 10_u64.pow(6),
//         1 * 10_u64.pow(6) / 2,
//         1 * 10_u64.pow(6) / 4,
//     );

//     transaction_batch.submit_perpetual_order(perp_order7);
//     transaction_batch.submit_perpetual_order(perp_order8);
//     transaction_batch.submit_perpetual_order(perp_order9);

//     transaction_batch.execute_perpetual_transaction(perp_swap5);
//     transaction_batch.execute_perpetual_transaction(perp_swap6);

//     println!(
//         "perp state tree leaves {:#?}",
//         transaction_batch
//             .perpetual_state_tree
//             .lock()
//             .unwrap()
//             .leaf_nodes
//     );
//     println!("==============\n\n");

//     //

//     // & CLOSE POSITION SWAPS ==================================================================================
//     // & ===================================================================================================
//     //

//     let (perp_order10, sig10, perp_order11, sig11, perp_order12, sig12) =
//         get_dummy_close_orders(&transaction_batch);

//     let perp_swap7 = PerpSwap::new(
//         perp_order11.order_id,
//         perp_order10.order_id,
//         Some(sig11),
//         Some(sig10.clone()),
//         20_000 * 10_u64.pow(6),
//         20 * 10_u64.pow(6),
//         2 * 10_u64.pow(6),
//         2 * 10_u64.pow(6) / 2,
//     );

//     let perp_swap8 = PerpSwap::new(
//         perp_order12.order_id,
//         perp_order10.order_id,
//         Some(sig12),
//         Some(sig10),
//         10_000 * 10_u64.pow(6),
//         10 * 10_u64.pow(6),
//         1 * 10_u64.pow(6),
//         1 * 10_u64.pow(6) / 2,
//     );

//     transaction_batch.submit_perpetual_order(perp_order10);
//     transaction_batch.submit_perpetual_order(perp_order11);
//     transaction_batch.submit_perpetual_order(perp_order12);

//     transaction_batch.execute_perpetual_transaction(perp_swap7);
//     transaction_batch.execute_perpetual_transaction(perp_swap8);

//     // println!(
//     //     "state tree leaves {:#?}",
//     //     transaction_batch.state_tree.leaf_nodes
//     // );
//     // println!("\n==============");
//     println!(
//         "perp state tree leaves {:#?}",
//         transaction_batch
//             .perpetual_state_tree
//             .lock()
//             .unwrap()
//             .leaf_nodes
//     );
//     println!("==============\n\n");

//     //

//     //

//     //

//     // transaction_batch
//     //     .perpetual_positions_map
//     //     .iter()
//     //     .for_each(|x| println!("{:#?}", x.1.position_size));
//     // println!(
//     //     "========================================================================================"
//     // );

//     // & CLOSE POSITION SWAPS ==================================================================================
//     // & ===================================================================================================

//     // let x = transaction_batch.swap_output_json.lock().unwrap();
//     // let mut json_res = serde_json::to_value(&x).unwrap();
//     // let mut output_json = serde_json::Map::new();
//     // output_json.insert(String::from("swaps"), json_res);
//     // let path = Path::new("./output.json");
//     // std::fs::write(path, serde_json::to_string(&output_json).unwrap()).unwrap();

//     println!("{:?}", "ALL GOOD");
// }

// //

// //

// #[test]
// fn test_batch_funding_rates() {
//     let (batch_init_tree, note, refund_note) = build_dummy_init_state_tree();

//     let mut tx_batch = TransactionBatch::new(batch_init_tree, Tree::new(3));

//     let (perp_order1, sig1, perp_order2, sig2, perp_order3, sig3) = get_dummy_open_orders();

//     let perp_swap1 = PerpSwap::new(
//         perp_order1.order_id,
//         perp_order2.order_id,
//         Some(sig1.clone()),
//         Some(sig2),
//         20000 * 10_u64.pow(6),
//         20 * 10_u64.pow(6),
//         2 * 10_u64.pow(6),
//         2 * 10_u64.pow(6) / 2,
//     );

//     let perp_swap2 = PerpSwap::new(
//         perp_order1.order_id,
//         perp_order3.order_id,
//         Some(sig1.clone()),
//         Some(sig3),
//         10000 * 10_u64.pow(6),
//         10 * 10_u64.pow(6),
//         1 * 10_u64.pow(6),
//         1 * 10_u64.pow(6) / 2,
//     );

//     tx_batch.submit_perpetual_order(perp_order1);
//     tx_batch.submit_perpetual_order(perp_order2);
//     tx_batch.submit_perpetual_order(perp_order3);

//     tx_batch.execute_perpetual_transaction(perp_swap1);
//     tx_batch.execute_perpetual_transaction(perp_swap2);

//     println!("{:#?}", tx_batch.perpetual_positions_map);
//     println!("======================================================================\n");

//     // ? =====================================================================================

//     let oracle_updates = get_dummy_oracle_updates(8);

//     for update in oracle_updates {
//         tx_batch.update_index_prices(vec![update.0, update.1]);
//         for i in 0..(240 / 8) {
//             tx_batch.per_minute_funding_updates();
//         }
//     }

//     tx_batch.apply_funding();

//     let funding_rates: [i64; 9] = [100, 150, -80, 200, -100, 130, -100, 20, -60];
//     let prices1: [u64; 9] = [
//         1992 * 10_u64.pow(6),
//         2000 * 10_u64.pow(6),
//         2002 * 10_u64.pow(6),
//         1996 * 10_u64.pow(6),
//         1997 * 10_u64.pow(6),
//         2001 * 10_u64.pow(6),
//         1998 * 10_u64.pow(6),
//         1999 * 10_u64.pow(6),
//         2000 * 10_u64.pow(6),
//     ];

//     let prices2: [u64; 9] = [
//         21000 * 10_u64.pow(6),
//         21005 * 10_u64.pow(6),
//         20995 * 10_u64.pow(6),
//         21000 * 10_u64.pow(6),
//         20995 * 10_u64.pow(6),
//         21005 * 10_u64.pow(6),
//         21005 * 10_u64.pow(6),
//         21000 * 10_u64.pow(6),
//         20995 * 10_u64.pow(6),
//     ];

//     for i in 0..9 {
//         let mut _funding_rates_: HashMap<u64, i64> = HashMap::new();
//         _funding_rates_.insert(0, funding_rates[i]);
//         _funding_rates_.insert(1, funding_rates[8 - i]);

//         let mut _funding_prices_: HashMap<u64, u64> = HashMap::new();
//         _funding_prices_.insert(0, prices1[i]);
//         _funding_prices_.insert(1, prices2[8 - i]);

//         tx_batch.dummy_apply_funding(_funding_rates_, _funding_prices_);
//     }

//     // ? =====================================================================================

//     // println!("{:#?}", tx_batch.perpetual_positions_map);
//     println!("======================================================================\n");

//     let (perp_order4, sig4, perp_order5, sig5, perp_order6, sig6) =
//         get_dummy_increase_size_orders(&tx_batch);

//     let perp_swap3 = PerpSwap::new(
//         perp_order4.order_id,
//         perp_order5.order_id,
//         Some(sig4.clone()),
//         Some(sig5),
//         5000 * 10_u64.pow(6),
//         5 * 10_u64.pow(6),
//         1 * 10_u64.pow(6) / 2,
//         1 * 10_u64.pow(6) / 4,
//     );

//     let perp_swap4 = PerpSwap::new(
//         perp_order4.order_id,
//         perp_order6.order_id,
//         Some(sig4.clone()),
//         Some(sig6),
//         5000 * 10_u64.pow(6),
//         5 * 10_u64.pow(6),
//         1 * 10_u64.pow(6) / 2,
//         1 * 10_u64.pow(6) / 4,
//     );

//     tx_batch.submit_perpetual_order(perp_order4);
//     tx_batch.submit_perpetual_order(perp_order5);
//     tx_batch.submit_perpetual_order(perp_order6);

//     tx_batch.execute_perpetual_transaction(perp_swap3);
//     tx_batch.execute_perpetual_transaction(perp_swap4);

//     // println!("{:#?}", tx_batch.perpetual_positions_map);
//     // println!("======================================================================\n");

//     let funding_info: FundingInfo = tx_batch.get_funding_info();

//     // let mut swaps_json = serde_json::to_value(&tx_batch.swap_output_json).unwrap();
//     // let mut funding_info_json = serde_json::to_value(&funding_info).unwrap();
//     // let mut output_json = serde_json::Map::new();
//     // output_json.insert(String::from("swaps"), swaps_json);
//     // output_json.insert(String::from("funding_info"), funding_info_json);
//     // let path = Path::new("./output.json");
//     // std::fs::write(path, serde_json::to_string(&output_json).unwrap()).unwrap();
// }

// //

// //

// #[test]
// fn test_spot_swaps() {
//     let pk1 = BigUint::from_str("8932749863246329746327463249328632").unwrap();

//     let (batch_init_tree, note1, refund_note1, note2, refund_note2) = build_spot_init_state_tree();

//     let mut tx_batch = TransactionBatch::new(batch_init_tree, Tree::new(3));

//     let limit_order1 = LimitOrder::new(
//         1,
//         10000,
//         0,
//         1,
//         10 * 10_u64.pow(6),
//         200 * 10_u64.pow(6),
//         10_u64.pow(5),
//         EcPoint {
//             x: BigInt::zero(),
//             y: BigInt::one(),
//         },
//         EcPoint {
//             x: BigInt::zero(),
//             y: BigInt::one(),
//         },
//         BigUint::zero(),
//         BigUint::zero(),
//         vec![note1],
//         refund_note1,
//     );

//     let limit_order2 = LimitOrder::new(
//         2,
//         10000,
//         1,
//         0,
//         100 * 10_u64.pow(6),
//         5 * 10_u64.pow(6),
//         10_u64.pow(5),
//         EcPoint {
//             x: BigInt::zero(),
//             y: BigInt::one(),
//         },
//         EcPoint {
//             x: BigInt::zero(),
//             y: BigInt::one(),
//         },
//         BigUint::zero(),
//         BigUint::zero(),
//         vec![note2.clone()],
//         refund_note2.clone(),
//     );

//     note2.index.set(2);
//     refund_note2.index.set(2);
//     let limit_order3 = LimitOrder::new(
//         3,
//         10000,
//         1,
//         0,
//         100 * 10_u64.pow(6),
//         5 * 10_u64.pow(6),
//         10_u64.pow(5),
//         EcPoint {
//             x: BigInt::zero(),
//             y: BigInt::one(),
//         },
//         EcPoint {
//             x: BigInt::zero(),
//             y: BigInt::one(),
//         },
//         BigUint::zero(),
//         BigUint::zero(),
//         vec![note2],
//         refund_note2,
//     );

//     tx_batch.submit_new_order(limit_order1.clone());
//     tx_batch.submit_new_order(limit_order2.clone());
//     tx_batch.submit_new_order(limit_order3.clone());

//     let sig1 = limit_order1.sign_order(vec![&pk1.clone()]);
//     let sig2 = limit_order2.sign_order(vec![&pk1.clone()]);
//     let sig3 = limit_order3.sign_order(vec![&pk1.clone()]);

//     let swap1 = Swap::new(
//         limit_order1.order_id,
//         limit_order2.order_id,
//         sig1.clone(),
//         sig2,
//         5 * 10_u64.pow(6),
//         100 * 10_u64.pow(6),
//         0,
//         0,
//     );

//     let swap2 = Swap::new(
//         limit_order1.order_id,
//         limit_order3.order_id,
//         sig1,
//         sig3,
//         5 * 10_u64.pow(6),
//         100 * 10_u64.pow(6),
//         0,
//         0,
//     );

//     tx_batch.execute_transaction(swap1);
//     tx_batch.execute_transaction(swap2);
// }
// //

// use std::time::Instant;

// #[test]
// fn test_full_batch() {
//     let fn_time = Instant::now();

//     let pk1 = BigInt::from_str("8932749863246329746327463249328632").unwrap();
//     let address1 = EcPoint::from_priv_key(&pk1);

//     let now = Instant::now();
//     let mut transaction_batch = TransactionBatch::new(Tree::new(5), Tree::new(3));
//     let elapsed = now.elapsed();

//     println!("init transaction_batch : {:.2?}", elapsed);

//     // & execute all deposits ===================================================================

//     let deposits = get_dummy_deposits();

//     let now = Instant::now();
//     for deposit in deposits {
//         transaction_batch.execute_transaction(deposit);
//     }
//     let deposit_time = now.elapsed();

//     // println!(
//     //     "state tree after deposit: {:#?}",
//     //     transaction_batch.state_tree.leaf_nodes
//     // );

//     // & make spot swaps ===================================================================

//     let (limit_order1, sig1, limit_order2, sig2, limit_order3, sig3) = get_dummy_spot_swaps();

//     transaction_batch.submit_new_order(limit_order1.clone());
//     transaction_batch.submit_new_order(limit_order2.clone());
//     transaction_batch.submit_new_order(limit_order3.clone());

//     let swap1 = Swap::new(
//         limit_order1.order_id,
//         limit_order2.order_id,
//         sig1.clone(),
//         sig2,
//         5 * 10_u64.pow(6),
//         100 * 10_u64.pow(6),
//         0,
//         0,
//     );

//     let swap2 = Swap::new(
//         limit_order1.order_id,
//         limit_order3.order_id,
//         sig1,
//         sig3,
//         5 * 10_u64.pow(6),
//         100 * 10_u64.pow(6),
//         0,
//         0,
//     );

//     let now = Instant::now();
//     transaction_batch.execute_transaction(swap1);
//     transaction_batch.execute_transaction(swap2);
//     let spot_swaps_time = now.elapsed();

//     // println!(
//     //     "after swaps: {:#?}",
//     //     transaction_batch.state_tree.leaf_nodes
//     // );

//     // & test all perpetual order types ======================================================================
//     // ! Open Orders

//     let (perp_order1, sig1, perp_order2, sig2, perp_order3, sig3) = get_dummy_open_orders();

//     let perp_swap1 = PerpSwap::new(
//         perp_order1.order_id,
//         perp_order2.order_id,
//         Some(sig1.clone()),
//         Some(sig2),
//         20000 * 10_u64.pow(6),
//         10 * 10_u64.pow(6),
//         2 * 10_u64.pow(6),
//         2 * 10_u64.pow(6) / 2,
//     );

//     let perp_swap2 = PerpSwap::new(
//         perp_order1.order_id,
//         perp_order3.order_id,
//         Some(sig1.clone()),
//         Some(sig3),
//         10000 * 10_u64.pow(6),
//         5 * 10_u64.pow(6),
//         1 * 10_u64.pow(6),
//         1 * 10_u64.pow(6) / 2,
//     );

//     transaction_batch.submit_perpetual_order(perp_order1);
//     transaction_batch.submit_perpetual_order(perp_order2);
//     transaction_batch.submit_perpetual_order(perp_order3);

//     let now = Instant::now();
//     transaction_batch.execute_perpetual_transaction(perp_swap1);
//     transaction_batch.execute_perpetual_transaction(perp_swap2);
//     let open_position_swaps_time = now.elapsed();

//     // println!(
//     //     "leaves after open {:#?}",
//     //     transaction_batch.state_tree.leaf_nodes
//     // );

//     // ! INCREASE SIZE ORDERS
//     let (perp_order4, sig4, perp_order5, sig5, perp_order6, sig6) =
//         get_dummy_increase_size_orders(&transaction_batch);

//     let perp_swap3 = PerpSwap::new(
//         perp_order4.order_id,
//         perp_order5.order_id,
//         Some(sig4.clone()),
//         Some(sig5),
//         5000 * 10_u64.pow(6),
//         25 * 10_u64.pow(5),
//         1 * 10_u64.pow(6) / 2,
//         1 * 10_u64.pow(6) / 4,
//     );

//     let perp_swap4 = PerpSwap::new(
//         perp_order4.order_id,
//         perp_order6.order_id,
//         Some(sig4.clone()),
//         Some(sig6),
//         5000 * 10_u64.pow(6),
//         25 * 10_u64.pow(5),
//         1 * 10_u64.pow(6) / 2,
//         1 * 10_u64.pow(6) / 4,
//     );

//     transaction_batch.submit_perpetual_order(perp_order4);
//     transaction_batch.submit_perpetual_order(perp_order5);
//     transaction_batch.submit_perpetual_order(perp_order6);

//     let now = Instant::now();
//     transaction_batch.execute_perpetual_transaction(perp_swap3);
//     transaction_batch.execute_perpetual_transaction(perp_swap4);
//     let increase_position_swaps_time = now.elapsed();

//     // println!(
//     //     "perp positions after increase size {:#?}",
//     //     transaction_batch.perpetual_state_tree.leaf_nodes
//     // );

//     // ? =====================================================================================

//     let oracle_updates = get_dummy_oracle_updates(8);

//     for update in oracle_updates {
//         transaction_batch.update_index_prices(vec![update.0, update.1]);
//         for i in 0..(240 / 8) {
//             transaction_batch.per_minute_funding_updates();
//         }
//     }

//     transaction_batch.apply_funding();

//     let funding_rates: [i64; 9] = [100, 150, -80, 200, -100, 130, -100, 20, -60];
//     let prices1: [u64; 9] = [
//         1992 * 10_u64.pow(6),
//         2000 * 10_u64.pow(6),
//         2002 * 10_u64.pow(6),
//         1996 * 10_u64.pow(6),
//         1997 * 10_u64.pow(6),
//         2001 * 10_u64.pow(6),
//         1998 * 10_u64.pow(6),
//         1999 * 10_u64.pow(6),
//         2000 * 10_u64.pow(6),
//     ];

//     let prices2: [u64; 9] = [
//         21000 * 10_u64.pow(6),
//         21005 * 10_u64.pow(6),
//         20995 * 10_u64.pow(6),
//         21000 * 10_u64.pow(6),
//         20995 * 10_u64.pow(6),
//         21005 * 10_u64.pow(6),
//         21005 * 10_u64.pow(6),
//         21000 * 10_u64.pow(6),
//         20995 * 10_u64.pow(6),
//     ];

//     let now = Instant::now();
//     for i in 0..9 {
//         let mut _funding_rates_: HashMap<u64, i64> = HashMap::new();
//         _funding_rates_.insert(0, funding_rates[i]);
//         _funding_rates_.insert(1, funding_rates[8 - i]);

//         let mut _funding_prices_: HashMap<u64, u64> = HashMap::new();
//         _funding_prices_.insert(0, prices1[i]);
//         _funding_prices_.insert(1, prices2[8 - i]);

//         transaction_batch.dummy_apply_funding(_funding_rates_, _funding_prices_);
//     }
//     let funding_time = now.elapsed();

//     // ? =====================================================================================

//     // ! DECREASE SIZE ORDERS
//     let (perp_order7, sig7, perp_order8, sig8, perp_order9, sig9) =
//         get_dummy_reduce_size_orders(&transaction_batch);

//     let perp_swap5 = PerpSwap::new(
//         perp_order8.order_id,
//         perp_order7.order_id,
//         Some(sig8),
//         Some(sig7.clone()),
//         5000 * 10_u64.pow(6),
//         25 * 10_u64.pow(5),
//         1 * 10_u64.pow(6) / 2,
//         1 * 10_u64.pow(6) / 4,
//     );

//     let perp_swap6 = PerpSwap::new(
//         perp_order9.order_id,
//         perp_order7.order_id,
//         Some(sig9),
//         Some(sig7.clone()),
//         5000 * 10_u64.pow(6),
//         25 * 10_u64.pow(5),
//         1 * 10_u64.pow(6) / 2,
//         1 * 10_u64.pow(6) / 4,
//     );

//     transaction_batch.submit_perpetual_order(perp_order7);
//     transaction_batch.submit_perpetual_order(perp_order8);
//     transaction_batch.submit_perpetual_order(perp_order9);

//     let now = Instant::now();
//     transaction_batch.execute_perpetual_transaction(perp_swap5);
//     transaction_batch.execute_perpetual_transaction(perp_swap6);
//     let decrease_position_swaps_time = now.elapsed();

//     // println!(
//     //     "perp positions after decrease size {:#?} \n\n",
//     //     transaction_batch.perpetual_positions_map
//     // );

//     // ! CLOSE ORDERS
//     let (_, _, perp_order11, sig11, perp_order12, sig12) =
//         get_dummy_close_orders(&transaction_batch);

//     let perp_order10 = get_dummy_liquidate_order(&transaction_batch);

//     let perp_swap7 = PerpSwap::new(
//         perp_order11.order_id,
//         perp_order10.order_id,
//         Some(sig11),
//         None,
//         10_000 * 10_u64.pow(6),
//         10 * 10_u64.pow(6),
//         1 * 10_u64.pow(6),
//         0,
//     );

//     let perp_swap8 = PerpSwap::new(
//         perp_order12.order_id,
//         perp_order10.order_id,
//         Some(sig12),
//         None,
//         5_000 * 10_u64.pow(6),
//         5 * 10_u64.pow(6),
//         5 * 10_u64.pow(5),
//         0,
//     );

//     transaction_batch.submit_perpetual_order(perp_order10);
//     transaction_batch.submit_perpetual_order(perp_order11);
//     transaction_batch.submit_perpetual_order(perp_order12);

//     let now = Instant::now();
//     transaction_batch.execute_perpetual_transaction(perp_swap7);
//     transaction_batch.execute_perpetual_transaction(perp_swap8);
//     let close_position_swaps_time = now.elapsed();

//     // println!(
//     //     "perp positions after close {:#?}",
//     //     transaction_batch.perpetual_positions_map
//     // );

//     // & make withdrawals ================================================================

//     let withdrawals = get_dummy_withdrawals();

//     let now = Instant::now();
//     for withdrawal in withdrawals {
//         transaction_batch.execute_transaction(withdrawal);
//     }
//     let withdrawal_time = now.elapsed();

//     // println!(
//     //     "leaves after withdrawals: {:#?}",
//     //     transaction_batch.state_tree.leaf_nodes
//     // );

//     // ? ====================================================================================

//     println!("deposit_time: {:?}", deposit_time);
//     println!("spot_swaps_time: {:?}", spot_swaps_time);
//     println!("open_position_swaps_time: {:?}", open_position_swaps_time);
//     println!(
//         "increase_position_swaps_time: {:?}",
//         increase_position_swaps_time
//     );
//     println!(
//         "decrease_position_swaps_time: {:?}",
//         decrease_position_swaps_time
//     );
//     println!("close_position_swaps_time: {:?}", close_position_swaps_time);
//     println!("withdrawal_time: {:?}", withdrawal_time);

//     let now = Instant::now();
//     transaction_batch.finalize_batch();
//     let finalize_time = now.elapsed();

//     println!("finalize_time: {:?}", finalize_time);

//     // println!("{:#?}", transaction_batch.state_tree.leaf_nodes);

//     println!("{:?}", "ALL GOOD");
// }

// //

// //

// fn get_dummy_open_orders() -> (
//     PerpOrder,
//     Signature,
//     PerpOrder,
//     Signature,
//     PerpOrder,
//     Signature,
// ) {
//     //
//     let pk1 = BigInt::from_str("8932749863246329746327463249328632").unwrap();
//     let address1 = EcPoint::from_priv_key(&pk1);

//     let mut note = Note::new(
//         0,
//         address1.clone(), //todo,
//         1,
//         10_u64.pow(12),
//         BigUint::from_str("1234").unwrap(),
//     );

//     let mut refund_note = Note::new(
//         0,
//         address1.clone(), //todo,
//         1,
//         10_u64.pow(12) - 30_000 * 10_u64.pow(6),
//         BigUint::from_str("1234").unwrap(),
//     );

//     let note1 = note.clone();
//     note1.index.set(1);
//     let note2 = note.clone();
//     note2.index.set(2);
//     let note3 = note.clone();
//     note3.index.set(3);

//     let refund_note1 = refund_note.clone();
//     refund_note1.index.set(1);
//     let refund_note2 = refund_note.clone();
//     refund_note2.index.set(2);
//     let refund_note3 = refund_note.clone();
//     refund_note3.index.set(3);

//     // ============================================================================================

//     // & Order A is long for 3 BTC with 3x leverage with price of BTC at 10000 USD

//     let order_id = 1;
//     let expiration_timestamp: u32 = 10000;
//     let position_id = 111;
//     let order_side = OrderSide::Long;
//     let synthetic_token = 0;
//     let collateral_token = 1;
//     let synthetic_amount = 15 * 10_u64.pow(6);
//     let collateral_amount = 30_000 * 10_u64.pow(6);
//     let leverage = 200;
//     let fee_limit = 3 * 10_u64.pow(6);
//     let notes_in = vec![note1];
//     let refund_note = refund_note1;

//     let perp_order_a = PerpOrder::new_open_order(
//         order_id,
//         expiration_timestamp,
//         position_id,
//         order_side,
//         synthetic_token,
//         collateral_token,
//         synthetic_amount,
//         collateral_amount,
//         leverage,
//         fee_limit,
//         notes_in,
//         refund_note,
//         address1.clone(),
//     );

//     let signature1 = perp_order_a.sign_order(
//         //
//         Some(vec![&pk1.to_biguint().unwrap()]),
//         None,
//     );

//     // & Order B is short for 2 BTC with 2x leverage with price of USDC at 10000 USD

//     let order_id = 2;
//     let expiration_timestamp: u32 = 10000;
//     let position_id = 222;
//     let order_side = OrderSide::Short;
//     let synthetic_token = 0;
//     let collateral_token = 1;
//     let synthetic_amount = 10 * 10_u64.pow(6);
//     let collateral_amount = 20_000 * 10_u64.pow(6);
//     let leverage = 200;
//     let fee_limit = 2 * 10_u64.pow(6);
//     let notes_in = vec![note2];
//     let refund_note = refund_note2;

//     let perp_order_b = PerpOrder::new_open_order(
//         order_id,
//         expiration_timestamp,
//         position_id,
//         order_side,
//         synthetic_token,
//         collateral_token,
//         synthetic_amount,
//         collateral_amount,
//         leverage,
//         fee_limit,
//         notes_in,
//         refund_note,
//         address1.clone(),
//     );

//     let signature2 = perp_order_b.sign_order(
//         //
//         Some(vec![&pk1.to_biguint().unwrap()]),
//         None,
//     );

//     // & Order C is short for 1 BTC with 1x leverage with price of USDC at 10000 USD

//     let order_id = 3;
//     let expiration_timestamp: u32 = 10000;
//     let position_id = 333;
//     let order_side = OrderSide::Short;
//     let synthetic_token = 0;
//     let collateral_token = 1;
//     let synthetic_amount = 5 * 10_u64.pow(6);
//     let collateral_amount = 10_000 * 10_u64.pow(6);
//     let leverage = 100;
//     let fee_limit = 1 * 10_u64.pow(6);
//     let notes_in = vec![note3];
//     let refund_note = refund_note3;

//     let perp_order_c = PerpOrder::new_open_order(
//         order_id,
//         expiration_timestamp,
//         position_id,
//         order_side,
//         synthetic_token,
//         collateral_token,
//         synthetic_amount,
//         collateral_amount,
//         leverage,
//         fee_limit,
//         notes_in,
//         refund_note,
//         address1.clone(),
//     );

//     let signature3 = perp_order_c.sign_order(
//         //
//         Some(vec![&pk1.to_biguint().unwrap()]),
//         None,
//     );

//     return (
//         perp_order_a,
//         signature1,
//         perp_order_b,
//         signature2,
//         perp_order_c,
//         signature3,
//     );
// }

// fn get_dummy_increase_size_orders(
//     transaction_batch: &TransactionBatch,
// ) -> (
//     PerpOrder,
//     Signature,
//     PerpOrder,
//     Signature,
//     PerpOrder,
//     Signature,
// ) {
//     //
//     let pk1 = BigInt::from_str("8932749863246329746327463249328632").unwrap();
//     let address1 = EcPoint::from_priv_key(&pk1);

//     // ============================================================================================

//     // & Order A —————————————————————————————————————————————————————————————————————

//     let order_id = 4;
//     let expiration_timestamp: u32 = 10000;
//     let position_id = 111;
//     let order_side = OrderSide::Long;
//     let synthetic_token = 0;
//     let collateral_token = 1;
//     let synthetic_amount = 5 * 10_u64.pow(6);
//     let collateral_amount = 10_000 * 10_u64.pow(6);
//     let fee_limit = 1 * 10_u64.pow(6);

//     let prev_position = transaction_batch.get_position_by_id(position_id);
//     if prev_position.is_none() {
//         panic!("Position not found");
//     }

//     let perp_order_a = PerpOrder::new_modify_order(
//         order_id,
//         expiration_timestamp,
//         position_id,
//         order_side,
//         synthetic_token,
//         collateral_token,
//         synthetic_amount,
//         collateral_amount,
//         fee_limit,
//         prev_position.unwrap().get_identifier(),
//     );

//     let signature1 = perp_order_a.sign_order(
//         //
//         None,
//         Some(pk1.to_biguint().as_ref().unwrap()),
//     );

//     // & Order B  —————————————————————————————————————————————————————————————————————

//     let order_id = 5;
//     let expiration_timestamp: u32 = 10000;
//     let position_id = 222;
//     let order_side = OrderSide::Short;
//     let synthetic_token = 0;
//     let collateral_token = 1;
//     let synthetic_amount = 25 * 10_u64.pow(5);
//     let collateral_amount = 5000 * 10_u64.pow(6);
//     let fee_limit = 5 * 10_u64.pow(5);

//     let prev_position = transaction_batch.get_position_by_id(position_id);
//     if prev_position.is_none() {
//         panic!("Position not found");
//     }

//     let perp_order_b = PerpOrder::new_modify_order(
//         order_id,
//         expiration_timestamp,
//         position_id,
//         order_side,
//         synthetic_token,
//         collateral_token,
//         synthetic_amount,
//         collateral_amount,
//         fee_limit,
//         prev_position.unwrap().get_identifier(),
//     );

//     let signature2 = perp_order_b.sign_order(
//         //
//         None,
//         Some(pk1.to_biguint().as_ref().unwrap()),
//     );

//     // & Order C  —————————————————————————————————————————————————————————————————————

//     let order_id = 6;
//     let expiration_timestamp: u32 = 10000;
//     let position_id = 333;
//     let order_side = OrderSide::Short;
//     let synthetic_token = 0;
//     let collateral_token = 1;
//     let synthetic_amount = 25 * 10_u64.pow(5);
//     let collateral_amount = 5000 * 10_u64.pow(6);
//     let fee_limit = 5 * 10_u64.pow(5);

//     let prev_position = transaction_batch.get_position_by_id(position_id);
//     if prev_position.is_none() {
//         panic!("Position not found");
//     }

//     let perp_order_c = PerpOrder::new_modify_order(
//         order_id,
//         expiration_timestamp,
//         position_id,
//         order_side,
//         synthetic_token,
//         collateral_token,
//         synthetic_amount,
//         collateral_amount,
//         fee_limit,
//         prev_position.unwrap().get_identifier(),
//     );

//     let signature3 = perp_order_c.sign_order(
//         //
//         None,
//         Some(pk1.to_biguint().as_ref().unwrap()),
//     );

//     return (
//         perp_order_a,
//         signature1,
//         perp_order_b,
//         signature2,
//         perp_order_c,
//         signature3,
//     );
// }

// fn get_dummy_reduce_size_orders(
//     transaction_batch: &TransactionBatch,
// ) -> (
//     PerpOrder,
//     Signature,
//     PerpOrder,
//     Signature,
//     PerpOrder,
//     Signature,
// ) {
//     //
//     let pk1 = BigInt::from_str("8932749863246329746327463249328632").unwrap();

//     // ============================================================================================

//     // & Order A ————————————————————————————————————————————————————————————————————————————

//     let order_id = 7;
//     let expiration_timestamp: u32 = 10000;
//     let position_id = 111;
//     let order_side = OrderSide::Short;
//     let synthetic_token = 0;
//     let collateral_token = 1;
//     let synthetic_amount = 5 * 10_u64.pow(6);
//     let collateral_amount = 10_000 * 10_u64.pow(6);
//     let fee_limit = 1 * 10_u64.pow(6);

//     let prev_position = transaction_batch.get_position_by_id(position_id);
//     if prev_position.is_none() {
//         panic!("Position not found");
//     }

//     let perp_order_a = PerpOrder::new_modify_order(
//         order_id,
//         expiration_timestamp,
//         position_id,
//         order_side,
//         synthetic_token,
//         collateral_token,
//         synthetic_amount,
//         collateral_amount,
//         fee_limit,
//         prev_position.unwrap().get_identifier(),
//     );

//     let signature1 = perp_order_a.sign_order(
//         //
//         None,
//         Some(pk1.to_biguint().as_ref().unwrap()),
//     );

//     // & Order B   ————————————————————————————————————————————————————————————————————————————

//     let order_id = 8;
//     let expiration_timestamp: u32 = 10000;
//     let position_id = 222;
//     let order_side = OrderSide::Long;
//     let synthetic_token = 0;
//     let collateral_token = 1;
//     let synthetic_amount = 25 * 10_u64.pow(5);
//     let collateral_amount = 5000 * 10_u64.pow(6);
//     let fee_limit = 5 * 10_u64.pow(5);

//     let prev_position = transaction_batch.get_position_by_id(position_id);
//     if prev_position.is_none() {
//         panic!("Position not found");
//     }

//     let perp_order_b = PerpOrder::new_modify_order(
//         order_id,
//         expiration_timestamp,
//         position_id,
//         order_side,
//         synthetic_token,
//         collateral_token,
//         synthetic_amount,
//         collateral_amount,
//         fee_limit,
//         prev_position.unwrap().get_identifier(),
//     );

//     let signature2 = perp_order_b.sign_order(
//         //
//         None,
//         Some(pk1.to_biguint().as_ref().unwrap()),
//     );

//     // & Order C   ————————————————————————————————————————————————————————————————————————————

//     let order_id = 9;
//     let expiration_timestamp: u32 = 10000;
//     let position_id = 333;
//     let order_side = OrderSide::Long;
//     let synthetic_token = 0;
//     let collateral_token = 1;
//     let synthetic_amount = 25 * 10_u64.pow(5);
//     let collateral_amount = 5000 * 10_u64.pow(6);
//     let fee_limit = 5 * 10_u64.pow(5);

//     let prev_position = transaction_batch.get_position_by_id(position_id);
//     if prev_position.is_none() {
//         panic!("Position not found");
//     }

//     let perp_order_c = PerpOrder::new_modify_order(
//         order_id,
//         expiration_timestamp,
//         position_id,
//         order_side,
//         synthetic_token,
//         collateral_token,
//         synthetic_amount,
//         collateral_amount,
//         fee_limit,
//         prev_position.unwrap().get_identifier(),
//     );

//     let signature3 = perp_order_c.sign_order(
//         //
//         None,
//         Some(pk1.to_biguint().as_ref().unwrap()),
//     );

//     return (
//         perp_order_a,
//         signature1,
//         perp_order_b,
//         signature2,
//         perp_order_c,
//         signature3,
//     );
// }

// fn get_dummy_close_orders(
//     transaction_batch: &TransactionBatch,
// ) -> (
//     PerpOrder,
//     Signature,
//     PerpOrder,
//     Signature,
//     PerpOrder,
//     Signature,
// ) {
//     //
//     let pk1 = BigInt::from_str("8932749863246329746327463249328632").unwrap();

//     // ============================================================================================

//     // & Order A    ———————————————————————————————————————————————————————————————————————————
//     let order_id = 10;
//     let expiration_timestamp: u32 = 10000;
//     let position_id = 111;
//     let order_side = OrderSide::Short;
//     let synthetic_token = 0;
//     let collateral_token = 1;
//     let synthetic_amount = 15 * 10_u64.pow(6);
//     let collateral_amount = 15_000 * 10_u64.pow(6);
//     let fee_limit = 3 * 10_u64.pow(6);

//     let prev_position = transaction_batch.get_position_by_id(position_id);
//     if prev_position.is_none() {
//         panic!("Position not found");
//     }

//     let perp_order_a = PerpOrder::new_close_order(
//         order_id,
//         expiration_timestamp,
//         position_id,
//         order_side,
//         synthetic_token,
//         collateral_token,
//         synthetic_amount,
//         collateral_amount,
//         fee_limit,
//         prev_position.unwrap().get_identifier(),
//         EcPoint {
//             x: BigInt::zero(),
//             y: BigInt::zero(),
//         },
//         BigUint::zero(),
//     );

//     let signature1 = perp_order_a.sign_order(
//         //
//         None,
//         Some(pk1.to_biguint().as_ref().unwrap()),
//     );

//     // & Order B     ———————————————————————————————————————————————————————————————————————————

//     let order_id = 11;
//     let expiration_timestamp: u32 = 10000;
//     let position_id = 222;
//     let order_side = OrderSide::Long;
//     let synthetic_token = 0;
//     let collateral_token = 1;
//     let synthetic_amount = 10 * 10_u64.pow(6);
//     let collateral_amount = 10_000 * 10_u64.pow(6);
//     let fee_limit = 1 * 10_u64.pow(6);

//     let prev_position = transaction_batch.get_position_by_id(position_id);
//     if prev_position.is_none() {
//         panic!("Position not found");
//     }

//     let perp_order_b = PerpOrder::new_close_order(
//         order_id,
//         expiration_timestamp,
//         position_id,
//         order_side,
//         synthetic_token,
//         collateral_token,
//         synthetic_amount,
//         collateral_amount,
//         fee_limit,
//         prev_position.unwrap().get_identifier(),
//         EcPoint {
//             x: BigInt::zero(),
//             y: BigInt::zero(),
//         },
//         BigUint::zero(),
//     );

//     let signature2 = perp_order_b.sign_order(
//         //
//         None,
//         Some(pk1.to_biguint().as_ref().unwrap()),
//     );

//     // & Order C    ———————————————————————————————————————————————————————————————————————————

//     let order_id = 12;
//     let expiration_timestamp: u32 = 10000;
//     let position_id = 333;
//     let order_side = OrderSide::Long;
//     let synthetic_token = 0;
//     let collateral_token = 1;
//     let synthetic_amount = 5 * 10_u64.pow(6);
//     let collateral_amount = 5_000 * 10_u64.pow(6);
//     let fee_limit = 1 * 10_u64.pow(6);

//     let prev_position = transaction_batch.get_position_by_id(position_id);
//     if prev_position.is_none() {
//         panic!("Position not found");
//     }

//     let perp_order_c = PerpOrder::new_close_order(
//         order_id,
//         expiration_timestamp,
//         position_id,
//         order_side,
//         synthetic_token,
//         collateral_token,
//         synthetic_amount,
//         collateral_amount,
//         fee_limit,
//         prev_position.unwrap().get_identifier(),
//         EcPoint {
//             x: BigInt::zero(),
//             y: BigInt::zero(),
//         },
//         BigUint::zero(),
//     );

//     let signature3 = perp_order_c.sign_order(
//         //
//         None,
//         Some(pk1.to_biguint().as_ref().unwrap()),
//     );

//     return (
//         perp_order_a,
//         signature1,
//         perp_order_b,
//         signature2,
//         perp_order_c,
//         signature3,
//     );
// }

// fn get_dummy_liquidate_order(transaction_batch: &TransactionBatch) -> PerpOrder {
//     // ============================================================================================

//     // & Order A    ———————————————————————————————————————————————————————————————————————————
//     let order_id = 10;
//     let expiration_timestamp: u32 = 10000;
//     let position_id = 111;
//     let order_side = OrderSide::Short;
//     let synthetic_token = 0;
//     let collateral_token = 1;
//     let synthetic_amount = 15 * 10_u64.pow(6);
//     let collateral_amount = 15_000 * 10_u64.pow(6);

//     let prev_position = transaction_batch.get_position_by_id(position_id);
//     if prev_position.is_none() {
//         panic!("Position not found");
//     }

//     let perp_order_a = PerpOrder::new_liquidation_order(
//         order_id,
//         expiration_timestamp,
//         position_id,
//         order_side,
//         synthetic_token,
//         collateral_token,
//         synthetic_amount,
//         collateral_amount,
//         prev_position.unwrap().get_identifier(),
//     );

//     return perp_order_a;
// }

// //

// //

// fn build_dummy_init_state_tree() -> (Tree, Note, Note) {
//     let pk1 = BigInt::from_str("8932749863246329746327463249328632").unwrap();
//     let address1 = EcPoint::from_priv_key(&pk1);

//     let mut note = Note::new(
//         0,
//         address1, //todo,
//         1,
//         10_u64.pow(12),
//         BigUint::from_str("1234").unwrap(),
//     );

//     let mut refund_note = Note::new(
//         1,
//         EcPoint {
//             x: BigInt::zero(),
//             y: BigInt::zero(),
//         }, // todo,
//         1,
//         10_u64.pow(9),
//         BigUint::from_str("1234").unwrap(),
//     );

//     let mut batch_init_tree = Tree::new(5);
//     for i in 0..9 {
//         let (proof, proof_pos) = batch_init_tree.get_proof(i as u64);
//         batch_init_tree.update_node(&note.hash, i as u64, &proof);
//     }

//     return (batch_init_tree, note, refund_note);
// }

// fn build_spot_init_state_tree() -> (Tree, Note, Note, Note, Note) {
//     let pk1 = BigInt::from_str("8932749863246329746327463249328632").unwrap();
//     let address1 = EcPoint::from_priv_key(&pk1);

//     let mut note = Note::new(
//         0,
//         address1.clone(), //todo,
//         0,
//         10_u64.pow(12),
//         BigUint::from_str("1234").unwrap(),
//     );

//     let mut refund_note = Note::new(
//         0,
//         EcPoint {
//             x: BigInt::zero(),
//             y: BigInt::zero(),
//         }, // todo,
//         0,
//         10_u64.pow(9),
//         BigUint::from_str("1234").unwrap(),
//     );

//     let mut note2 = Note::new(
//         1,
//         address1.clone(), //todo,
//         1,
//         10_u64.pow(12),
//         BigUint::from_str("1234").unwrap(),
//     );

//     let mut refund_note2 = Note::new(
//         1,
//         EcPoint {
//             x: BigInt::zero(),
//             y: BigInt::zero(),
//         }, // todo,
//         1,
//         10_u64.pow(9),
//         BigUint::from_str("1234").unwrap(),
//     );

//     let mut batch_init_tree = Tree::new(5);

//     let (proof, proof_pos) = batch_init_tree.get_proof(0);
//     batch_init_tree.update_node(&note.hash, 0, &proof);
//     for i in 1..4 {
//         let (proof, proof_pos) = batch_init_tree.get_proof(i as u64);
//         batch_init_tree.update_node(&note2.hash, i as u64, &proof);
//     }

//     return (batch_init_tree, note, refund_note, note2, refund_note2);
// }

// //

// fn get_dummy_oracle_updates(n: usize) -> Vec<(OracleUpdate, OracleUpdate)> {
//     assert!(n <= 9);

//     let prices1: [u64; 9] = [
//         1992 * 10_u64.pow(6),
//         2000 * 10_u64.pow(6),
//         2002 * 10_u64.pow(6),
//         1996 * 10_u64.pow(6),
//         1997 * 10_u64.pow(6),
//         2001 * 10_u64.pow(6),
//         1998 * 10_u64.pow(6),
//         1999 * 10_u64.pow(6),
//         2000 * 10_u64.pow(6),
//     ];

//     let prices2: [u64; 9] = [
//         21000 * 10_u64.pow(6),
//         21005 * 10_u64.pow(6),
//         20995 * 10_u64.pow(6),
//         21000 * 10_u64.pow(6),
//         20995 * 10_u64.pow(6),
//         21005 * 10_u64.pow(6),
//         21005 * 10_u64.pow(6),
//         21000 * 10_u64.pow(6),
//         20995 * 10_u64.pow(6),
//     ];

//     let mut vec: Vec<(OracleUpdate, OracleUpdate)> = Vec::new();

//     for i in 0..n {
//         let oracle_update1 = OracleUpdate {
//             token: 0,
//             timestamp: 0,
//             observer_ids: vec![1, 2, 3],
//             prices: vec![prices1[i] - 100_000, prices1[i], prices1[i] + 100_000],
//             signatures: vec![
//                 (BigUint::zero(), BigUint::zero()),
//                 (BigUint::zero(), BigUint::zero()),
//                 (BigUint::zero(), BigUint::zero()),
//             ],
//         };
//         let oracle_update2 = OracleUpdate {
//             token: 1,
//             timestamp: 0,
//             observer_ids: vec![1, 2, 3],
//             prices: vec![prices2[i] - 1_000_000, prices2[i], prices2[i] + 1_000_000],
//             signatures: vec![
//                 (BigUint::zero(), BigUint::zero()),
//                 (BigUint::zero(), BigUint::zero()),
//                 (BigUint::zero(), BigUint::zero()),
//             ],
//         };

//         vec.push((oracle_update1, oracle_update2));
//     }

//     return vec;
// }

// //

// fn get_dummy_deposits() -> Vec<Deposit> {
//     let pk1 = BigInt::from_str("8932749863246329746327463249328632").unwrap();
//     let address1 = EcPoint::from_priv_key(&pk1);

//     let mut note1 = Note::new(
//         0,
//         address1.clone(), //todo,
//         1,
//         10_u64.pow(12),
//         BigUint::from_str("1234").unwrap(),
//     );

//     let mut note2 = Note::new(
//         0,
//         address1.clone(), //todo,
//         0,
//         10_u64.pow(12),
//         BigUint::from_str("1234").unwrap(),
//     );

//     let mut deposits: Vec<Deposit> = Vec::new();

//     for i in 0..4 {
//         let note = note1.clone();
//         note.index.set(i);
//         let deposit = Deposit::new(
//             i,
//             1,
//             10_u64.pow(12),
//             address1.x.to_biguint().unwrap(),
//             vec![note],
//             &pk1.to_biguint().unwrap(),
//         );

//         deposits.push(deposit);
//     }
//     for i in 4..6 {
//         let note = note2.clone();
//         note.index.set(i);
//         let deposit = Deposit::new(
//             i,
//             0,
//             10_u64.pow(12),
//             address1.x.to_biguint().unwrap(),
//             vec![note],
//             &pk1.to_biguint().unwrap(),
//         );

//         deposits.push(deposit);
//     }

//     return deposits;
// }

// fn get_dummy_spot_swaps() -> (
//     LimitOrder,
//     Signature,
//     LimitOrder,
//     Signature,
//     LimitOrder,
//     Signature,
// ) {
//     let pk1 = BigInt::from_str("8932749863246329746327463249328632").unwrap();
//     let address1 = EcPoint::from_priv_key(&pk1);

//     let mut note1 = Note::new(
//         0,
//         address1.clone(), //todo,
//         1,
//         10_u64.pow(12),
//         BigUint::from_str("1234").unwrap(),
//     );

//     let mut refund_note1 = Note::new(
//         0,
//         address1.clone(), //todo,
//         1,
//         10_u64.pow(12) - 10 * 10_u64.pow(6),
//         BigUint::from_str("1234").unwrap(),
//     );

//     let mut note2 = Note::new(
//         4,
//         address1.clone(), //todo,
//         0,
//         10_u64.pow(12),
//         BigUint::from_str("1234").unwrap(),
//     );

//     let mut refund_note2 = Note::new(
//         4,
//         address1.clone(), //todo,
//         0,
//         10_u64.pow(12) - 100 * 10_u64.pow(6),
//         BigUint::from_str("1234").unwrap(),
//     );

//     let note3 = note2.clone();
//     note3.index.set(5);
//     let refund_note3 = refund_note2.clone();
//     refund_note3.index.set(5);

//     let limit_order1 = LimitOrder::new(
//         1,
//         10000,
//         1,
//         0,
//         10 * 10_u64.pow(6),
//         200 * 10_u64.pow(6),
//         10_u64.pow(5),
//         EcPoint {
//             x: BigInt::zero(),
//             y: BigInt::one(),
//         },
//         EcPoint {
//             x: BigInt::zero(),
//             y: BigInt::one(),
//         },
//         BigUint::zero(),
//         BigUint::zero(),
//         vec![note1],
//         refund_note1,
//     );

//     let limit_order2 = LimitOrder::new(
//         2,
//         10000,
//         0,
//         1,
//         100 * 10_u64.pow(6),
//         5 * 10_u64.pow(6),
//         10_u64.pow(5),
//         EcPoint {
//             x: BigInt::zero(),
//             y: BigInt::one(),
//         },
//         EcPoint {
//             x: BigInt::zero(),
//             y: BigInt::one(),
//         },
//         BigUint::zero(),
//         BigUint::zero(),
//         vec![note2.clone()],
//         refund_note2.clone(),
//     );

//     let limit_order3 = LimitOrder::new(
//         3,
//         10000,
//         0,
//         1,
//         100 * 10_u64.pow(6),
//         5 * 10_u64.pow(6),
//         10_u64.pow(5),
//         EcPoint {
//             x: BigInt::zero(),
//             y: BigInt::one(),
//         },
//         EcPoint {
//             x: BigInt::zero(),
//             y: BigInt::one(),
//         },
//         BigUint::zero(),
//         BigUint::zero(),
//         vec![note3],
//         refund_note3,
//     );

//     let sig1 = limit_order1.sign_order(vec![&pk1.to_biguint().unwrap()]);
//     let sig2 = limit_order2.sign_order(vec![&pk1.to_biguint().unwrap()]);
//     let sig3 = limit_order3.sign_order(vec![&pk1.to_biguint().unwrap()]);

//     return (limit_order1, sig1, limit_order2, sig2, limit_order3, sig3);
// }

// fn get_dummy_withdrawals() -> Vec<Withdrawal> {
//     let pk1 = BigInt::from_str("8932749863246329746327463249328632").unwrap();
//     let address1 = EcPoint::from_priv_key(&pk1);

//     let mut note1 = Note::new(
//         0,
//         address1.clone(), //todo,
//         1,
//         10_u64.pow(12) - 10 * 10_u64.pow(6),
//         BigUint::from_str("1234").unwrap(),
//     );
//     let withdrawal_amount1 = 20 * 10_u64.pow(6);
//     let refund_note1 = Note::new(
//         0,
//         address1.clone(), //todo,
//         1,
//         10_u64.pow(12) - 30 * 10_u64.pow(6),
//         BigUint::from_str("1234").unwrap(),
//     );

//     let mut note2 = Note::new(
//         4,
//         address1.clone(), //todo,
//         0,
//         10_u64.pow(12) - 100 * 10_u64.pow(6),
//         BigUint::from_str("1234").unwrap(),
//     );
//     let withdrawal_amount2 = 200 * 10_u64.pow(6);
//     let refund_note2 = Note::new(
//         4,
//         address1.clone(), //todo,
//         0,
//         10_u64.pow(12) - 300 * 10_u64.pow(6),
//         BigUint::from_str("1234").unwrap(),
//     );

//     let note3 = note2.clone();
//     note3.index.set(5);
//     let refund_note3 = refund_note2.clone();
//     refund_note3.index.set(5);

//     let withdrawal1 = Withdrawal::new(
//         1,
//         1,
//         withdrawal_amount1,
//         address1.x.to_biguint().unwrap(),
//         vec![note1],
//         refund_note1,
//         vec![&pk1.clone().to_biguint().unwrap()],
//     );

//     let withdrawal2 = Withdrawal::new(
//         2,
//         0,
//         withdrawal_amount2,
//         address1.x.to_biguint().unwrap(),
//         vec![note2],
//         refund_note2,
//         vec![&pk1.clone().to_biguint().unwrap()],
//     );

//     let withdrawal3 = Withdrawal::new(
//         3,
//         0,
//         withdrawal_amount2,
//         address1.x.to_biguint().unwrap(),
//         vec![note3],
//         refund_note3,
//         vec![&pk1.clone().to_biguint().unwrap()],
//     );

//     return vec![withdrawal1, withdrawal2, withdrawal3];
// }
