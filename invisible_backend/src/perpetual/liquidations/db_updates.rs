use std::sync::Arc;

use firestore_db_and_auth::ServiceSession;
use parking_lot::Mutex;

use crate::{
    perpetual::perp_position::PerpPosition,
    utils::{
        firestore::{
            start_add_note_thread, start_add_position_thread, start_delete_note_thread,
            start_delete_position_thread,
        },
        storage::BackupStorage,
    },
};

use super::liquidation_order::LiquidationOrder;

pub fn update_db_after_liquidation_swap(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    liquidation_order: &LiquidationOrder,
    liquidated_position: &Option<PerpPosition>,
    new_position: &PerpPosition,
) {
    let mut handles = Vec::new();

    // let mut spot_removed_notes: Vec<(String, String)> = Vec::new();
    // let mut spot_added_notes: Vec<Note> = Vec::new();

    let notes_in = &liquidation_order.open_order_fields.notes_in;
    let refund_note = &liquidation_order.open_order_fields.refund_note;
    if refund_note.is_some() {
        let handle = start_add_note_thread(
            refund_note.as_ref().unwrap().clone(),
            session,
            backup_storage.clone(),
        );
        handles.push(handle);
    } else if refund_note.as_ref().unwrap().address.x != notes_in[0].address.x {
        //
        let n0 = &notes_in[0];
        let handle =
            start_delete_note_thread(session, n0.address.x.to_string(), n0.index.to_string());
        handles.push(handle);
    }

    // ? Remove the notes spent from the database -----------------------------------------
    for n in notes_in[1..].iter() {
        let handle =
            start_delete_note_thread(session, n.address.x.to_string(), n.index.to_string());
        handles.push(handle);
    }

    // ? Update/Remove Liquidated position from database -----------------------------------------
    if liquidated_position.is_some() {
        let handle = start_add_position_thread(
            liquidated_position.as_ref().unwrap().clone(),
            session,
            backup_storage.clone(),
        );
        handles.push(handle);
    } else {
        let handle = start_delete_position_thread(
            session,
            liquidation_order.position.position_address.to_string(),
            liquidation_order.position.index.to_string(),
        );
        handles.push(handle);
    }

    // ? Store new position in database -----------------------------------------
    let handle = start_add_position_thread(new_position.clone(), session, backup_storage.clone());
    handles.push(handle);
}
