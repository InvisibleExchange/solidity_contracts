// use parking_lot::Mutex;
// use std::collections::HashMap;
// use std::str::FromStr;
// use std::sync::Arc;
// use std::thread::{JoinHandle, ThreadId};
// use std::time::Instant;

// use error_stack::Report;
// use invisible_backend::perpetual::perp_helpers::perp_rollback::PerpRollbackInfo;
// use invisible_backend::transactions::{
//     deposit::Deposit,
//     limit_order::LimitOrder,
//     swap::{Swap, SwapResponse},
//     transaction_helpers::rollbacks::RollbackInfo,
//     withdrawal::Withdrawal,
// };
// use invisible_backend::utils::{errors::TransactionExecutionError, notes::Note};
// use num_bigint::{BigInt, BigUint};
// use num_traits::{One, Zero};

// use invisible_backend::server::transaction_batch::TransactionBatch;
// use invisible_backend::starkware_crypto::EcPoint;

// #[test]
// fn test_spot_swaps() {
//     let _pk1 = BigUint::from_str("8932749863246329746327463249328632").unwrap();

//     let n: u64 = 1;

//     let rollback_safeguard: Arc<Mutex<HashMap<ThreadId, RollbackInfo>>> =
//         Arc::new(Mutex::new(HashMap::new()));
//     let perp_rollback_safeguard: Arc<Mutex<HashMap<ThreadId, PerpRollbackInfo>>> =
//         Arc::new(Mutex::new(HashMap::new()));
//     let mut tx_batch = TransactionBatch::new(40, 32, rollback_safeguard, perp_rollback_safeguard);

//     let deposit1 = get_dummy_deposits(n)[0].clone();
//     let deposit2 = get_dummy_deposits(n)[1].clone();

//     let note1 = deposit1.notes[0].clone();
//     let note2 = deposit2.notes[0].clone();

//     let deposits_vec: Vec<Deposit> = vec![deposit1.clone(); n as usize];

//     let now = Instant::now();

//     let mut handles: Vec<
//         JoinHandle<
//             Result<(Option<SwapResponse>, Option<Vec<u64>>), Report<TransactionExecutionError>>,
//         >,
//     > = Vec::new();
//     for deposit in deposits_vec {
//         let handle = tx_batch.execute_transaction(deposit);
//         handles.push(handle);
//     }

//     for handle in handles {
//         let (_, _) = handle.join().unwrap().unwrap();
//     }

//     println!("Time to execute deposits: {:?}", now.elapsed());

//     // ============================================================================================

//     let swap_data = get_dummy_spot_swaps(note1, note2, n);

//     let now = Instant::now();

//     let mut handles: Vec<
//         JoinHandle<
//             Result<(Option<SwapResponse>, Option<Vec<u64>>), Report<TransactionExecutionError>>,
//         >,
//     > = Vec::new();
//     for swap in swap_data {
//         let handle = tx_batch.execute_transaction(swap);
//         handles.push(handle);
//     }

//     let mut out_notes: Vec<Note> = Vec::new();
//     // let mut outputs: Vec<Option<SwapResponse>> = Vec::new();
//     for handle in handles {
//         let res = handle.join().unwrap();

//         out_notes.push(
//             res.as_ref()
//                 .unwrap()
//                 .0
//                 .as_ref()
//                 .unwrap()
//                 .swap_note_a
//                 .clone(),
//         );
//         out_notes.push(
//             res.as_ref()
//                 .unwrap()
//                 .0
//                 .as_ref()
//                 .unwrap()
//                 .swap_note_b
//                 .clone(),
//         );

//         // outputs.push(res);
//     }

//     println!("Time to execute swaps: {:?}", now.elapsed());

//     // ============================================================================================

//     // let withdrawals = get_dummy_withdrawals(out_notes);

//     // let mut handles: Vec<JoinHandle<(Option<SwapResponse>, Option<Vec<u64>>)>> = Vec::new();
//     // for withdrawal in withdrawals {
//     //     let handle = tx_batch.execute_transaction(withdrawal);
//     //     handles.push(handle);
//     // }
//     // for handle in handles {
//     //     handle.join().unwrap();
//     // }

//     // println!(
//     //     "state tree: {:#?}",
//     //     tx_batch.state_tree.lock().unwrap().leaf_nodes
//     // );
// }
// //

// fn get_dummy_deposits(n: u64) -> Vec<Deposit> {
//     let pk1 = BigInt::from_str("8932749863246329746327463249328632").unwrap();
//     let address1 = EcPoint::from_priv_key(&pk1);

