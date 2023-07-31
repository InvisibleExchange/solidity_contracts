use std::{collections::HashMap, sync::Arc};

use num_bigint::BigUint;
use num_traits::FromPrimitive;
use parking_lot::Mutex;
use serde_json::Value;
use starknet::curve::AffinePoint;

use firestore_db_and_auth::ServiceSession;

use crate::{
    perpetual::perp_order::CloseOrderFields,
    server::grpc::engine_proto::ModifyOrderTabReq,
    trees::superficial_tree::SuperficialTree,
    utils::{
        crypto_utils::{pedersen_on_vec, EcPoint},
        notes::Note,
        storage::BackupStorage,
    },
};

use crate::utils::crypto_utils::{verify, Signature};

use super::{
    db_updates::modify_tab_db_updates, json_output::modifiy_tab_json_output,
    state_updates::modify_tab_state_updates, OrderTab,
};

// TODO: Check that the notes exist just before you update the state tree not in the beginning

pub fn modify_order_tab(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    modify_order_tab_req: ModifyOrderTabReq,
    state_tree: &Arc<Mutex<SuperficialTree>>,
    updated_note_hashes: &Arc<Mutex<HashMap<u64, BigUint>>>,
    order_tabs_state_tree: &Arc<Mutex<SuperficialTree>>,
    updated_tab_hashes: &Arc<Mutex<HashMap<u32, BigUint>>>,
    swap_output_json_m: &Arc<Mutex<Vec<serde_json::Map<String, Value>>>>,
) -> std::result::Result<(OrderTab, Option<Note>, Option<Note>), String> {
    //

    let order_tab = OrderTab::try_from(modify_order_tab_req.order_tab.unwrap());
    if let Err(e) = order_tab {
        return Err(e.to_string());
    }
    let mut order_tab = order_tab.unwrap();

    let prev_order_tab = order_tab.clone();

    if modify_order_tab_req.base_amount_change == 0 && modify_order_tab_req.quote_amount_change == 0
    {
        return Err("amounts cannot be zero".to_string());
    }

    // ? Check that the order_tab_exists
    let tab_state_tree_m = order_tabs_state_tree.lock();

    let leaf_hash = tab_state_tree_m.get_leaf_by_index(order_tab.tab_idx as u64);
    if leaf_hash != order_tab.hash {
        return Err("order tab does not exist".to_string());
    }
    drop(tab_state_tree_m);

    let base_token = order_tab.tab_header.base_token;
    let quote_token = order_tab.tab_header.quote_token;

    let sig_pub_key;

    let mut base_refund_note: Option<Note> = None;
    let mut quote_refund_note: Option<Note> = None;
    let mut base_notes_in = Vec::new();
    let mut quote_notes_in = Vec::new();
    //
    let mut base_close_order_fields: Option<CloseOrderFields> = None;
    let mut quote_close_order_fields: Option<CloseOrderFields> = None;
    let mut base_return_note: Option<Note> = None;
    let mut quote_return_note: Option<Note> = None;
    if modify_order_tab_req.is_add {
        //

        let mut base_amount = 0;
        let mut quote_amount = 0;

        let mut pub_key_sum: AffinePoint = AffinePoint::identity();

        // ? Check that the notes spent exist
        let state_tree_m = state_tree.lock();
        // & BASE TOKEN —————————————————————————

        for note_ in modify_order_tab_req.base_notes_in.into_iter() {
            if note_.token != base_token {
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
        if modify_order_tab_req.base_refund_note.is_some() {
            let note_ = modify_order_tab_req.base_refund_note.as_ref().unwrap();
            if note_.token != base_token {
                return Err("token missmatch".to_string());
            }

            base_amount -= note_.amount;

            base_refund_note = Note::try_from(note_.clone()).ok();
        }

        // & QUOTE TOKEN —————————————————————————
        // ? Check that notes for quote token exist

        for note_ in modify_order_tab_req.quote_notes_in.into_iter() {
            if note_.token != quote_token {
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
        if modify_order_tab_req.quote_refund_note.is_some() {
            let note_ = modify_order_tab_req.quote_refund_note.as_ref().unwrap();
            if note_.token != quote_token {
                return Err("token missmatch".to_string());
            }

            quote_amount -= note_.amount;
            quote_refund_note = Note::try_from(note_.clone()).ok();
        }

        // ? Get the public key from the sum of the notes
        sig_pub_key = EcPoint::from(&pub_key_sum).x.to_biguint().unwrap();

        if base_amount != modify_order_tab_req.base_amount_change
            || quote_amount != modify_order_tab_req.quote_amount_change
        {
            return Err("amount missmatch".to_string());
        }

        order_tab.base_amount += base_amount;
        order_tab.quote_amount += quote_amount;

        drop(state_tree_m);
    } else {
        let base_close_order_fields_ =
            CloseOrderFields::try_from(modify_order_tab_req.base_close_order_fields.unwrap());
        let quote_close_order_fields_ =
            CloseOrderFields::try_from(modify_order_tab_req.quote_close_order_fields.unwrap());

        if base_close_order_fields_.is_err() || quote_close_order_fields_.is_err() {
            return Err("failed to parse order tab or close order fields".to_string());
        }
        let base_close_fields = base_close_order_fields_.as_ref().unwrap();
        let quote_close_fields = quote_close_order_fields_.as_ref().unwrap();

        if order_tab.base_amount < modify_order_tab_req.base_amount_change
            || order_tab.quote_amount < modify_order_tab_req.quote_amount_change
        {
            return Err("amounts to reduce are to large".to_string());
        }

        let mut state_tree_m = state_tree.lock();

        let zero_idx1 = state_tree_m.first_zero_idx();
        let zero_idx2 = state_tree_m.first_zero_idx();

        base_return_note = Some(Note::new(
            zero_idx1,
            base_close_fields.dest_received_address.clone(),
            base_token,
            modify_order_tab_req.base_amount_change,
            base_close_fields.dest_received_blinding.clone(),
        ));
        quote_return_note = Some(Note::new(
            zero_idx2,
            quote_close_fields.dest_received_address.clone(),
            quote_token,
            modify_order_tab_req.quote_amount_change,
            quote_close_fields.dest_received_blinding.clone(),
        ));

        base_close_order_fields = base_close_order_fields_.ok();
        quote_close_order_fields = quote_close_order_fields_.ok();

        sig_pub_key = order_tab.tab_header.pub_key.clone();

        order_tab.base_amount -= modify_order_tab_req.base_amount_change;
        order_tab.quote_amount -= modify_order_tab_req.quote_amount_change;
    }

    // ? Update the order_tab hash
    order_tab.update_hash();

    // ? Verify the signature --------------------------------------------------------------
    let signature = Signature::try_from(modify_order_tab_req.signature.unwrap_or_default())
        .map_err(|err| err.to_string())?;
    verify_modify_signature(
        modify_order_tab_req.is_add,
        &prev_order_tab.hash,
        &base_refund_note,
        &quote_refund_note,
        &base_close_order_fields,
        &quote_close_order_fields,
        modify_order_tab_req.base_amount_change,
        modify_order_tab_req.quote_amount_change,
        &sig_pub_key,
        &signature,
    );

    // ? GENERATE THE JSON_OUTPUT -----------------------------------------------------------------
    modifiy_tab_json_output(
        &swap_output_json_m,
        modify_order_tab_req.is_add,
        modify_order_tab_req.base_amount_change,
        modify_order_tab_req.quote_amount_change,
        &prev_order_tab,
        &base_notes_in,
        &base_refund_note,
        &quote_notes_in,
        &quote_refund_note,
        &base_close_order_fields,
        &quote_close_order_fields,
        &base_return_note,
        &quote_return_note,
        &order_tab,
        &signature,
    );

    // ? UPDATE THE DATABASE ----------------------------------------------------------------------
    modify_tab_db_updates(
        session,
        backup_storage,
        modify_order_tab_req.is_add,
        &order_tab,
        // if is_add
        &base_notes_in,
        &quote_notes_in,
        &base_refund_note,
        &quote_refund_note,
        // if not is_add
        &base_return_note,
        &quote_return_note,
    );

    // ? UPDATE THE STATE TREE --------------------------------------------------------------------
    modify_tab_state_updates(
        state_tree,
        updated_note_hashes,
        order_tabs_state_tree,
        updated_tab_hashes,
        modify_order_tab_req.is_add,
        order_tab.clone(),
        // if is_add
        base_notes_in,
        quote_notes_in,
        base_refund_note,
        quote_refund_note,
        // if not is_add
        base_return_note.clone(),
        quote_return_note.clone(),
    );

    Ok((order_tab, base_return_note, quote_return_note))
}

//

// HELPERS ————————————————————————————————————————————————————————————————————————————————————

fn verify_modify_signature(
    is_add: bool,
    order_tab_hash: &BigUint,
    //
    base_refund_note: &Option<Note>,
    quote_refund_note: &Option<Note>,
    //
    base_close_order_fields: &Option<CloseOrderFields>,
    quote_close_order_fields: &Option<CloseOrderFields>,
    base_amount: u64,
    quote_amount: u64,
    pub_key: &BigUint,
    signature: &Signature,
) -> bool {
    let mut hash_inputs: Vec<&BigUint> = Vec::new();

    hash_inputs.push(&order_tab_hash);
    let is_add_val = BigUint::from_u8(if is_add { 1 } else { 0 }).unwrap();
    hash_inputs.push(&is_add_val);

    let base_amount_ = BigUint::from_u64(base_amount).unwrap();
    hash_inputs.push(&base_amount_);
    let quote_amount_ = BigUint::from_u64(quote_amount).unwrap();
    hash_inputs.push(&quote_amount_);

    let hash: BigUint;
    if is_add {
        // & hash = H({order_tab_hash, is_add, base_amount, quote_amount, base_refund_note_hash, quote_refund_note_hash})

        let z = BigUint::from_u64(0).unwrap();
        let base_refund_hash = if base_refund_note.is_some() {
            &base_refund_note.as_ref().unwrap().hash
        } else {
            &z
        };
        let quote_refund_hash = if quote_refund_note.is_some() {
            &quote_refund_note.as_ref().unwrap().hash
        } else {
            &z
        };
        hash_inputs.push(&base_refund_hash);
        hash_inputs.push(&quote_refund_hash);

        hash = pedersen_on_vec(&hash_inputs);
    } else {
        // & hash = H({order_tab_hash, is_add, base_amount, quote_amount, base_close_order_fields.hash, quote_close_order_fields.hash})

        let base_close_order_fields_hash = base_close_order_fields.as_ref().unwrap().hash();
        hash_inputs.push(&base_close_order_fields_hash);
        let quote_close_order_fields_hash = quote_close_order_fields.as_ref().unwrap().hash();
        hash_inputs.push(&quote_close_order_fields_hash);

        hash = pedersen_on_vec(&hash_inputs);
    }

    let valid = verify(pub_key, &hash, signature);

    return valid;
}
