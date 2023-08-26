use std::{collections::HashMap, sync::Arc};

use num_bigint::BigUint;
use num_traits::Zero;
use parking_lot::Mutex;
use serde_json::Value;

use firestore_db_and_auth::ServiceSession;
use starknet::curve::AffinePoint;

use crate::{
    order_tab::{
        db_updates::onchain_add_liquidity_db_updates,
        json_output::onchain_add_liquidity_json_output,
        state_updates::onchain_add_liquidity_state_updates, OrderTab,
    },
    perpetual::{
        perp_order::CloseOrderFields, COLLATERAL_TOKEN_DECIMALS, DECIMALS_PER_ASSET,
        PRICE_DECIMALS_PER_ASSET,
    },
    server::grpc::engine_proto::OnChainAddLiqTabReq,
    transaction_batch::LeafNodeType,
    trees::superficial_tree::SuperficialTree,
    utils::{
        crypto_utils::{pedersen_on_vec, EcPoint},
        notes::Note,
        storage::BackupStorage,
    },
};

use crate::utils::crypto_utils::{verify, Signature};

// use super::{
//     db_updates::open_tab_db_updates, json_output::open_tab_json_output,
//     state_updates::open_tab_state_updates, OrderTab,
// };

// TODO: Check that the notes exist just before you update the state tree not in the beginning

