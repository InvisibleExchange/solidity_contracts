use std::{str::FromStr, sync::Arc};

use num_bigint::BigUint;
use num_traits::{FromPrimitive, One, Zero};
use parking_lot::Mutex;
use starknet::curve::AffinePoint;

use crate::{
    perpetual::{perp_position::PerpPosition, VALID_COLLATERAL_TOKENS},
    server::grpc::engine::OrderTabReq,
    trees::superficial_tree::SuperficialTree,
    utils::notes::Note,
};

use crate::utils::crypto_utils::{pedersen_on_vec, verify, EcPoint, Signature};

#[derive(Debug, Clone)]
pub struct OrderTab {
    pub tab_idx: u32,
    pub tab_header: TabHeader,
    pub base_token: u64,
    pub quote_token: u64,
    pub base_amount: u64,
    pub quote_amount: u64,
    pub position: Option<PerpPosition>,
    pub hash: BigUint,
}

impl OrderTab {
    pub fn new(
        tab_header: TabHeader,
        base_token: u64,
        quote_token: u64,
        base_amount: u64,
        quote_amount: u64,
        position: Option<PerpPosition>,
    ) -> OrderTab {
        let hash = hash_tab(
            &tab_header,
            base_token,
            quote_token,
            base_amount,
            quote_amount,
            &position.as_ref(),
        );

        OrderTab {
            tab_idx: 0,
            tab_header,
            base_token,
            quote_token,
            base_amount,
            quote_amount,
            position,
            hash,
        }
    }
}

fn hash_tab(
    tab_header: &TabHeader,
    base_token: u64,
    quote_token: u64,
    base_amount: u64,
    quote_amount: u64,
    position: &Option<&PerpPosition>,
) -> BigUint {
    let mut hash_inputs: Vec<&BigUint> = Vec::new();

    // & H({header_hash, base_token, quote_token, base_amount, quote_amount, position_hash})

    let header_hash = tab_header.hash_header();
    hash_inputs.push(&header_hash);
    let base_token = BigUint::from_u64(base_token).unwrap();
    hash_inputs.push(&base_token);
    let quote_token = BigUint::from_u64(quote_token).unwrap();
    hash_inputs.push(&quote_token);
    let base_amount = BigUint::from_u64(base_amount).unwrap();
    hash_inputs.push(&base_amount);
    let quote_amount = BigUint::from_u64(quote_amount).unwrap();
    hash_inputs.push(&quote_amount);

    let position_hash = if position.is_some() {
        let position = position.unwrap();
        let position_hash = position.hash.clone();
        position_hash
    } else {
        BigUint::zero()
    };
    hash_inputs.push(&position_hash);

    let order_hash = pedersen_on_vec(&hash_inputs);

    return order_hash;
}

#[derive(Debug, Clone)]
pub struct TabHeader {
    pub expiration_timestamp: u64,
    pub is_perp: bool,
    pub is_smart_contract: bool,
    pub pub_key: BigUint,
    pub user_id: u64,
    pub market_id: u16,
}

impl TabHeader {
    pub fn new(
        expiration_timestamp: u64,
        is_perp: bool,
        is_smart_contract: bool,
        pub_key: BigUint,
        user_id: u64,
        market_id: u16,
    ) -> TabHeader {
        TabHeader {
            user_id,
            expiration_timestamp,
            is_perp,
            is_smart_contract,
            pub_key,
            market_id,
        }
    }

    pub fn hash_header(&self) -> BigUint {
        let mut hash_inputs: Vec<&BigUint> = Vec::new();

        let expiration_timestamp = BigUint::from_u64(self.expiration_timestamp).unwrap();
        hash_inputs.push(&expiration_timestamp);
        let is_perp = if self.is_perp {
            BigUint::one()
        } else {
            BigUint::zero()
        };
        hash_inputs.push(&is_perp);
        let is_smart_contract = if self.is_smart_contract {
            BigUint::one()
        } else {
            BigUint::zero()
        };
        hash_inputs.push(&is_smart_contract);
        hash_inputs.push(&self.pub_key);

        let order_hash = pedersen_on_vec(&hash_inputs);

        return order_hash;
    }
}

// * EXECUTION LOGIC ======================================================================================================

