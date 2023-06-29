use std::{collections::HashMap, sync::Arc, thread::JoinHandle};

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
    backup_storage: &Arc<Mutex<BackupStorage>>,
    order_a: &LimitOrder,
    order_b: &LimitOrder,
    prev_pfr_note_a: Option<Note>,
    prev_pfr_note_b: Option<Note>,
    swap_note_a: &Note,
    swap_note_b: &Note,
    new_pfr_note_a: &Option<Note>,
    new_pfr_note_b: &Option<Note>,
) {
    let mut delete_notes: Vec<(u64, String)> = Vec::new();
    let mut add_notes: Vec<&Note> = Vec::new();

    let is_first_fill_a = prev_pfr_note_a.is_none();
    let is_first_fill_b = prev_pfr_note_b.is_none();

    // ? Delete notes spent from the database
    if is_first_fill_a {
        if order_a.refund_note.is_some() {
            // ? Store the refund note in place of the first note
            add_notes.push(&order_a.refund_note.as_ref().unwrap())
        }

        // ? Delete all notes in
        for n in order_a.notes_in.iter() {
            delete_notes.push((n.index, n.address.x.to_string()))
        }
    }
    if is_first_fill_b {
        // ? Store refund note (*if necessary)
        if order_b.refund_note.is_some() {
            add_notes.push(&order_b.refund_note.as_ref().unwrap())
        }

        // ? Delete all notes in
        for n in order_b.notes_in.iter() {
            delete_notes.push((n.index, n.address.x.to_string()))
        }
    }

    // ? Delete prev partially fill refund notes (*if necessary)
    if prev_pfr_note_a.is_some() {
        let n = prev_pfr_note_a.as_ref().unwrap();
        delete_notes.push((n.index, n.address.x.to_string()));
    }
    if prev_pfr_note_b.is_some() {
        let n = prev_pfr_note_b.as_ref().unwrap();
        delete_notes.push((n.index, n.address.x.to_string()));
    }

    // ? Store swap notes
    add_notes.push(&swap_note_a);
    add_notes.push(&swap_note_b);

    // ? Store partial fill refund notes if order was partially filled
    if new_pfr_note_a.is_some() {
        add_notes.push(&new_pfr_note_a.as_ref().unwrap());
    }
    if new_pfr_note_b.is_some() {
        add_notes.push(&new_pfr_note_b.as_ref().unwrap());
    }

    let updater = DbNoteUpdater {
        session,
        backup_storage,
        delete_notes,
        add_notes,
    };

    let _handles = updater.update_db();
}

pub fn store_spot_fill(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
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
}

// DEPOSITS -----------------------------------------------------

/// Add all the newly generated deposit notes (in most cases only one) to the database
pub fn update_db_after_deposit(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    new_notes: Vec<Note>,
    zero_indexes: &Vec<u64>,
) {
    let mut _handles = Vec::new();

    for (mut note, z_idx) in new_notes.into_iter().zip(zero_indexes.iter()) {
        note.index = *z_idx;
        let handle = start_add_note_thread(note.clone(), session, backup_storage);
        _handles.push(handle);
    }
}

// WITHDRAWAL ----------------------------------------------------

/// Remove the withdrawn notes from the database and add the refund note (if necessary)
pub fn update_db_after_withdrawal(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    notes_in: &Vec<Note>,
    refund_note: Option<Note>,
) {
    let mut delete_notes: Vec<(u64, String)> = Vec::new();
    let mut add_notes: Vec<&Note> = Vec::new();

    if refund_note.is_some() {
        // ? Store the refund note in place of the first note
        add_notes.push(&refund_note.as_ref().unwrap())
    }

    for n in notes_in.into_iter() {
        delete_notes.push((n.index, n.address.x.to_string()))
    }

    let updater = DbNoteUpdater {
        session,
        backup_storage,
        delete_notes,
        add_notes,
    };

    let _handles = updater.update_db();
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
    let mut delete_notes: Vec<(u64, String)> = Vec::new();
    let mut add_notes: Vec<Note> = Vec::new();

    for note in notes_in {
        delete_notes.push((note.index, note.address.x.to_string()))
    }

    for (i, mut note) in notes_out.into_iter().enumerate() {
        note.index = zero_idxs[i];

        add_notes.push(note.clone());
    }

    let add_notes = add_notes.iter().collect::<Vec<&Note>>();

    let updater = DbNoteUpdater {
        session,
        backup_storage,
        delete_notes,
        add_notes,
    };

    let _handles = updater.update_db();
}

pub struct DbNoteUpdater<'a> {
    pub session: &'a Arc<Mutex<ServiceSession>>,
    pub backup_storage: &'a Arc<Mutex<BackupStorage>>,
    pub delete_notes: Vec<(u64, String)>,
    pub add_notes: Vec<&'a Note>,
}

impl DbNoteUpdater<'_> {
    pub fn update_db(&self) -> Vec<JoinHandle<()>> {
        let mut _handles: Vec<_> = Vec::new();
        let mut added_notes = HashMap::new();

        for note in self.add_notes.iter() {
            let handle =
                start_add_note_thread(note.clone().clone(), self.session, self.backup_storage);
            _handles.push(handle);
            added_notes.insert((note.index, note.address.x.to_string()), false);
        }

        for deletion in self.delete_notes.iter() {
            if added_notes.contains_key(&deletion) {
                continue;
            }

            let handle = start_delete_note_thread(
                self.session,
                self.backup_storage,
                deletion.1.to_string(),
                deletion.0.to_string(),
            );
            _handles.push(handle);
        }

        return _handles;
    }
}
