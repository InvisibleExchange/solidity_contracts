use std::sync::Arc;

use firestore_db_and_auth::ServiceSession;
use parking_lot::Mutex;

use crate::{
    transactions::limit_order::LimitOrder,
    utils::{
        firestore::{start_add_fill_thread, start_add_note_thread, start_delete_note_thread},
        notes::Note,
        storage::BackupStorage,
    },
};

use super::transaction_output::FillInfo;

// SWAPS ----------------------------------------------------

/// Remove the spent notes from the database and add the new ones as well as the refund and pfr notes (if necessary)
///
pub fn update_db_after_spot_swap(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: Arc<Mutex<BackupStorage>>,
    order_a: &LimitOrder,
    order_b: &LimitOrder,
    prev_pfr_note_a: Option<Note>,
    prev_pfr_note_b: Option<Note>,
    swap_note_a: &Note,
    swap_note_b: &Note,
    new_pfr_note_a: &Option<Note>,
    new_pfr_note_b: &Option<Note>,
) {
    let mut handles = Vec::new();

    let is_first_fill_a = prev_pfr_note_a.is_none();
    let is_first_fill_b = prev_pfr_note_b.is_none();

    // ? Delete notes spent from the database
    if is_first_fill_a {
        // ? Delete all notes in

        for n in order_a.notes_in.iter() {
            // println!("deleting note in: {:?} {}", n.address.x, n.index);

            let handle =
                start_delete_note_thread(session, n.address.x.to_string(), n.index.to_string());
            handles.push(handle);
        }

        // ? Store refund note (*if necessary)
        if order_a.refund_note.is_some() {
            // println!(
            //     "storing refund note: {:?} {}",
            //     order_a.refund_note.as_ref().unwrap().address.x,
            //     order_a.refund_note.as_ref().unwrap().index
            // );

            let handle = start_add_note_thread(
                order_a.refund_note.as_ref().unwrap().clone(),
                session,
                backup_storage.clone(),
            );
            handles.push(handle);
        }
    }
    if is_first_fill_b {
        // ? Delete all notes in
        for n in order_b.notes_in.iter() {
            // println!("deleting note in: {:?} {}", n.address.x, n.index);

            let handle =
                start_delete_note_thread(session, n.address.x.to_string(), n.index.to_string());
            handles.push(handle);
        }

        // ? Store refund note (*if necessary)
        if order_b.refund_note.is_some() {
            // println!(
            //     "storing refund note: {:?} {}",
            //     order_b.refund_note.as_ref().unwrap().address.x,
            //     order_b.refund_note.as_ref().unwrap().index
            // );

            let handle = start_add_note_thread(
                order_b.refund_note.as_ref().unwrap().clone(),
                session,
                backup_storage.clone(),
            );
            handles.push(handle);
        }
    }

    // ? Delete prev partiall fill refund notes (*if necessary)
    if prev_pfr_note_a.is_some() {
        // println!(
        //     "deleting prev pfr note: {:?} {}",
        //     prev_pfr_note_a.as_ref().unwrap().address.x,
        //     prev_pfr_note_a.as_ref().unwrap().index
        // );

        let handle = start_delete_note_thread(
            session,
            prev_pfr_note_a.as_ref().unwrap().address.x.to_string(),
            prev_pfr_note_a.as_ref().unwrap().index.to_string(),
        );
        handles.push(handle);
    }
    if prev_pfr_note_b.is_some() {
        // println!(
        //     "deleting prev pfr note: {:?} {}",
        //     prev_pfr_note_b.as_ref().unwrap().address.x,
        //     prev_pfr_note_b.as_ref().unwrap().index
        // );

        let handle = start_delete_note_thread(
            session,
            prev_pfr_note_b.as_ref().unwrap().address.x.to_string(),
            prev_pfr_note_b.as_ref().unwrap().index.to_string(),
        );
        handles.push(handle);
    }

    // println!(
    //     "storing swap note: a {:?} {}",
    //     swap_note_a.address.x, swap_note_a.index
    // );

    // ? Store swap notes
    let handle = start_add_note_thread(swap_note_a.clone(), session, backup_storage.clone());
    handles.push(handle);

    // println!(
    //     "storing swap note: b {:?} {}",
    //     swap_note_b.address.x, swap_note_b.index
    // );

    let handle = start_add_note_thread(swap_note_b.clone(), session, backup_storage.clone());
    handles.push(handle);

    // ? Store partial fill refund notes if order was partially filled
    if new_pfr_note_a.is_some() {
        // println!(
        //     "storing new pfr note: {:?} {}",
        //     new_pfr_note_a.as_ref().unwrap().address.x,
        //     new_pfr_note_a.as_ref().unwrap().index
        // );

        let handle = start_add_note_thread(
            new_pfr_note_a.as_ref().unwrap().clone(),
            session,
            backup_storage.clone(),
        );
        handles.push(handle);
    }
    if new_pfr_note_b.is_some() {
        // println!(
        //     "storing new pfr note: {:?} {}",
        //     new_pfr_note_b.as_ref().unwrap().address.x,
        //     new_pfr_note_b.as_ref().unwrap().index
        // );

        let handle = start_add_note_thread(
            new_pfr_note_b.as_ref().unwrap().clone(),
            session,
            backup_storage.clone(),
        );
        handles.push(handle);
    }
}