/// Claim the deposit that was created onchain
pub fn add_liquidity_to_order_tab(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    add_liquidity_req: OnChainAddLiqTabReq,
    state_tree: &Arc<Mutex<SuperficialTree>>,
    updated_state_hashes: &Arc<Mutex<HashMap<u64, (LeafNodeType, BigUint)>>>,
    swap_output_json_m: &Arc<Mutex<Vec<serde_json::Map<String, Value>>>>,
    index_price: u64,
) -> std::result::Result<(OrderTab, Note), String> {
    //

    if add_liquidity_req.order_tab.is_none() {
        return Err("Order tab is not defined".to_string());
    }
    let order_tab = OrderTab::try_from(add_liquidity_req.order_tab.unwrap());
    if let Err(e) = order_tab {
        return Err("Order tab is not properly defined: ".to_string() + &e.to_string());
    }
    let mut order_tab = order_tab.unwrap();

    // ? Verify the notes are valid and exist in the state
    let base_notes_in = add_liquidity_req
        .base_notes_in
        .into_iter()
        .map(|n| Note::try_from(n).unwrap())
        .collect::<Vec<Note>>();
    let base_refund_note = if add_liquidity_req.base_refund_note.is_some() {
        Some(Note::try_from(add_liquidity_req.base_refund_note.unwrap()).unwrap())
    } else {
        None
    };
    let quote_notes_in = add_liquidity_req
        .quote_notes_in
        .into_iter()
        .map(|n: crate::server::grpc::engine_proto::GrpcNote| Note::try_from(n).unwrap())
        .collect::<Vec<Note>>();
    let quote_refund_note = if add_liquidity_req.quote_refund_note.is_some() {
        Some(Note::try_from(add_liquidity_req.quote_refund_note.unwrap()).unwrap())
    } else {
        None
    };

    let mut pub_key_sum: AffinePoint = AffinePoint::identity();

    let state_tree_m = state_tree.lock();
    let mut base_amount = 0;
    for note in base_notes_in.iter() {
        if note.token != order_tab.tab_header.base_token {
            return Err("base note does not exist".to_string());
        }

        if state_tree_m.get_leaf_by_index(note.index) != note.hash {
            return Err("base note does not exist".to_string());
        }

        base_amount += note.amount;

        // ? Add to the pub key for sig verification
        let ec_point = AffinePoint::from(&note.address);
        pub_key_sum = &pub_key_sum + &ec_point;
    }
    if base_refund_note.is_some() {
        if base_refund_note.as_ref().unwrap().token != order_tab.tab_header.quote_token {
            return Err("quote note does not exist".to_string());
        }

        if state_tree_m.get_leaf_by_index(base_refund_note.as_ref().unwrap().index)
            != base_refund_note.as_ref().unwrap().hash
        {
            return Err("quote note does not exist".to_string());
        }

        base_amount -= base_refund_note.as_ref().unwrap().amount;
    }
    let mut quote_amount = 0;
    for note in quote_notes_in.iter() {
        if note.token != order_tab.tab_header.quote_token {
            return Err("quote note does not exist".to_string());
        }

        if state_tree_m.get_leaf_by_index(note.index) != note.hash {
            return Err("base note does not exist".to_string());
        }

        quote_amount += note.amount;

        // ? Add to the pub key for sig verification
        let ec_point = AffinePoint::from(&note.address);
        pub_key_sum = &pub_key_sum + &ec_point;
    }
    if quote_refund_note.is_some() {
        if quote_refund_note.as_ref().unwrap().token != order_tab.tab_header.quote_token {
            return Err("quote note does not exist".to_string());
        }

        if state_tree_m.get_leaf_by_index(quote_refund_note.as_ref().unwrap().index)
            != quote_refund_note.as_ref().unwrap().hash
        {
            return Err("quote note does not exist".to_string());
        }

        quote_amount -= quote_refund_note.as_ref().unwrap().amount;
    }
    drop(state_tree_m);

    let pub_key_sum = EcPoint::from(&pub_key_sum).x.to_biguint().unwrap();

    // ? Verify this is a smart_contract initiated order tab
    if !order_tab.tab_header.is_smart_contract {
        return Err("This is not a smart contract initiated order tab".to_string());
    }

    if add_liquidity_req.vlp_close_order_fields.is_none() {
        return Err("vlp_close_order_fields is None".to_string());
    }
    let vlp_close_order_fields =
        CloseOrderFields::try_from(add_liquidity_req.vlp_close_order_fields.unwrap());
    if let Err(e) = vlp_close_order_fields {
        return Err(e.to_string());
    }
    let vlp_close_order_fields = vlp_close_order_fields.unwrap();

    // ? Verify the signature ---------------------------------------------------------------------
    let signature = Signature::try_from(add_liquidity_req.signature.unwrap_or_default())
        .map_err(|err| err.to_string())?;

    let valid = verfiy_add_liquidity_sig(
        &base_refund_note,
        &quote_refund_note,
        &order_tab.tab_header.pub_key,
        &vlp_close_order_fields,
        &pub_key_sum,
        &signature,
    );

    if !valid {
        return Err("Invalid Signature".to_string());
    }

    // ? calculate the right amount of vLP tokens to mint using the index price
    let base_decimals: &u8 = DECIMALS_PER_ASSET
        .get(&order_tab.tab_header.base_token.to_string())
        .unwrap();
    let base_price_decimals: &u8 = PRICE_DECIMALS_PER_ASSET
        .get(&order_tab.tab_header.base_token.to_string())
        .unwrap();

    let decimal_conversion = *base_decimals + *base_price_decimals - COLLATERAL_TOKEN_DECIMALS;
    let multiplier = 10_u128.pow(decimal_conversion as u32);

    let base_nominal = base_amount as u128 * index_price as u128 / multiplier;
    let added_nominal = base_nominal as u64 + quote_amount;

    let tab_base_nominal = order_tab.base_amount as u128 * index_price as u128 / multiplier;
    let tab_nominal = tab_base_nominal as u64 + order_tab.quote_amount;

    let vlp_supply = order_tab.vlp_supply;

    let vlp_amount = vlp_supply * added_nominal / tab_nominal;

    // ? Update the order tab ---------------------------------------------------------------------
    // ? Verify that the order tab exists
    let mut state_tree_m = state_tree.lock();
    let zero_idx = state_tree_m.first_zero_idx();

    let leaf_hash = state_tree_m.get_leaf_by_index(order_tab.tab_idx as u64);
    if leaf_hash != order_tab.hash {
        return Err("order tab does not exist".to_string());
    }
    drop(state_tree_m);

    // ? Adding to an existing order tab
    let prev_order_tab = order_tab.clone();

    order_tab.base_amount += base_amount;
    order_tab.quote_amount += quote_amount;
    order_tab.vlp_supply += vlp_amount;

    order_tab.update_hash();

    // ? Mint the new amount of vLP tokens using the vLP_close_order_fields

    let vlp_note = Note::new(
        zero_idx,
        vlp_close_order_fields.dest_received_address.clone(),
        order_tab.tab_header.vlp_token,
        vlp_amount,
        vlp_close_order_fields.dest_received_blinding.clone(),
    );

    // ? GENERATE THE JSON_OUTPUT -----------------------------------------------------------------
    onchain_add_liquidity_json_output(
        &swap_output_json_m,
        &prev_order_tab,
        &base_notes_in,
        &base_refund_note,
        &quote_notes_in,
        &quote_refund_note,
        &order_tab.hash,
        &vlp_close_order_fields,
        &vlp_note,
        &signature,
    );

    // ? UPDATE THE STATE TREE --------------------------------------------------------------------
    onchain_add_liquidity_state_updates(
        state_tree,
        updated_state_hashes,
        &order_tab,
        &base_notes_in,
        &quote_notes_in,
        &base_refund_note,
        &quote_refund_note,
        &vlp_note,
    );

    // ? UPDATE THE DATABASE ----------------------------------------------------------------------
    onchain_add_liquidity_db_updates(
        session,
        backup_storage,
        order_tab.clone(),
        base_notes_in,
        quote_notes_in,
        base_refund_note,
        quote_refund_note,
        vlp_note.clone(),
    );

    Ok((order_tab, vlp_note))
}

//

// * HELPERS =======================================================================================

/// Verify the signature for the order tab hash
fn verfiy_add_liquidity_sig(
    base_refund_note: &Option<Note>,
    quote_refund_note: &Option<Note>,
    tab_pub_key: &BigUint,
    vlp_close_order_fields: &CloseOrderFields,
    public_key: &BigUint,
    signature: &Signature,
) -> bool {
    // & header_hash = H({tab_pub_key, base_refund_hash, quote_refund_hash, quote_token_added, base_amount_added, quote_amount_added})

    let mut hash_inputs: Vec<&BigUint> = vec![];

    hash_inputs.push(&tab_pub_key);

    let base_refund_hash = if base_refund_note.is_some() {
        base_refund_note.as_ref().unwrap().hash.clone()
    } else {
        BigUint::zero()
    };
    let quote_refund_hash = if quote_refund_note.is_some() {
        quote_refund_note.as_ref().unwrap().hash.clone()
    } else {
        BigUint::zero()
    };

    hash_inputs.push(&base_refund_hash);
    hash_inputs.push(&quote_refund_hash);

    let h = vlp_close_order_fields.hash();
    hash_inputs.push(&h);

    let hash = pedersen_on_vec(&hash_inputs);

    let valid = verify(public_key, &hash, signature);

    return valid;
}
