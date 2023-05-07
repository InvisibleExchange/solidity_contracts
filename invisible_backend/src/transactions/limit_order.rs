use crate::perpetual::DUST_AMOUNT_PER_ASSET;
use crate::utils::crypto_utils::{pedersen_on_vec, verify, EcPoint, Signature};
use crate::utils::errors::{send_swap_error, SwapThreadExecutionError};

use error_stack::Result;
use num_bigint::{BigInt, BigUint};
use num_traits::{FromPrimitive, Zero};

//
use crate::utils::notes::Note;
//

#[derive(Debug, Clone)]
pub struct LimitOrder {
    pub order_id: u64,
    pub expiration_timestamp: u64,
    pub token_spent: u64,
    pub token_received: u64,
    pub amount_spent: u64,
    pub amount_received: u64,
    pub fee_limit: u64,
    //& dest_spent is for the refund and partial fill refund notes
    //& dest_received is for the swap output notes (should be the ec sum of input note addresses)
    pub dest_received_address: EcPoint,
    pub dest_spent_blinding: BigUint,
    pub dest_received_blinding: BigUint,
    //
    pub notes_in: Vec<Note>,
    pub refund_note: Option<Note>,
    pub hash: BigUint,
}

impl LimitOrder {
    pub fn new(
        order_id: u64,
        expiration_timestamp: u64,
        token_spent: u64,
        token_received: u64,
        amount_spent: u64,
        amount_received: u64,
        fee_limit: u64,
        dest_received_address: EcPoint,
        dest_spent_blinding: BigUint,
        dest_received_blinding: BigUint,
        notes_in: Vec<Note>,
        refund_note_: Option<Note>,
    ) -> LimitOrder {
        let refund_note: Option<Note>;
        if refund_note_.is_some() {
            if refund_note_.as_ref().unwrap().amount
                <= DUST_AMOUNT_PER_ASSET[&refund_note_.as_ref().unwrap().token.to_string()]
            {
                refund_note = None;
            } else {
                refund_note = Some(refund_note_.unwrap())
            }
        } else {
            refund_note = None
        };

        let hash = hash_order(
            expiration_timestamp,
            token_spent,
            token_received,
            amount_spent,
            amount_received,
            fee_limit,
            // &dest_spent_address,
            &dest_received_address,
            &dest_spent_blinding,
            &dest_received_blinding,
            &notes_in,
            &refund_note,
        );

        LimitOrder {
            order_id,
            expiration_timestamp,
            token_spent,
            token_received,
            amount_spent,
            amount_received,
            fee_limit,
            // dest_spent_address,
            dest_received_address,
            dest_spent_blinding,
            dest_received_blinding,
            notes_in,
            refund_note,
            hash,
        }
    }

    pub fn set_hash(&mut self) {
        let hash = hash_order(
            self.expiration_timestamp,
            self.token_spent,
            self.token_received,
            self.amount_spent,
            self.amount_received,
            self.fee_limit,
            // &dest_spent_address,
            &self.dest_received_address,
            &self.dest_spent_blinding,
            &self.dest_received_blinding,
            &self.notes_in,
            &self.refund_note,
        );

        self.hash = hash;
    }

    pub fn verify_order_signature(
        &self,
        signature: &Signature,
    ) -> Result<EcPoint, SwapThreadExecutionError> {
        let order_hash = &self.hash;

        let mut pub_key_sum: EcPoint = EcPoint {
            x: BigInt::zero(),
            y: BigInt::zero(),
        };

        for i in 0..self.notes_in.len() {
            pub_key_sum = pub_key_sum.add_point(&self.notes_in[i].address);
        }

        let valid = verify(
            &pub_key_sum.x.to_biguint().unwrap(),
            &order_hash,
            &signature,
        );

        if valid {
            return Ok(pub_key_sum);
        } else {
            return Err(send_swap_error(
                "Invalid Signature".to_string(),
                Some(self.order_id),
                Some(format!(
                    "Invalid signature: r:{:?} s:{:?} hash:{:?} pub_key:{:?}",
                    &signature.r, &signature.s, order_hash, pub_key_sum
                )),
            ));
        }
    }
}

// * SERIALIZE * //

use serde::ser::{Serialize, SerializeStruct, Serializer};

impl Serialize for LimitOrder {
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut note = serializer.serialize_struct("LimitOrder", 13)?;

        note.serialize_field("order_id", &self.order_id)?;
        note.serialize_field("expiration_timestamp", &self.expiration_timestamp)?;
        note.serialize_field("token_spent", &self.token_spent)?;
        note.serialize_field("token_received", &self.token_received)?;
        note.serialize_field("amount_spent", &self.amount_spent)?;
        note.serialize_field("amount_received", &self.amount_received)?;
        note.serialize_field("fee_limit", &self.fee_limit)?;
        // note.serialize_field("dest_spent_address", &self.dest_spent_address)?;
        note.serialize_field("dest_received_address", &self.dest_received_address)?;
        note.serialize_field("dest_spent_blinding", &self.dest_spent_blinding.to_string())?;
        note.serialize_field(
            "dest_received_blinding",
            &self.dest_received_blinding.to_string(),
        )?;
        note.serialize_field("fee_limit", &self.fee_limit)?;
        note.serialize_field("notes_in", &self.notes_in)?;
        note.serialize_field("refund_note", &self.refund_note)?;
        let hash: &BigUint = &self.hash;
        note.serialize_field("hash", &hash.to_string())?;

        return note.end();
    }
}

fn hash_order(
    expiration_timestamp: u64,
    token_spent: u64,
    token_received: u64,
    amount_spent: u64,
    amount_received: u64,
    fee_limit: u64,
    // dest_spent_address: &EcPoint,
    dest_received_address: &EcPoint,
    dest_spent_blinding: &BigUint,
    dest_received_blinding: &BigUint,
    notes_in: &Vec<Note>,
    refund_note: &Option<Note>,
) -> BigUint {
    let note_hashes: Vec<&BigUint> = notes_in
        .iter()
        .map(|note| &note.hash)
        .collect::<Vec<&BigUint>>();

    let z = BigUint::zero();
    let refund_hash: &BigUint;
    if refund_note.is_some() {
        refund_hash = &refund_note.as_ref().unwrap().hash
    } else {
        refund_hash = &z;
    };

    let mut hash_inputs: Vec<&BigUint> = Vec::new();
    for n_hash in note_hashes {
        hash_inputs.push(n_hash);
    }

    hash_inputs.push(refund_hash);
    let expiration_timestamp = BigUint::from_u64(expiration_timestamp).unwrap();
    hash_inputs.push(&expiration_timestamp);
    let token_spent = BigUint::from_u64(token_spent).unwrap();
    hash_inputs.push(&token_spent);
    let token_received = BigUint::from_u64(token_received).unwrap();
    hash_inputs.push(&token_received);
    let amount_spent = BigUint::from_u64(amount_spent).unwrap();
    hash_inputs.push(&amount_spent);
    let amount_received = BigUint::from_u64(amount_received).unwrap();
    hash_inputs.push(&amount_received);
    let fee_limit = BigUint::from_u64(fee_limit).unwrap();
    hash_inputs.push(&fee_limit);
    // let dsa_x = dest_spent_address.x.to_biguint().unwrap();
    // hash_inputs.push(&dsa_x);
    let dra_x = dest_received_address.x.to_biguint().unwrap();
    hash_inputs.push(&dra_x);
    hash_inputs.push(&dest_spent_blinding);
    hash_inputs.push(&dest_received_blinding);

    let order_hash = pedersen_on_vec(&hash_inputs);

    return order_hash;
}