pub fn store_spot_fill(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: Arc<Mutex<BackupStorage>>,
    amount: u64,
    price: u64,
    user_id_a: u64,
    user_id_b: u64,
    base_token: u64,
    quote_token: u64,
    is_buy: bool,
    timestamp: u64,
) {
    let fill_info = FillInfo {
        amount,
        price,
        user_id_a: user_id_a.to_string(),
        user_id_b: user_id_b.to_string(),
        base_token,
        quote_token,
        timestamp,
        is_buy,
    };

    let _handle = start_add_fill_thread(fill_info, session, backup_storage);

    println!("storing spot fill");
}

// DEPOSITS -----------------------------------------------------

/// Add all the newly generated deposit notes (in most cases only one) to the database
pub fn update_db_after_deposit(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: Arc<Mutex<BackupStorage>>,
    new_notes: Vec<Note>,
    zero_indexes: &Vec<u64>,
) {
    let mut handles = Vec::new();

    for (mut note, z_idx) in new_notes.into_iter().zip(zero_indexes.iter()) {
        note.index = *z_idx;
        let handle = start_add_note_thread(note.clone(), session, backup_storage.clone());
        handles.push(handle);
    }
}

// WITHDRAWAL ----------------------------------------------------

/// Remove the withdrawn notes from the database and add the refund note (if necessary)
pub fn update_db_after_withdrawal(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: Arc<Mutex<BackupStorage>>,
    notes_in: &Vec<Note>,
    refund_note: Option<Note>,
) {
    let mut handles = Vec::new();

    if refund_note.is_some() {
        let handle = start_add_note_thread(refund_note.unwrap(), session, backup_storage);
        handles.push(handle);
    } else {
        let handle = start_delete_note_thread(
            session,
            notes_in[0].address.x.to_string(),
            notes_in[0].index.to_string(),
        );
        handles.push(handle);
    }

    for n in notes_in.into_iter().skip(1) {
        let handle =
            start_delete_note_thread(session, n.address.x.to_string(), n.index.to_string());
        handles.push(handle);
    }
}

// NOTE SPLITS -----------------------------------------------------
/// Remove the old notes from the database and add the new ones
pub fn update_db_after_note_split(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    notes_in: Vec<Note>,
    notes_out: Vec<Note>,
    zero_idxs: &Vec<u64>,
) {
    let mut handles = Vec::new();

    for note in notes_in {
        let handle =
            start_delete_note_thread(session, note.address.x.to_string(), note.index.to_string());
        handles.push(handle);
    }

    for (i, mut note) in notes_out.into_iter().enumerate() {
        note.index = zero_idxs[i];

        let handle = start_add_note_thread(note, session, backup_storage.clone());
        handles.push(handle);
    }
}
