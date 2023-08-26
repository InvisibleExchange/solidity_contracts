use std::{collections::HashMap, sync::Arc};

use num_bigint::BigUint;
use parking_lot::Mutex;
use serde_json::Value;

use firestore_db_and_auth::ServiceSession;

use crate::{
    order_tab::{
        db_updates::onchain_open_tab_db_updates, json_output::onchain_open_tab_json_output,
        state_updates::onchain_open_tab_state_updates, OrderTab, TabHeader,
    },
    perpetual::{
        perp_order::CloseOrderFields, COLLATERAL_TOKEN_DECIMALS, DECIMALS_PER_ASSET,
        PRICE_DECIMALS_PER_ASSET,
    },
    server::grpc::engine_proto::OnChainOpenOrderTabReq,
    transaction_batch::LeafNodeType,
    trees::superficial_tree::SuperficialTree,
    utils::{crypto_utils::pedersen_on_vec, notes::Note, storage::BackupStorage},
};

use crate::utils::crypto_utils::{verify, Signature};

// use super::{
//     db_updates::open_tab_db_updates, json_output::open_tab_json_output,
//     state_updates::open_tab_state_updates, OrderTab,
// };

// TODO: Check that the notes exist just before you update the state tree not in the beginning

/// Claim the deposit that was created onchain
pub fn onchain_open_order_tab(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    open_order_tab_req: OnChainOpenOrderTabReq,
    state_tree: &Arc<Mutex<SuperficialTree>>,
    updated_state_hashes: &Arc<Mutex<HashMap<u64, (LeafNodeType, BigUint)>>>,
    swap_output_json_m: &Arc<Mutex<Vec<serde_json::Map<String, Value>>>>,
    index_price: u64,
) -> std::result::Result<OrderTab, String> {
    //

    if open_order_tab_req.tab_header.is_none() {
        return Err("Order tab is not defined".to_string());
    }
    let tab_header = TabHeader::try_from(open_order_tab_req.tab_header.unwrap());
    if let Err(e) = tab_header {
        return Err("Order tab is not properly defined: ".to_string() + &e.to_string());
    }
    let tab_header = tab_header.unwrap();

    let base_token = tab_header.base_token;
    // let quote_token = tab_header.quote_token;

    // ? Verify this is a smart_contract initiated order tab
    if !tab_header.is_smart_contract {
        return Err("This is not a smart contract initiated order tab".to_string());
    }

    if open_order_tab_req.vlp_close_order_fields.is_none() {
        return Err("vlp_close_order_fields is None".to_string());
    }
    let vlp_close_order_fields =
        CloseOrderFields::try_from(open_order_tab_req.vlp_close_order_fields.unwrap());
    if let Err(e) = vlp_close_order_fields {
        return Err(e.to_string());
    }
    let vlp_close_order_fields = vlp_close_order_fields.unwrap();

    // ? Verify the signature ---------------------------------------------------------------------
    let signature = Signature::try_from(open_order_tab_req.signature.unwrap_or_default())
        .map_err(|err| err.to_string())?;
    let valid = verfiy_open_order_sig(&tab_header, &vlp_close_order_fields, &signature);

    if !valid {
        return Err("Invalid Signature".to_string());
    }

    // ? calculate the right amount of vLP tokens to mint using the index price
    // ? Get the input nominal value with the index price
    // ? init token price is 1
    let base_decimals: &u8 = DECIMALS_PER_ASSET.get(&base_token.to_string()).unwrap();
    let base_price_decimals: &u8 = PRICE_DECIMALS_PER_ASSET
        .get(&base_token.to_string())
        .unwrap();

    let decimal_conversion = *base_decimals + *base_price_decimals - COLLATERAL_TOKEN_DECIMALS;
    let multiplier = 10_u128.pow(decimal_conversion as u32);

    let base_nominal = open_order_tab_req.base_amount as u128 * index_price as u128 / multiplier;
    let vlp_amount = base_nominal as u64 + open_order_tab_req.quote_amount;

    let order_tab = OrderTab::new(
        tab_header,
        open_order_tab_req.base_amount,
        open_order_tab_req.quote_amount,
        vlp_amount,
    );

    // ? Mint the new amount of vLP tokens using the vLP_close_order_fields
    let mut state_tree_lock = state_tree.lock();
    let zero_idx = state_tree_lock.first_zero_idx();
    drop(state_tree_lock);

    let vlp_note = Note::new(
        zero_idx,
        vlp_close_order_fields.dest_received_address.clone(),
        order_tab.tab_header.vlp_token,
        vlp_amount,
        vlp_close_order_fields.dest_received_blinding.clone(),
    );

    // ? GENERATE THE JSON_OUTPUT -----------------------------------------------------------------
    onchain_open_tab_json_output(
        &swap_output_json_m,
        &order_tab,
        &vlp_close_order_fields,
        &vlp_note,
        &signature,
    );

    // ? UPDATE THE STATE TREE --------------------------------------------------------------------
    onchain_open_tab_state_updates(state_tree, updated_state_hashes, &order_tab, &vlp_note);

    // ? UPDATE THE DATABASE ----------------------------------------------------------------------
    onchain_open_tab_db_updates(session, backup_storage, order_tab.clone(), vlp_note.clone());

    Ok(order_tab)
}

//

// * HELPERS =======================================================================================

/// Verify the signature for the order tab hash
fn verfiy_open_order_sig(
    tab_header: &TabHeader,
    close_order_fields: &CloseOrderFields,
    signature: &Signature,
) -> bool {
    // & header_hash = H({tab_hash, close_order_fields_hash})

    let mut hash_inputs: Vec<&BigUint> = Vec::new();

    hash_inputs.push(&tab_header.hash);
    let h = close_order_fields.hash();
    hash_inputs.push(&h);

    let hash = pedersen_on_vec(&hash_inputs);

    let valid = verify(&tab_header.pub_key, &hash, signature);

    return valid;
}
