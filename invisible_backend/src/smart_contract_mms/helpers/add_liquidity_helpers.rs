use std::sync::Arc;

use num_bigint::BigUint;
use num_traits::Zero;
use parking_lot::Mutex;

use starknet::curve::AffinePoint;

use crate::{
    order_tab::OrderTab,
    perpetual::{
        perp_order::CloseOrderFields, perp_position::PerpPosition, COLLATERAL_TOKEN,
        COLLATERAL_TOKEN_DECIMALS, DECIMALS_PER_ASSET, PRICE_DECIMALS_PER_ASSET,
    },
    server::grpc::engine_proto::{
        GrpcCloseOrderFields, PositionAddLiquidityReq, TabAddLiquidityReq,
    },
    trees::superficial_tree::SuperficialTree,
    utils::{
        crypto_utils::{pedersen_on_vec, verify, EcPoint, Signature},
        notes::Note,
    },
};

// * ORDER TAB SMART CONTRACT MM ====================================================================

/// Verify the order tab is valid
pub fn verify_order_tab_validity(
    add_liquidity_req: &TabAddLiquidityReq,
) -> Result<OrderTab, String> {
    if add_liquidity_req.order_tab.is_none() {
        return Err("Order tab is not defined".to_string());
    }
    let order_tab = OrderTab::try_from(add_liquidity_req.order_tab.as_ref().unwrap().clone());
    if let Err(e) = order_tab {
        return Err("Order tab is not properly defined: ".to_string() + &e.to_string());
    }
    let order_tab = order_tab.unwrap();

    // ? Verify this is a smart_contract initiated order tab
    if !order_tab.tab_header.is_smart_contract {
        return Err("This is not a smart contract initiated order tab".to_string());
    }

    return Ok(order_tab);
}

pub fn verify_close_order_fields(
    vlp_close_order_fields: GrpcCloseOrderFields,
) -> Result<CloseOrderFields, String> {
    let vlp_close_order_fields = CloseOrderFields::try_from(vlp_close_order_fields);
    if let Err(e) = vlp_close_order_fields {
        return Err(e.to_string());
    }
    let vlp_close_order_fields = vlp_close_order_fields.unwrap();

    return Ok(vlp_close_order_fields);
}

/// Verify the notes exist in the state and are valid
pub fn verify_note_validity(
    state_tree: &Arc<Mutex<SuperficialTree>>,
    add_liquidity_req: TabAddLiquidityReq,
    base_token: u32,
    quote_token: u32,
) -> Result<
    (
        Vec<Note>,
        Option<Note>,
        Vec<Note>,
        Option<Note>,
        u64,
        u64,
        BigUint,
    ),
    String,
