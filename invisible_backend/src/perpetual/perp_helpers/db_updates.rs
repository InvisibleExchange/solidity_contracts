use std::sync::Arc;

use firestore_db_and_auth::ServiceSession;
use parking_lot::Mutex;

use crate::{
    perpetual::{perp_order::PerpOrder, perp_position::PerpPosition, PositionEffectType},
    transactions::transaction_helpers::transaction_output::PerpFillInfo,
    utils::{
        firestore::{
            start_add_note_thread, start_add_perp_fill_thread, start_add_position_thread,
            start_delete_note_thread, start_delete_position_thread,
        },
        notes::Note,
        storage::BackupStorage,
    },
};

pub fn update_db_after_perp_swap(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: Arc<Mutex<BackupStorage>>,
    order_a: &PerpOrder,
    order_b: &PerpOrder,
    prev_pfr_note_a: &Option<Note>,
    prev_pfr_note_b: &Option<Note>,
    new_pfr_note_a: &Option<Note>,
    new_pfr_note_b: &Option<Note>,
    return_collateral_note_a: &Option<Note>,
    return_collateral_note_b: &Option<Note>,
    position_a: &Option<PerpPosition>,
    position_b: &Option<PerpPosition>,
    // swap_response: &PerpSwapResponse,
) {
    let mut handles = Vec::new();

    // ? Remove the notes spent from the database if necessary ==============================================================
    if order_a.position_effect_type == PositionEffectType::Open {
        let is_first_fill = prev_pfr_note_a.is_none();

        if is_first_fill {
            // ? Store refund note (*if necessary) -----------------------------------------

            let refund_note_a = &order_a.open_order_fields.as_ref().unwrap().refund_note;
            if refund_note_a.is_some() {
                let handle = start_add_note_thread(
                    refund_note_a.as_ref().unwrap().clone(),
                    session,
                    backup_storage.clone(),
                );
                handles.push(handle);
            }
            if refund_note_a.is_none()
                || refund_note_a.as_ref().unwrap().address.x
                    != order_a.open_order_fields.as_ref().unwrap().notes_in[0]
                        .address
                        .x
            {
                let n0 = &order_a.open_order_fields.as_ref().unwrap().notes_in[0];
                let handle = start_delete_note_thread(
                    session,
                    n0.address.x.to_string(),
                    n0.index.to_string(),
                );
                handles.push(handle);
            }

            // ? Remove the notes spent from the database -----------------------------------------
            for n in order_a.open_order_fields.as_ref().unwrap().notes_in[1..].iter() {
                let handle =
                    start_delete_note_thread(session, n.address.x.to_string(), n.index.to_string());
                handles.push(handle);
            }
        } else {
            // ? Remove the previous partial fill refund note -----------------------------------------
            let handle = start_delete_note_thread(
                session,
                prev_pfr_note_a.as_ref().unwrap().address.x.to_string(),
                prev_pfr_note_a.as_ref().unwrap().index.to_string(),
            );
            handles.push(handle);
        }

        // ? store partial fill refund notes (if necessary)
        if new_pfr_note_a.is_some() {
            let handle = start_add_note_thread(
                new_pfr_note_a.as_ref().unwrap().clone(),
                session,
                backup_storage.clone(),
            );
            handles.push(handle);
        }
    }
    if order_b.position_effect_type == PositionEffectType::Open {
        let is_first_fill = prev_pfr_note_b.is_none();

        if is_first_fill {
            // ? Store refund note (*if necessary) -----------------------------------------

            let refund_note_b = &order_b.open_order_fields.as_ref().unwrap().refund_note;
            if refund_note_b.is_some() {
                let handle = start_add_note_thread(
                    refund_note_b.as_ref().unwrap().clone(),
                    session,
                    backup_storage.clone(),
                );
                handles.push(handle);
            }
            if refund_note_b.is_none()
                || refund_note_b.as_ref().unwrap().address.x
                    != order_b.open_order_fields.as_ref().unwrap().notes_in[0]
                        .address
                        .x
            {
                let n0 = &order_b.open_order_fields.as_ref().unwrap().notes_in[0];
                let handle = start_delete_note_thread(
                    session,
                    n0.address.x.to_string(),
                    n0.index.to_string(),
                );
                handles.push(handle);
            }

            // ? Remove the notes spent from the database -----------------------------------------
            for n in order_b.open_order_fields.as_ref().unwrap().notes_in[1..].iter() {
                let handle =
                    start_delete_note_thread(session, n.address.x.to_string(), n.index.to_string());
                handles.push(handle);
            }
        } else {
            // ? Remove the previous partial fill refund note
            let handle = start_delete_note_thread(
                session,
                prev_pfr_note_b.as_ref().unwrap().address.x.to_string(),
                prev_pfr_note_b.as_ref().unwrap().index.to_string(),
            );
            handles.push(handle);
        }

        // ? store partial fill refund notes (if necessary)
        if new_pfr_note_b.is_some() {
            let handle = start_add_note_thread(
                new_pfr_note_b.as_ref().unwrap().clone(),
                session,
                backup_storage.clone(),
            );
            handles.push(handle);
        }
    }

    // ? Store the return collateral note and remove closed positions (when necessary)
    if order_a.position_effect_type == PositionEffectType::Close {
        if order_a.position_effect_type == PositionEffectType::Close {
            let handle = start_add_note_thread(
                return_collateral_note_a.as_ref().unwrap().clone(),
                session,
                backup_storage.clone(),
            );
            handles.push(handle);
        }

        if position_a.is_none() {
            let handle = start_delete_position_thread(
                session,
                order_a
                    .position
                    .as_ref()
                    .unwrap()
                    .position_address
                    .to_string(),
                order_a.position.as_ref().unwrap().index.to_string(),
            );
            handles.push(handle);
        }
    }
    if order_b.position_effect_type == PositionEffectType::Close {
        if order_b.position_effect_type == PositionEffectType::Close {
            let handle = start_add_note_thread(
                return_collateral_note_b.as_ref().unwrap().clone(),
                session,
                backup_storage.clone(),
            );
            handles.push(handle);
        }

        if position_b.is_none() {
            let handle = start_delete_position_thread(
                session,
                order_b
                    .position
                    .as_ref()
                    .unwrap()
                    .position_address
                    .to_string(),
                order_b.position.as_ref().unwrap().index.to_string(),
            );
            handles.push(handle);
        }
    }

    // ? Store the updated position (if necessary)
    if position_a.is_some() {
        let handle = start_add_position_thread(
            position_a.as_ref().unwrap().clone(),
            session,
            backup_storage.clone(),
        );
        handles.push(handle);
    }
    if position_b.is_some() {
        let handle = start_add_position_thread(
            position_b.as_ref().unwrap().clone(),
            session,
            backup_storage.clone(),
        );
        handles.push(handle);
    }
}

// Store perp fill

pub fn store_perp_fill(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: Arc<Mutex<BackupStorage>>,
    amount: u64,
    price: u64,
    user_id_a: u64,
    user_id_b: u64,
    synthetic_token: u64,
    is_buy: bool,
    timestamp: u64,
) {
    let fill_info = PerpFillInfo {
        amount,
        price,
        user_id_a: user_id_a.to_string(),
        user_id_b: user_id_b.to_string(),
        timestamp,
        synthetic_token,
        is_buy,
    };

    let _handle = start_add_perp_fill_thread(fill_info, session, backup_storage);
}
