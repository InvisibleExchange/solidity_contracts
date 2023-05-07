use invisible_backend::perpetual::perp_helpers::perp_rollback::PerpRollbackInfo;
use parking_lot::Mutex;
use std::collections::HashMap;
use std::str::FromStr;
use std::sync::Arc;
use std::thread::ThreadId;
use std::time::Instant;

use invisible_backend::perpetual::perp_order::OpenOrderFields;
use invisible_backend::perpetual::{perp_order::PerpOrder, OrderSide};
use invisible_backend::transactions::transaction_helpers::rollbacks::RollbackInfo;
use invisible_backend::transactions::{deposit::Deposit, limit_order::LimitOrder, swap::Swap};
use invisible_backend::utils::notes::Note;
use num_bigint::{BigInt, BigUint};
use num_traits::{One, Zero};

use invisible_backend::starkware_crypto::EcPoint;

use invisible_backend::{
    perpetual::perp_swap::PerpSwap, transaction_batch::transaction_batch::TransactionBatch,
};

//

#[test]
fn test_sequential_perp_fills() {
    let _n: u64 = 1;

    let rollback_safeguard: Arc<Mutex<HashMap<ThreadId, RollbackInfo>>> =
        Arc::new(Mutex::new(HashMap::new()));
    let perp_rollback_safeguard: Arc<Mutex<HashMap<ThreadId, PerpRollbackInfo>>> =
        Arc::new(Mutex::new(HashMap::new()));
    let mut tx_batch = TransactionBatch::new(4, 4, rollback_safeguard, perp_rollback_safeguard);

    let (deposit1, deposit2, deposit3) = get_perp_deposits();

    let note1 = deposit1.notes[0].clone();

    let z_idx1 = tx_batch
        .execute_transaction(deposit1)
        .join()
        .unwrap()
        .unwrap()
        .1
        .unwrap()[0];
    let z_idx2 = tx_batch
        .execute_transaction(deposit2)
        .join()
        .unwrap()
        .unwrap()
        .1
        .unwrap()[0];
    let z_idx3 = tx_batch
        .execute_transaction(deposit3)
        .join()
        .unwrap()
        .unwrap()
        .1
        .unwrap()[0];

    // ---------------------------------------------------------------------------------------

    let (perp_swap1, perp_swap2) = get_dummy_open_order_swaps(note1, vec![z_idx1, z_idx2, z_idx3]);

    let now = Instant::now();
    let handle1 = tx_batch.execute_perpetual_transaction(perp_swap1);
    let handle2 = tx_batch.execute_perpetual_transaction(perp_swap2);

    let _res1 = handle1.join().unwrap();
    let _res2 = handle2.join().unwrap();

    //

    println!("time for swap: {:?}", now.elapsed());

    println!("state tree: {:#?}", tx_batch.state_tree.lock().leaf_nodes);

    let now = Instant::now();
    tx_batch.finalize_batch().expect("err");
    println!("time for finalization: {:?}", now.elapsed());

    println!("All good: ");

    //

    //
}

//

#[test]
fn test_sequential_spot_fills() {
    let rollback_safeguard: Arc<Mutex<HashMap<ThreadId, RollbackInfo>>> =
        Arc::new(Mutex::new(HashMap::new()));
    let perp_rollback_safeguard: Arc<Mutex<HashMap<ThreadId, PerpRollbackInfo>>> =
        Arc::new(Mutex::new(HashMap::new()));
    let mut tx_batch = TransactionBatch::new(4, 4, rollback_safeguard, perp_rollback_safeguard);

    let (deposit1, deposit2, deposit3) = get_spot_deposits();

    let note1 = deposit1.notes[0].clone();
    let note2 = deposit2.notes[0].clone();

    let z_idx1 = tx_batch
        .execute_transaction(deposit1)
        .join()
        .unwrap()
        .unwrap()
        .1
        .unwrap()[0];
    let z_idx2 = tx_batch
        .execute_transaction(deposit2)
        .join()
        .unwrap()
        .unwrap()
        .1
        .unwrap()[0];
    let z_idx3 = tx_batch
        .execute_transaction(deposit3)
        .join()
        .unwrap()
        .unwrap()
        .1
        .unwrap()[0];

    let (swap1, swap2) = get_dummy_spot_swaps(note1, note2, vec![z_idx1, z_idx2, z_idx3]);

    let now = Instant::now();
    let handle1 = tx_batch.execute_transaction(swap1);
    let handle2 = tx_batch.execute_transaction(swap2);

    let res1 = handle1.join().unwrap();
    let res2 = handle2.join().unwrap();

    println!("swap1: {:#?}\n", res1.unwrap().0.unwrap());
    println!("swap2: {:#?}\n", res2.unwrap().0.unwrap());

    //

    println!("time for swap: {:?}", now.elapsed());

    println!("state {:#?}", tx_batch.state_tree.lock().leaf_nodes);
    tx_batch.finalize_batch().expect("err");
}