> {
    // ? Verify the notes are valid and exist in the state
    let base_notes_in = add_liquidity_req
        .base_notes_in
        .into_iter()
        .map(|n| Note::try_from(n).unwrap())
        .collect::<Vec<Note>>();
    let base_refund_note = add_liquidity_req
        .base_refund_note
        .map(|n| Note::try_from(n).unwrap());

    let quote_notes_in = add_liquidity_req
        .quote_notes_in
        .into_iter()
        .map(|n: crate::server::grpc::engine_proto::GrpcNote| Note::try_from(n).unwrap())
        .collect::<Vec<Note>>();
    let quote_refund_note = add_liquidity_req
        .quote_refund_note
        .map(|n| Note::try_from(n).unwrap());

    let mut pub_key_sum: AffinePoint = AffinePoint::identity();

    let state_tree_m = state_tree.lock();
    let mut base_amount = 0;
    for note in base_notes_in.iter() {
        if note.token != base_token {
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
        if base_refund_note.as_ref().unwrap().token != base_token {
            return Err("base refund note has invalid token".to_string());
        }

        if base_refund_note.as_ref().unwrap().index != base_notes_in[0].index {
            return Err("quote refund note index is invalid".to_string());
        }

        base_amount -= base_refund_note.as_ref().unwrap().amount;
    }
    let mut quote_amount = 0;
    for note in quote_notes_in.iter() {
        if note.token != quote_token {
            return Err("quote note token is invalid".to_string());
        }

        if state_tree_m.get_leaf_by_index(note.index) != note.hash {
            return Err("quote note does not exist".to_string());
        }

        quote_amount += note.amount;

        // ? Add to the pub key for sig verification
        let ec_point = AffinePoint::from(&note.address);
        pub_key_sum = &pub_key_sum + &ec_point;
    }
    if quote_refund_note.is_some() {
        if quote_refund_note.as_ref().unwrap().token != quote_token {
            return Err("quote refund note token is invalid".to_string());
        }

        if quote_refund_note.as_ref().unwrap().index != quote_notes_in[0].index {
            return Err("quote refund note index is invalid".to_string());
        }

        quote_amount -= quote_refund_note.as_ref().unwrap().amount;
    }
    drop(state_tree_m);

    let pub_key_sum = EcPoint::from(&pub_key_sum).x.to_biguint().unwrap();

    Ok((
        base_notes_in,
        base_refund_note,
        quote_notes_in,
        quote_refund_note,
        base_amount,
        quote_amount,
        pub_key_sum,
    ))
}

pub fn calculate_vlp_amount(
    order_tab: &OrderTab,
    base_amount: u64,
    quote_amount: u64,
    index_price: u64,
) -> u64 {
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
    let added_nominal = base_nominal + quote_amount as u128;

    let tab_base_nominal = order_tab.base_amount as u128 * index_price as u128 / multiplier;
    let tab_nominal = tab_base_nominal + order_tab.quote_amount as u128;

    let vlp_supply = order_tab.vlp_supply as u128;

    let vlp_amount = vlp_supply * added_nominal / tab_nominal;

    return vlp_amount as u64;
}

// * POSITION SMART CONTRACT MM ====================================================================

/// Verify the order tab is valid
pub fn verify_position_validity(
    add_liquidity_req: &PositionAddLiquidityReq,
) -> Result<PerpPosition, String> {
    if add_liquidity_req.position.is_none() {
        return Err("Position is not defined".to_string());
    }
    let position = PerpPosition::try_from(add_liquidity_req.position.as_ref().unwrap().clone());
    if let Err(e) = position {
        return Err("Position is not properly defined: ".to_string() + &e.to_string());
    }
    let position = position.unwrap();

    // ? Verify this is a smart_contract initiated order tab
    if !position.position_header.is_smart_contract {
        return Err("This is not a smart contract initiated position".to_string());
    }

    return Ok(position);
}

/// Verify the notes exist in the state and are valid
pub fn verify_pos_note_validity(
    state_tree: &Arc<Mutex<SuperficialTree>>,
    add_liquidity_req: PositionAddLiquidityReq,
) -> Result<(Vec<Note>, Option<Note>, u64, BigUint), String> {
    // ? Verify the notes are valid and exist in the state
    let collateral_notes_in = add_liquidity_req
        .collateral_notes_in
        .into_iter()
        .map(|n| Note::try_from(n).unwrap())
        .collect::<Vec<Note>>();
    let collateral_refund_note = add_liquidity_req
        .collateral_refund_note
        .map(|n| Note::try_from(n).unwrap());

    let mut pub_key_sum: AffinePoint = AffinePoint::identity();

    let state_tree_m = state_tree.lock();
    let mut collateral_amount = 0;
    for note in collateral_notes_in.iter() {
        if note.token != COLLATERAL_TOKEN {
            return Err("base note does not exist".to_string());
        }

        if state_tree_m.get_leaf_by_index(note.index) != note.hash {
            return Err("base note does not exist".to_string());
        }

        collateral_amount += note.amount;

        // ? Add to the pub key for sig verification
        let ec_point = AffinePoint::from(&note.address);
        pub_key_sum = &pub_key_sum + &ec_point;
    }
    if collateral_refund_note.is_some() {
        if collateral_refund_note.as_ref().unwrap().token != COLLATERAL_TOKEN {
            return Err("collateral note token is invalid".to_string());
        }

        if state_tree_m.get_leaf_by_index(collateral_refund_note.as_ref().unwrap().index)
            != collateral_refund_note.as_ref().unwrap().hash
        {
            return Err("collateral note does not exist".to_string());
        }

        collateral_amount -= collateral_refund_note.as_ref().unwrap().amount;
    }
    drop(state_tree_m);

    let pub_key_sum = EcPoint::from(&pub_key_sum).x.to_biguint().unwrap();

    Ok((
        collateral_notes_in,
        collateral_refund_note,
        collateral_amount,
        pub_key_sum,
    ))
}

pub fn calculate_pos_vlp_amount(position: &PerpPosition, collateral_amount: u64) -> u64 {
    // ? calculate the right amount of vLP tokens to mint
    let vlp_supply = position.vlp_supply;
    let total_margin = position.margin;

    let vlp_amount = (collateral_amount as u128 * vlp_supply as u128) / total_margin as u128;

    return vlp_amount as u64;
}

// * HELPERS =======================================================================================

/// Verify the signature for the order tab hash
pub fn verfiy_add_liquidity_sig(
    base_refund_note: &Option<Note>,
    quote_refund_note: &Option<Note>,
    tab_pub_key: &BigUint,
    vlp_close_order_fields: &CloseOrderFields,
    public_key: &BigUint,
    signature: &Signature,
) -> bool {
    // & header_hash = H({tab_pub_key, base_refund_hash, quote_refund_hash, fields_hash})

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

/// Verify the signature for the order tab hash
pub fn verfiy_pos_add_liquidity_sig(
    collateral_refund_note: &Option<Note>,
    position_address: &BigUint,
    vlp_close_order_fields: &CloseOrderFields,
    public_key: &BigUint,
    signature: &Signature,
) -> bool {
    // & header_hash = H({pos_address, refund_hash, close_fields_hash})

    let mut hash_inputs: Vec<&BigUint> = vec![];

    hash_inputs.push(&position_address);

    let close_refund_hash = if collateral_refund_note.is_some() {
        collateral_refund_note.as_ref().unwrap().hash.clone()
    } else {
        BigUint::zero()
    };
    hash_inputs.push(&close_refund_hash);

    let h = vlp_close_order_fields.hash();
    hash_inputs.push(&h);

    let hash = pedersen_on_vec(&hash_inputs);

    let valid = verify(public_key, &hash, signature);

    return valid;
}