pub fn open_orders_tab(
    order_tab_req: OrderTabReq,
    state_tree: &Arc<Mutex<SuperficialTree>>,
    perpetual_state_tree: &Arc<Mutex<SuperficialTree>>,
    order_tabs_state_tree: &Arc<Mutex<SuperficialTree>>,
) -> std::result::Result<(), String> {
    let sig_pub_key: BigUint;

    let mut base_amount = 0;
    let mut base_refund_note: Option<Note> = None;
    let mut quote_amount = 0;
    let mut quote_refund_note: Option<Note> = None;
    let mut position: Option<PerpPosition> = None;

    if order_tab_req.is_perp {
        // ? Check that the position exists
        let perp_state_tree = perpetual_state_tree.lock();

        if order_tab_req.position.is_none() {
            return Err("position is undefined".to_string());
        }

        let position_ = order_tab_req.position.unwrap();
        if position_.synthetic_token != order_tab_req.base_token
            || !VALID_COLLATERAL_TOKENS.contains(&order_tab_req.quote_token)
        {
            return Err("token missmatch".to_string());
        }

        let position_ = PerpPosition::try_from(position_);

        if let Err(e) = position_ {
            return Err(e.to_string());
        }

        position = position_.ok();

        let leaf_hash = perp_state_tree.get_leaf_by_index(position.as_ref().unwrap().index as u64);

        if leaf_hash != position.as_ref().unwrap().hash {
            return Err("note spent to open tab does not exist".to_string());
        }

        // ? Get the public key from the position address
        sig_pub_key = position.as_ref().unwrap().position_address.clone();
    } else {
        let mut pub_key_sum: AffinePoint = AffinePoint::identity();

        // ? Check that the notes spent exist
        let state_tree = state_tree.lock();

        // & BASE TOKEN —————————————————————————
        // ? Check that notes for base token exist
        for note_ in order_tab_req.base_notes_in.into_iter() {
            if note_.token != order_tab_req.base_token {
                return Err("token missmatch".to_string());
            }

            let note = Note::try_from(note_);
            if let Err(e) = note {
                return Err(e.to_string());
            }
            let note = note.unwrap();

            let leaf_hash = state_tree.get_leaf_by_index(note.index);

            if leaf_hash != note.hash {
                return Err("note spent to open tab does not exist".to_string());
            }

            // ? Add to the pub key for sig verification
            let ec_point = AffinePoint::from(&note.address);
            pub_key_sum = &pub_key_sum + &ec_point;

            base_amount += note.amount;
        }
        // ? Check if there is a refund note for base token
        if order_tab_req.base_refund_note.is_some() {
            let note_ = order_tab_req.base_refund_note.unwrap();
            if note_.token != order_tab_req.base_token {
                return Err("token missmatch".to_string());
            }

            base_amount -= note_.amount;

            base_refund_note = Note::try_from(note_).ok();
        }

        // & QUOTE TOKEN —————————————————————————
        // ? Check that notes for quote token exist
        for note_ in order_tab_req.quote_notes_in.into_iter() {
            if note_.token != order_tab_req.quote_token {
                return Err("token missmatch".to_string());
            }

            let note = Note::try_from(note_);
            if let Err(e) = note {
                return Err(e.to_string());
            }
            let note = note.unwrap();

            let leaf_hash = state_tree.get_leaf_by_index(note.index);

            if leaf_hash != note.hash {
                return Err("note spent to open tab does not exist".to_string());
            }

            // ? Add to the pub key for sig verification
            let ec_point = AffinePoint::from(&note.address);
            pub_key_sum = &pub_key_sum + &ec_point;

            quote_amount += note.amount;
        }
        // ? Check if there is a refund note for base token
        if order_tab_req.quote_refund_note.is_some() {
            let note_ = order_tab_req.quote_refund_note.unwrap();
            if note_.token != order_tab_req.quote_token {
                return Err("token missmatch".to_string());
            }

            quote_amount -= note_.amount;
            quote_refund_note = Note::try_from(note_).ok();
        }

        // ? Get the public key from the sum of the notes
        sig_pub_key = EcPoint::from(&pub_key_sum).x.to_biguint().unwrap();

        drop(state_tree);
    }

    // ? Create an Orders tab object
    let pub_key =
        BigUint::from_str(order_tab_req.pub_key.as_str()).map_err(|err| err.to_string())?;
    let tab_header = TabHeader::new(
        order_tab_req.expiration_timestamp,
        order_tab_req.is_perp,
        order_tab_req.is_smart_contract,
        pub_key,
        order_tab_req.user_id,
        order_tab_req.market_id as u16,
    );

    let order_tab: OrderTab = OrderTab::new(
        tab_header,
        order_tab_req.base_token,
        order_tab_req.quote_token,
        base_amount,
        quote_amount,
        position,
    );

    // ? Verify the signature
    let signature = Signature::try_from(order_tab_req.signature.unwrap_or_default())
        .map_err(|err| err.to_string())?;
    let valid = verify(&sig_pub_key, &order_tab.hash, &signature);

    if !valid {
        return Err("Invalid Signature".to_string());
    }

    // ? If spot tab remove the notes from the state tree and add the refund notes
    // TODO

    // ? add it to the order tabs state
    let mut tabs_tree = order_tabs_state_tree.lock();
    let z_index = tabs_tree.first_zero_idx();
    tabs_tree.update_leaf_node(&order_tab.hash, z_index);
    // TODO: insert into UpdatedTabHashes

    // ? add it to the database
    // TODO: ADD TO DATATBASE

    Ok(())
}
