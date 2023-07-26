use std::{collections::HashMap, sync::Arc};

use num_bigint::BigUint;
use parking_lot::Mutex;

use firestore_db_and_auth::ServiceSession;

use crate::{
    perpetual::perp_order::CloseOrderFields,
    server::grpc::engine_proto::CloseOrderTabReq,
    trees::superficial_tree::SuperficialTree,
    utils::{crypto_utils::pedersen_on_vec, notes::Note, storage::BackupStorage},
};

use crate::utils::crypto_utils::{verify, Signature};

use super::{db_updates::close_tab_db_updates, state_updates::close_tab_state_updates, OrderTab};

pub fn close_order_tab(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    close_order_tab_req: CloseOrderTabReq,
    state_tree: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes: &Arc<Mutex<HashMap<u64, BigUint>>>,
    order_tabs_state_tree: &Arc<Mutex<SuperficialTree>>,
    updated_tab_hashes: &Arc<Mutex<HashMap<u32, BigUint>>>,
) -> std::result::Result<(Note, Note), String> {
    if close_order_tab_req.order_tab.is_none() {
        return Err("order tab is missing".to_string());
    }
    if close_order_tab_req.base_close_order_fields.is_none()
        || close_order_tab_req.quote_close_order_fields.is_none()
    {
        return Err("close order fields are not defined".to_string());
    }
    if close_order_tab_req.signature.is_none() {
        return Err("signature is missing".to_string());
    }

    let order_tab = OrderTab::try_from(close_order_tab_req.order_tab.unwrap());
    let base_close_order_fields =
        CloseOrderFields::try_from(close_order_tab_req.base_close_order_fields.unwrap());
    let quote_close_order_fields =
        CloseOrderFields::try_from(close_order_tab_req.quote_close_order_fields.unwrap());

    if order_tab.is_err() || base_close_order_fields.is_err() || quote_close_order_fields.is_err() {
        return Err("failed to parse order tab or close order fields".to_string());
    }
    let order_tab = order_tab.unwrap();
    let base_close_order_fields = base_close_order_fields.unwrap();
    let quote_close_order_fields = quote_close_order_fields.unwrap();

    // ? Check that the order_tab_exists
    let tab_state_tree_m = order_tabs_state_tree.lock();

    let leaf_hash = tab_state_tree_m.get_leaf_by_index(order_tab.tab_idx as u64);
    if leaf_hash != order_tab.hash {
        return Err("order tab does not exist".to_string());
    }

    // ? Verify the signature --------------------------------------------------------------
    let signature = Signature::try_from(close_order_tab_req.signature.unwrap_or_default())
        .map_err(|err| err.to_string())?;
    verfiy_close_order_hash(
        &order_tab,
        &base_close_order_fields,
        &quote_close_order_fields,
        signature,
    );

    let base_token = order_tab.tab_header.base_token;
    let base_amount = order_tab.base_amount;
    let quote_token = order_tab.tab_header.quote_token;
    let quote_amount = order_tab.quote_amount;

    let mut state_tree_m = state_tree.lock();

    let zero_idx1 = state_tree_m.first_zero_idx();
    let zero_idx2 = state_tree_m.first_zero_idx();

    let base_return_note = Note::new(
        zero_idx1,
        base_close_order_fields.dest_received_address,
        base_token,
        base_amount,
        base_close_order_fields.dest_received_blinding,
    );
    let quote_return_note = Note::new(
        zero_idx2,
        quote_close_order_fields.dest_received_address,
        quote_token,
        quote_amount,
        quote_close_order_fields.dest_received_blinding,
    );

    drop(tab_state_tree_m);

    // ? UPDATE THE STATE -----------------------------------------------------------------
    close_tab_state_updates(
        state_tree,
        updated_note_hashes,
        order_tabs_state_tree,
        updated_tab_hashes,
        &order_tab,
        base_return_note.clone(),
        quote_return_note.clone(),
    );

    // ? UPDATE THE DATABASE ---------------------------------------------------------------
    close_tab_db_updates(
        session,
        backup_storage,
        &order_tab,
        base_return_note.clone(),
        quote_return_note.clone(),
    );

    Ok((base_return_note, quote_return_note))
}

/// Verify the signature for the order tab hash
pub fn verfiy_close_order_hash(
    order_tab: &OrderTab,
    base_close_order_fields: &CloseOrderFields,
    quote_close_order_fields: &CloseOrderFields,
    signature: Signature,
) -> bool {
    // & header_hash = H({order_tab_hash, base_close_order_fields.hash, quote_close_order_fields.hash})

    let mut hash_inputs: Vec<&BigUint> = Vec::new();

    hash_inputs.push(&order_tab.hash);

    let base_close_order_fields_hash = base_close_order_fields.hash();
    hash_inputs.push(&base_close_order_fields_hash);
    let quote_close_order_fields_hash = quote_close_order_fields.hash();
    hash_inputs.push(&quote_close_order_fields_hash);

    let hash = pedersen_on_vec(&hash_inputs);

    let valid = verify(&order_tab.tab_header.pub_key, &hash, &signature);

    return valid;
}
