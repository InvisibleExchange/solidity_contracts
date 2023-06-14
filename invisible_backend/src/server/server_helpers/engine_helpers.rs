use num_bigint::BigUint;
use num_traits::{FromPrimitive, Zero};
use parking_lot::Mutex;
use serde_json::Value;
use starknet::curve::AffinePoint;
use std::{str::FromStr, sync::Arc};

use crate::{
    perpetual::perp_position::PerpPosition,
    server::grpc::{engine::Signature as GrpcSignature, ChangeMarginMessage},
    trees::superficial_tree::SuperficialTree,
    utils::storage::MainStorage,
};

use crate::utils::crypto_utils::{pedersen_on_vec, verify, EcPoint, Signature};

use crate::utils::notes::Note;

pub fn verify_signature_format(sig: &Option<GrpcSignature>) -> Result<Signature, String> {
    // ? Verify the signature is defined and has a valid format
    let signature: Signature;
    if sig.is_none() {
        return Err("Signature is missing".to_string());
    }
    match Signature::try_from(sig.as_ref().unwrap().clone()) {
        Ok(sig) => signature = sig,
        Err(_e) => {
            return Err("Signature format is invalid".to_string());
        }
    }

    return Ok(signature);
}

pub fn verify_notes_existence(
    notes_in: &Vec<Note>,
    state_tree: &Arc<Mutex<SuperficialTree>>,
) -> Result<(), String> {
    let tree = state_tree.lock();

    for note in notes_in {
        let leaf_hash = tree.get_leaf_by_index(note.index);

        if leaf_hash != note.hash {
            return Err("Note does not exist".to_string());
        }
    }

    Ok(())
}

pub fn verify_position_existence(
    position: &PerpPosition,
    perp_state_tree: &Arc<Mutex<SuperficialTree>>,
) -> Result<(), String> {
    if position.hash != position.hash_position() {
        return Err("Position hash not valid".to_string());
    }

    let tree = perp_state_tree.lock();

    let leaf_hash = tree.get_leaf_by_index(position.index as u64);

    if leaf_hash != position.hash {
        return Err("Position does not exist".to_string());
    }

    Ok(())
}

pub fn verify_margin_change_signature(margin_change: &ChangeMarginMessage) -> Result<(), String> {
    // ? Verify the signature is defined and has a valid format
    let msg_hash = hash_margin_change_message(margin_change);

    if margin_change.margin_change >= 0 {
        let mut pub_key_sum: AffinePoint = AffinePoint::identity();

        let notes_in = margin_change.notes_in.as_ref().unwrap();
        for i in 0..notes_in.len() {
            let ec_point = AffinePoint::from(&notes_in[i].address);
            pub_key_sum = &pub_key_sum + &ec_point;
        }

        let pub_key: EcPoint = EcPoint::from(&pub_key_sum);

        let valid = verify(
            &pub_key.x.to_biguint().unwrap(),
            &msg_hash,
            &margin_change.signature,
        );

        if !valid {
            return Err("Signature is invalid".to_string());
        }
    } else {
        let valid = verify(
            &margin_change.position.position_address,
            &msg_hash,
            &margin_change.signature,
        );

        if !valid {
            return Err("Signature is invalid".to_string());
        }
    }

    Ok(())
}

fn hash_margin_change_message(margin_change: &ChangeMarginMessage) -> BigUint {
    //

    if margin_change.margin_change >= 0 {
        let mut hash_inputs: Vec<&BigUint> = margin_change
            .notes_in
            .as_ref()
            .unwrap()
            .iter()
            .map(|note| &note.hash)
            .collect::<Vec<&BigUint>>();

        let z = BigUint::zero();
        let refund_hash = if margin_change.refund_note.is_some() {
            &margin_change.refund_note.as_ref().unwrap().hash
        } else {
            &z
        };
        hash_inputs.push(refund_hash);

        hash_inputs.push(&margin_change.position.hash);

        let hash = pedersen_on_vec(&hash_inputs);

        return hash;
    } else {
        let mut hash_inputs = vec![];

        let p = BigUint::from_str(
            "3618502788666131213697322783095070105623107215331596699973092056135872020481",
        )
        .unwrap();

        let margin_change_amount =
            p - BigUint::from_u64(margin_change.margin_change.abs() as u64).unwrap();
        hash_inputs.push(&margin_change_amount);

        let fields_hash = &margin_change.close_order_fields.as_ref().unwrap().hash();
        hash_inputs.push(fields_hash);

        hash_inputs.push(&margin_change.position.hash);

        let hash = pedersen_on_vec(&hash_inputs);

        return hash;
    }
}

pub fn store_output_json(
    swap_output_json_: &Arc<Mutex<Vec<serde_json::Map<String, Value>>>>,
    main_storage_: &Arc<Mutex<MainStorage>>,
) {
    let mut swap_output_json = swap_output_json_.lock();
    if !swap_output_json.is_empty() {
        let main_storage = main_storage_.lock();
        main_storage.store_micro_batch(&swap_output_json);
        swap_output_json.clear();
        drop(swap_output_json);
        drop(main_storage);
    } else {
        drop(swap_output_json);
    }
}