//     let mut deposits: Vec<Deposit> = Vec::new();

//     for i in 0..n {
//         let note1 = Note::new(
//             0,
//             address1.clone(),
//             0,
//             100_000_000,
//             BigUint::from_str("1").unwrap(),
//         );

//         let note2 = Note::new(
//             0,
//             address1.clone(),
//             1,
//             1_000_000,
//             BigUint::from_str("1").unwrap(),
//         );

//         let deposit1 = Deposit::new(
//             i,
//             0,
//             100_000_000,
//             address1.x.to_biguint().unwrap(),
//             vec![note1],
//             &pk1.to_biguint().unwrap(),
//         );

//         let deposit2 = Deposit::new(
//             n + i,
//             1,
//             1_000_000,
//             address1.x.to_biguint().unwrap(),
//             vec![note2],
//             &pk1.to_biguint().unwrap(),
//         );

//         deposits.push(deposit1);
//         deposits.push(deposit2);
//     }

//     return deposits;
// }

// fn get_dummy_spot_swaps(note1: Note, note2: Note, n: u64) -> Vec<Swap> {
//     let pk1 = BigInt::from_str("8932749863246329746327463249328632").unwrap();
//     let address1 = EcPoint::from_priv_key(&pk1);

//     let mut swap_data: Vec<Swap> = Vec::new();
//     for i in 0..n {
//         let mut note1 = note1.clone();
//         note1.index = 2 * i;

//         let refund_note1 = Note::new(
//             note1.index,
//             note1.address.clone(),
//             note1.token,
//             0,
//             note1.blinding.clone(),
//         );

//         let mut note2 = note2.clone();
//         note2.index = 2 * i + 1;

//         let refund_note2 = Note::new(
//             note2.index,
//             note2.address.clone(),
//             note2.token,
//             0,
//             note2.blinding.clone(),
//         );

//         let limit_order1 = LimitOrder::new(
//             i,
//             10000,
//             0,
//             1,
//             100_000_000,
//             1_000_000,
//             0,
//             EcPoint {
//                 x: BigInt::zero(),
//                 y: BigInt::one(),
//             },
//             address1.clone(),
//             BigUint::zero(),
//             BigUint::zero(),
//             vec![note1],
//             Some(refund_note1),
//         );

//         let limit_order2 = LimitOrder::new(
//             n + i,
//             10000,
//             1,
//             0,
//             1_000_000,
//             100_000_000,
//             0,
//             EcPoint {
//                 x: BigInt::zero(),
//                 y: BigInt::one(),
//             },
//             address1.clone(),
//             BigUint::zero(),
//             BigUint::zero(),
//             vec![note2.clone()],
//             Some(refund_note2.clone()),
//         );

//         let sig1 = limit_order1.sign_order(vec![&pk1.to_biguint().unwrap()]);
//         let sig2 = limit_order2.sign_order(vec![&pk1.to_biguint().unwrap()]);

//         let swap = Swap::new(
//             limit_order1,
//             limit_order2,
//             sig1,
//             sig2,
//             100_000_000,
//             1_000_000,
//             0,
//             0,
//         );

//         swap_data.push(swap);
//     }

//     return swap_data;
// }

// fn _get_dummy_withdrawals(notes: Vec<Note>) -> Vec<Withdrawal> {
//     let pk1 = BigInt::from_str("8932749863246329746327463249328632").unwrap();
//     let address1 = EcPoint::from_priv_key(&pk1);

//     let mut withdrawals: Vec<Withdrawal> = Vec::new();
//     for note in notes {
//         let refund_note = Note::new(
//             note.index,
//             note.address.clone(),
//             note.token,
//             0,
//             note.blinding.clone(),
//         );

//         let withdrawal = Withdrawal {
//             transaction_type: "withdrawal".to_string(),
//             notes_in: vec![note],
//             refund_note: Some(refund_note),
//             withdrawal_token: note.token,
//             withdrawal_amount: note.amount,
//             stark_key: address1.x.to_biguint().unwrap(),
//             signature
//         }
//         //     note.token,
//         //     note.amount,
//         //     address1.x.to_biguint().unwrap(),
//         //     vec![note],
//         //     Some(refund_note),
//         //     vec![&pk1.clone().to_biguint().unwrap()],
//         // );

//         withdrawals.push(withdrawal);
//     }

//     return withdrawals;
// }
