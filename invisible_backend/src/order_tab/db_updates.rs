use std::sync::Arc;

use parking_lot::Mutex;

use firestore_db_and_auth::ServiceSession;

use crate::utils::{
    firestore::{
        start_add_note_thread, start_add_order_tab_thread, start_delete_note_thread,
        start_delete_order_tab_thread,
    },
    notes::Note,
    storage::BackupStorage,
};

use super::OrderTab;

/// Update the database after a new order has been opened.
pub fn open_tab_db_updates(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    order_tab: OrderTab,
    base_notes_in: &Vec<Note>,
    quote_notes_in: &Vec<Note>,
    base_refund_note: Option<Note>,
    quote_refund_note: Option<Note>,
) {
    for note in base_notes_in.into_iter() {
        let _h = start_delete_note_thread(
            session,
            backup_storage,
            note.address.x.to_string(),
            note.index.to_string(),
        );
    }
    for note in quote_notes_in.into_iter() {
        let _h = start_delete_note_thread(
            session,
            backup_storage,
            note.address.x.to_string(),
            note.index.to_string(),
        );
    }
    if let Some(note) = base_refund_note {
        let _h = start_add_note_thread(note, session, backup_storage);
    }
    if let Some(note) = quote_refund_note {
        let _h = start_add_note_thread(note, session, backup_storage);
    }

    let _h: std::thread::JoinHandle<()> =
        start_add_order_tab_thread(order_tab, session, backup_storage);
}

/// Update the database after a new order has been opened.
pub fn close_tab_db_updates(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    order_tab: &OrderTab,
    base_return_note: Note,
    quote_return_note: Note,
) {
    // ? remove the tab from the database
    let _h = start_delete_order_tab_thread(
        session,
        backup_storage,
        order_tab.tab_header.pub_key.to_string(),
        order_tab.tab_idx.to_string(),
    );

    // ? add the return notes to the state
    let _h = start_add_note_thread(base_return_note, session, backup_storage);
    let _h = start_add_note_thread(quote_return_note, session, backup_storage);
}
