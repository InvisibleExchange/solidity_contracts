use std::{collections::HashMap, sync::Arc};

use num_bigint::BigUint;
use parking_lot::Mutex;
use serde_json::Value;

use firestore_db_and_auth::ServiceSession;
use starknet::curve::AffinePoint;

use crate::{
    order_tab::{
        db_updates::onchain_remove_liquidity_db_updates,
        json_output::onchain_remove_liquidity_json_output,
        state_updates::onchain_remove_liquidity_state_updates, OrderTab,
    },
    perpetual::{
        perp_order::CloseOrderFields, COLLATERAL_TOKEN, COLLATERAL_TOKEN_DECIMALS,
        DECIMALS_PER_ASSET, DUST_AMOUNT_PER_ASSET, PRICE_DECIMALS_PER_ASSET,
    },
    server::grpc::engine_proto::OnChainRemoveLiqTabReq,
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

// ? redeem vLP tokens for base and quote tokens

// ? users signs the amount of tokens to redeem, the price, slippage and close order_fields

// ? the market maker burns the vLP tokens and sends the base and quote tokens to the user

// * ================================================================================================

// ? verify the vLP tokens exist
// ? Hash the users message and verify the signature

// ? verify the execution index price is within slippage range of users price

/// Claim the deposit that was created onchain
pub fn remove_liquidity_from_order_tab(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    remove_liquidity_req: OnChainRemoveLiqTabReq,
    state_tree: &Arc<Mutex<SuperficialTree>>,
    updated_state_hashes: &Arc<Mutex<HashMap<u64, (LeafNodeType, BigUint)>>>,
    swap_output_json_m: &Arc<Mutex<Vec<serde_json::Map<String, Value>>>>,
    index_price: u64,
) -> std::result::Result<Option<OrderTab>, String> {
    //

    // ? Get order tab
    if remove_liquidity_req.order_tab.is_none() {
        return Err("Order tab is not defined".to_string());
    }
    let order_tab = OrderTab::try_from(remove_liquidity_req.order_tab.unwrap());
    if let Err(e) = order_tab {
        return Err("Order tab is not properly defined: ".to_string() + &e.to_string());
    }
    let order_tab = order_tab.unwrap();

    // ? Verify the notes are valid and exist in the state
    let vlp_notes_in = remove_liquidity_req
        .vlp_notes_in
        .into_iter()
        .map(|n| Note::try_from(n).unwrap())
        .collect::<Vec<Note>>();
    let vlp_amount = vlp_notes_in.iter().map(|n| n.amount).sum::<u64>();

    let mut pub_key_sum: AffinePoint = AffinePoint::identity();

    let state_tree_m = state_tree.lock();
    for note in vlp_notes_in.iter() {
        let ec_point = AffinePoint::from(&note.address);
        pub_key_sum = &pub_key_sum + &ec_point;

        if note.token != order_tab.tab_header.vlp_token {
            return Err("vLP token mismatch".to_string());
        }

        if state_tree_m.get_leaf_by_index(note.index) != note.hash {
            return Err("vLP note does not exist".to_string());
        }
    }
    drop(state_tree_m);

    let pub_key_sum = EcPoint::from(&pub_key_sum).x.to_biguint().unwrap();

    let base_close_order_fields =
        CloseOrderFields::try_from(remove_liquidity_req.base_close_order_fields.unwrap());
    if let Err(e) = base_close_order_fields {
        return Err(e.to_string());
    }
    let base_close_order_fields = base_close_order_fields.unwrap();

    let quote_close_order_fields =
        CloseOrderFields::try_from(remove_liquidity_req.quote_close_order_fields.unwrap());
    if let Err(e) = quote_close_order_fields {
        return Err(e.to_string());
    }
    let quote_close_order_fields = quote_close_order_fields.unwrap();

    // ? Verify the signature ---------------------------------------------------------------------
    let signature = Signature::try_from(remove_liquidity_req.signature.unwrap_or_default())
        .map_err(|err| err.to_string())?;
    let valid = verfiy_remove_liquidity_sig(
        remove_liquidity_req.index_price,
        remove_liquidity_req.slippage,
        &base_close_order_fields,
        &quote_close_order_fields,
        &order_tab.tab_header.pub_key,
        &pub_key_sum,
        &signature,
    );

    if !valid {
        return Err("Invalid Signature".to_string());
    }

    // ? Verify the execution index price is within slippage range of users price
    // slippage: 10_000 = 100% ; 100 = 1%; 1 = 0.01%
    let max_slippage_price =
        remove_liquidity_req.index_price * (10_000 - remove_liquidity_req.slippage as u64) / 10_000;
    if index_price < max_slippage_price {
        return Err("Execution price is not within slippage range".to_string());
    }

    let is_full_close =
        vlp_amount >= order_tab.vlp_supply - DUST_AMOUNT_PER_ASSET[&COLLATERAL_TOKEN.to_string()];

    let base_return_amount;
    let quote_return_amount;
    if is_full_close {
        base_return_amount = order_tab.base_amount;
        quote_return_amount = order_tab.quote_amount;
    } else {
        // ? make sure:   vlp_amount * vlp_price = base_amount * index_price + quote_amount
        // ? The market maker specifies amount of base_token to return and the quote token is calculated here to make sure the above equation holds
        let base_decimals: &u8 = DECIMALS_PER_ASSET
            .get(&order_tab.tab_header.base_token.to_string())
            .unwrap();
        let base_price_decimals: &u8 = PRICE_DECIMALS_PER_ASSET
            .get(&order_tab.tab_header.base_token.to_string())
            .unwrap();

        let decimal_conversion = *base_decimals + *base_price_decimals - COLLATERAL_TOKEN_DECIMALS;
        let multiplier = 10_u128.pow(decimal_conversion as u32);

        base_return_amount = remove_liquidity_req.base_return_amount;
        let base_nominal: u128 = base_return_amount as u128 * index_price as u128 / multiplier;

        let tab_base_nominal = order_tab.base_amount as u128 * index_price as u128 / multiplier;
        let tab_nominal = tab_base_nominal as u64 + order_tab.quote_amount;

        // ? quote_amount = (vLP_amount*tab_nominal)/vLP_supply - base_amount*indexPrice
        quote_return_amount =
            (vlp_amount * tab_nominal) / order_tab.vlp_supply - base_nominal as u64;
    }

    if quote_return_amount
        > order_tab.quote_amount
            + DUST_AMOUNT_PER_ASSET[&order_tab.tab_header.quote_token.to_string()]
    {
        return Err("quote_return_amount is too large".to_string());
    }
    if base_return_amount
        > order_tab.base_amount
            + DUST_AMOUNT_PER_ASSET[&order_tab.tab_header.base_token.to_string()]
    {
        return Err("base_return_amount is too large".to_string());
    }

    // ? create the new notes for the user
    let mut state_tree_m = state_tree.lock();
    let zero_idx1 = state_tree_m.first_zero_idx();
    let zero_idx2 = state_tree_m.first_zero_idx();
    drop(state_tree_m);

    let base_return_note = Note::new(
        zero_idx1,
        base_close_order_fields.dest_received_address.clone(),
        order_tab.tab_header.base_token,
        base_return_amount,
        base_close_order_fields.dest_received_blinding.clone(),
    );
    let quote_return_note = Note::new(
        zero_idx2,
        quote_close_order_fields.dest_received_address.clone(),
        order_tab.tab_header.quote_token,
        quote_return_amount,
        quote_close_order_fields.dest_received_blinding.clone(),
    );

    // ? Adding to an existing order tab
    let prev_order_tab = order_tab;

    let mut new_order_tab: Option<OrderTab> = None;
    if !is_full_close {
        let mut new_tab = prev_order_tab.clone();

        new_tab.base_amount -= base_return_amount;
        new_tab.quote_amount -= quote_return_amount;
        new_tab.vlp_supply -= vlp_amount;

        new_tab.update_hash();

        new_order_tab = Some(new_tab)
    }

    // ? update the state tree, json_output and database

    // ? GENERATE THE JSON_OUTPUT -----------------------------------------------------------------
    onchain_remove_liquidity_json_output(
        swap_output_json_m,
        &vlp_notes_in,
        remove_liquidity_req.index_price,
        remove_liquidity_req.slippage,
        &base_close_order_fields,
        &quote_close_order_fields,
        remove_liquidity_req.base_return_amount,
        index_price,
        &prev_order_tab,
        &new_order_tab,
        &base_return_note,
        &quote_return_note,
        &signature,
    );

    // ? UPDATE THE STATE TREE --------------------------------------------------------------------
    onchain_remove_liquidity_state_updates(
        state_tree,
        updated_state_hashes,
        prev_order_tab.tab_idx as u64,
        &new_order_tab,
        &vlp_notes_in,
        &base_return_note,
        &quote_return_note,
    );

    // ? UPDATE THE DATABASE ----------------------------------------------------------------------
    onchain_remove_liquidity_db_updates(
        session,
        backup_storage,
        prev_order_tab.tab_idx as u64,
        prev_order_tab.tab_header.pub_key,
        new_order_tab.clone(),
        &vlp_notes_in,
        base_return_note,
        quote_return_note,
    );

    Ok(new_order_tab)
}

/// Verify the signature for the order tab hash
fn verfiy_remove_liquidity_sig(
    index_price: u64,
    slippage: u32,
    base_close_order_fields: &CloseOrderFields,
    quote_close_order_fields: &CloseOrderFields,
    tab_pub_key: &BigUint,
    pub_key_sum: &BigUint,
    signature: &Signature,
) -> bool {
    //

    let mut hash_inputs: Vec<&BigUint> = vec![];

    let index_price = BigUint::from(index_price);
    hash_inputs.push(&index_price);
    let slippage = BigUint::from(slippage);
    hash_inputs.push(&slippage);

    let base_fields_hash = base_close_order_fields.hash();
    hash_inputs.push(&base_fields_hash);
    let quote_fields_hash = quote_close_order_fields.hash();
    hash_inputs.push(&quote_fields_hash);

    hash_inputs.push(tab_pub_key);

    let hash = pedersen_on_vec(&hash_inputs);

    let valid = verify(pub_key_sum, &hash, signature);

    return valid;
}
