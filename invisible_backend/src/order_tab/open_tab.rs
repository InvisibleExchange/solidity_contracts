use std::{collections::HashMap, str::FromStr, sync::Arc};

use num_bigint::BigUint;
use parking_lot::Mutex;
use starknet::curve::AffinePoint;

use firestore_db_and_auth::ServiceSession;

use crate::{
    server::grpc::engine_proto::OpenOrderTabReq,
    trees::superficial_tree::SuperficialTree,
    utils::{notes::Note, storage::BackupStorage},
};

use crate::utils::crypto_utils::{verify, EcPoint, Signature};

use super::{
    db_updates::open_tab_db_updates, state_updates::open_tab_state_updates, OrderTab, TabHeader,
};

// TODO: Check that the notes exist just before you update the state tree not in the beginning

pub fn open_order_tab(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    open_order_tab_req: OpenOrderTabReq,
    state_tree: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes: &Arc<Mutex<HashMap<u64, BigUint>>>,
    order_tabs_state_tree: &Arc<Mutex<SuperficialTree>>,
    updated_tab_hashes: &Arc<Mutex<HashMap<u32, BigUint>>>,
) -> std::result::Result<OrderTab, String> {
    let sig_pub_key: BigUint;

    let mut base_amount = 0;
    let mut base_refund_note: Option<Note> = None;
    let mut quote_amount = 0;
    let mut quote_refund_note: Option<Note> = None;

    let mut pub_key_sum: AffinePoint = AffinePoint::identity();

    // ? Check that the notes spent exist
    let state_tree_m = state_tree.lock();
    // & BASE TOKEN —————————————————————————

    let mut base_notes_in = Vec::new();
    for note_ in open_order_tab_req.base_notes_in.into_iter() {
        if note_.token != open_order_tab_req.base_token {
            return Err("token missmatch".to_string());
        }

        let note = Note::try_from(note_);
        if let Err(e) = note {
            return Err(e.to_string());
        }
        let note = note.unwrap();

        // ? Check that notes for base token exist
        let leaf_hash = state_tree_m.get_leaf_by_index(note.index);

        if leaf_hash != note.hash {
            return Err("note spent to open tab does not exist".to_string());
        }

        // ? Add to the pub key for sig verification
        let ec_point = AffinePoint::from(&note.address);
        pub_key_sum = &pub_key_sum + &ec_point;

        base_amount += note.amount;

        base_notes_in.push(note);
    }
    // ? Check if there is a refund note for base token
    if open_order_tab_req.base_refund_note.is_some() {
        let note_ = open_order_tab_req.base_refund_note.as_ref().unwrap();
        if note_.token != open_order_tab_req.base_token {
            return Err("token missmatch".to_string());
        }

        base_amount -= note_.amount;

        base_refund_note = Note::try_from(note_.clone()).ok();
    }

    // & QUOTE TOKEN —————————————————————————
    // ? Check that notes for quote token exist
    let mut quote_notes_in = Vec::new();
    for note_ in open_order_tab_req.quote_notes_in.into_iter() {
        if note_.token != open_order_tab_req.quote_token {
            return Err("token missmatch".to_string());
        }

        let note = Note::try_from(note_);
        if let Err(e) = note {
            return Err(e.to_string());
        }
        let note = note.unwrap();

        let leaf_hash = state_tree_m.get_leaf_by_index(note.index);

        if leaf_hash != note.hash {
            return Err("note spent to open tab does not exist".to_string());
        }

        // ? Add to the pub key for sig verification
        let ec_point = AffinePoint::from(&note.address);
        pub_key_sum = &pub_key_sum + &ec_point;

        quote_amount += note.amount;

        quote_notes_in.push(note);
    }
    // ? Check if there is a refund note for base token
    if open_order_tab_req.quote_refund_note.is_some() {
        let note_ = open_order_tab_req.quote_refund_note.as_ref().unwrap();
        if note_.token != open_order_tab_req.quote_token {
            return Err("token missmatch".to_string());
        }

        quote_amount -= note_.amount;
        quote_refund_note = Note::try_from(note_.clone()).ok();
    }

    // ? Get the public key from the sum of the notes
    sig_pub_key = EcPoint::from(&pub_key_sum).x.to_biguint().unwrap();

    drop(state_tree_m);

    // ? Create an Orders tab object
    let pub_key =
        BigUint::from_str(open_order_tab_req.pub_key.as_str()).map_err(|err| err.to_string())?;
    let base_blinding = BigUint::from_str(open_order_tab_req.base_blinding.as_str())
        .map_err(|err| err.to_string())?;
    let quote_blinding = BigUint::from_str(open_order_tab_req.quote_blinding.as_str())
        .map_err(|err| err.to_string())?;

    let tab_header = TabHeader::new(
        open_order_tab_req.expiration_timestamp,
        open_order_tab_req.is_perp,
        open_order_tab_req.is_smart_contract,
        open_order_tab_req.base_token,
        open_order_tab_req.quote_token,
        base_blinding,
        quote_blinding,
        pub_key,
    );
    let mut order_tab: OrderTab = OrderTab::new(tab_header, base_amount, quote_amount);

    // ? Set the tab index
    let mut tabs_state_tree = order_tabs_state_tree.lock();
    let z_index = tabs_state_tree.first_zero_idx();
    order_tab.tab_idx = z_index as u32;
    drop(tabs_state_tree);

    // ? Verify the signature ---------------------------------------------------------------------
    let signature = Signature::try_from(open_order_tab_req.signature.unwrap_or_default())
        .map_err(|err| err.to_string())?;
    let valid = verify(&sig_pub_key, &order_tab.hash, &signature);

    if !valid {
        return Err("Invalid Signature".to_string());
    }

    // ? UPDATE THE DATABASE
    open_tab_db_updates(
        session,
        backup_storage,
        order_tab.clone(),
        &base_notes_in,
        &quote_notes_in,
        base_refund_note.clone(),
        quote_refund_note.clone(),
    );

    // ? UPDATE THE STATE
    open_tab_state_updates(
        state_tree,
        updated_note_hashes,
        order_tabs_state_tree,
        updated_tab_hashes,
        order_tab.clone(),
        base_notes_in,
        quote_notes_in,
        base_refund_note,
        quote_refund_note,
    );

    Ok(order_tab)
}

//

// * HELPERS =======================================================================================