//

//

fn get_perp_deposits() -> (Deposit, Deposit, Deposit) {
    let pk1 = BigInt::from_str("89327498632463297463274632493286132").unwrap();
    let address1 = EcPoint::from_priv_key(&pk1);

    let note = Note::new(
        0,
        address1.clone(),
        55555,
        100_000_000,
        BigUint::from_str("1").unwrap(),
    );

    let deposit1 = Deposit::new(
        1,
        55555,
        100_000_000,
        address1.x.to_biguint().unwrap(),
        vec![note.clone()],
        &pk1.to_biguint().unwrap(),
    );

    let deposit2 = Deposit::new(
        2,
        55555,
        100_000_000,
        address1.x.to_biguint().unwrap(),
        vec![note.clone()],
        &pk1.to_biguint().unwrap(),
    );

    let deposit3 = Deposit::new(
        3,
        55555,
        100_000_000,
        address1.x.to_biguint().unwrap(),
        vec![note.clone()],
        &pk1.to_biguint().unwrap(),
    );

    return (deposit1, deposit2, deposit3);
}

fn get_dummy_open_order_swaps(note_: Note, z_idxs: Vec<u64>) -> (PerpSwap, PerpSwap) {
    let pk1 = BigInt::from_str("89327498632463297463274632493286132").unwrap();
    let address1 = EcPoint::from_priv_key(&pk1).x.to_biguint().unwrap();
    let pk2 = BigInt::from_str("32875426429834347923748248234235723").unwrap();
    let address2 = EcPoint::from_priv_key(&pk2).x.to_biguint().unwrap();
    let pk3 = BigInt::from_str("72562893579235823562367487236523532").unwrap();
    let address3 = EcPoint::from_priv_key(&pk3).x.to_biguint().unwrap();

    let mut note1 = note_.clone();
    note1.index = z_idxs[0];
    let refund_note1 = Note::new(
        z_idxs[0],
        note1.address.clone(),
        note1.token,
        0,
        note1.blinding.clone(),
    );

    let mut note2 = note_.clone();
    note2.index = z_idxs[1];
    let refund_note2 = Note::new(
        z_idxs[1],
        note2.address.clone(),
        note2.token,
        30_000_000,
        note2.blinding.clone(),
    );

    let mut note3 = note_.clone();
    note3.index = z_idxs[2];
    let refund_note3 = Note::new(
        z_idxs[2],
        note3.address.clone(),
        note3.token,
        70_000_000,
        note3.blinding.clone(),
    );

    let expiration_timestamp = 10000;
    let synthetic_token = 54321;
    let collateral_token = 55555;
    // --- ---- --- ---- ----

    let order_id = 1;
    let order_side = OrderSide::Long;
    let synthetic_amount = 1_000_000;
    let collateral_amount = 100_000_000;
    let initial_margin = 100_000_000;
    let fee_limit = 0;
    let notes_in = vec![note1];
    let refund_note = Some(refund_note1);

    let open_order_fields = OpenOrderFields {
        initial_margin,
        collateral_token,
        notes_in,
        refund_note,
        position_address: address1.clone(),
        blinding: BigUint::one(),
    };

    let perp_order1 = PerpOrder::new_open_order(
        order_id,
        expiration_timestamp,
        order_side,
        synthetic_token,
        synthetic_amount,
        collateral_amount,
        fee_limit,
        open_order_fields,
    );

    // --- ---- --- ---- ----  ----- --- ---- ---- ---- -----

    let order_id = 2;
    let order_side = OrderSide::Short;
    let synthetic_amount = 700_000;
    let collateral_amount = 70_000_000;
    let initial_margin = 70_000_000;
    let fee_limit = 0;
    let notes_in = vec![note2];
    let refund_note = Some(refund_note2);

    let open_order_fields = OpenOrderFields {
        initial_margin,
        collateral_token,
        notes_in,
        refund_note,
        position_address: address2.clone(),
        blinding: BigUint::one(),
    };

    let perp_order2 = PerpOrder::new_open_order(
        order_id,
        expiration_timestamp,
        order_side,
        synthetic_token,
        synthetic_amount,
        collateral_amount,
        fee_limit,
        open_order_fields,
    );

    // --- ---- --- ---- ----  ----- --- ---- ---- ---- -----

    let order_id = 3;
    let order_side = OrderSide::Short;
    let synthetic_amount = 300_000;
    let collateral_amount = 30_000_000;
    let initial_margin = 30_000_000;
    let fee_limit = 0;
    let notes_in = vec![note3];
    let refund_note = Some(refund_note3);

    let open_order_fields = OpenOrderFields {
        initial_margin,
        collateral_token,
        notes_in,
        refund_note,
        position_address: address3.clone(),
        blinding: BigUint::one(),
    };

    let perp_order3 = PerpOrder::new_open_order(
        order_id,
        expiration_timestamp,
        order_side,
        synthetic_token,
        synthetic_amount,
        collateral_amount,
        fee_limit,
        open_order_fields,
    );

    // --- ---- --- ---- ----  ----- --- ---- ---- ---- -----

    let signature1 = perp_order1.sign_order(
        //
        Some(vec![&pk1.to_biguint().unwrap()]),
        None,
    );
    let signature2 = perp_order2.sign_order(
        //
        Some(vec![&pk1.to_biguint().unwrap()]),
        None,
    );
    let signature3 = perp_order3.sign_order(
        //
        Some(vec![&pk1.to_biguint().unwrap()]),
        None,
    );

    let swap1 = PerpSwap::new(
        perp_order1.clone(),
        perp_order2,
        Some(signature1.clone()),
        Some(signature2),
        70_000_000,
        700_000,
        0,
        0,
    );

    let swap2 = PerpSwap::new(
        perp_order1.clone(),
        perp_order3,
        Some(signature1),
        Some(signature3),
        30_000_000,
        300_000,
        0,
        0,
    );

    return (swap1, swap2);
}

fn get_spot_deposits() -> (Deposit, Deposit, Deposit) {
    let pk1 = BigInt::from_str("89327498632463297463274632493286132").unwrap();
    let address1 = EcPoint::from_priv_key(&pk1);

    let note = Note::new(
        0,
        address1.clone(),
        12345,
        100_000_000,
        BigUint::from_str("1").unwrap(),
    );

    let note2 = Note::new(
        0,
        address1.clone(),
        54321,
        5_000_000,
        BigUint::from_str("1").unwrap(),
    );

    let deposit1 = Deposit::new(
        1,
        12345,
        100_000_000,
        address1.x.to_biguint().unwrap(),
        vec![note],
        &pk1.to_biguint().unwrap(),
    );

    let deposit2 = Deposit::new(
        2,
        54321,
        5_000_000,
        address1.x.to_biguint().unwrap(),
        vec![note2.clone()],
        &pk1.to_biguint().unwrap(),
    );

    let deposit3 = Deposit::new(
        3,
        54321,
        5_000_000,
        address1.x.to_biguint().unwrap(),
        vec![note2.clone()],
        &pk1.to_biguint().unwrap(),
    );

    return (deposit1, deposit2, deposit3);
}

fn get_dummy_spot_swaps(note1_: Note, note2_: Note, z_idxs: Vec<u64>) -> (Swap, Swap) {
    let pk1 = BigInt::from_str("89327498632463297463274632493286132").unwrap();
    let address1 = EcPoint::from_priv_key(&pk1);

    let mut note1 = note1_.clone();
    note1.index = z_idxs[0];
    let refund_note1 = Note::new(
        z_idxs[0],
        note1.address.clone(),
        note1.token,
        50_000_000,
        note1.blinding.clone(),
    );

    let mut note2 = note2_.clone();
    note2.index = z_idxs[1];
    let refund_note2 = Note::new(
        z_idxs[1],
        note2.address.clone(),
        note2.token,
        2_500_000,
        note2.blinding.clone(),
    );

    let mut note3 = note2_.clone();
    note3.index = z_idxs[2];
    let refund_note3 = Note::new(
        z_idxs[2],
        note3.address.clone(),
        note3.token,
        2_500_000,
        note3.blinding.clone(),
    );

    let limit_order1 = LimitOrder::new(
        1,
        10000,
        12345,
        54321,
        50_000_000,
        5_000_000,
        0,
        address1.clone(),
        address1.clone(),
        BigUint::zero(),
        BigUint::zero(),
        vec![note1],
        Some(refund_note1),
    );

    let limit_order2 = LimitOrder::new(
        2,
        10000,
        54321,
        12345,
        2_500_000,
        25_000_000,
        0,
        address1.clone(),
        address1.clone(),
        BigUint::zero(),
        BigUint::zero(),
        vec![note2],
        Some(refund_note2),
    );

    let limit_order3 = LimitOrder::new(
        3,
        10000,
        54321,
        12345,
        2_500_000,
        25_000_000,
        0,
        address1.clone(),
        address1.clone(),
        BigUint::zero(),
        BigUint::zero(),
        vec![note3],
        Some(refund_note3),
    );

    let sig1 = limit_order1.sign_order(vec![&pk1.to_biguint().unwrap()]);
    let sig2 = limit_order2.sign_order(vec![&pk1.to_biguint().unwrap()]);
    let sig3 = limit_order3.sign_order(vec![&pk1.to_biguint().unwrap()]);

    let swap1 = Swap::new(
        limit_order1.clone(),
        limit_order2,
        sig1.clone(),
        sig2,
        25_000_000,
        2_500_000,
        0,
        0,
    );

    let swap2 = Swap::new(
        limit_order1.clone(),
        limit_order3,
        sig1,
        sig3,
        25_000_000,
        2_500_000,
        0,
        0,
    );

    return (swap1, swap2);
}
