use error_stack::Result;
use num_bigint::{BigInt, BigUint};
use num_traits::{FromPrimitive, One, Zero};

//
use crate::utils::errors::{send_perp_swap_error, PerpSwapExecutionError};
use crate::utils::notes::Note;
//
use crate::perpetual::{OrderSide, PositionEffectType};

use crate::utils::crypto_utils::{pedersen, pedersen_on_vec, verify, EcPoint, Signature};

#[derive(Debug, Clone)]
pub struct PerpOrder {
    // Common to all orders
    pub order_id: u64,
    pub expiration_timestamp: u64,
    pub position: Option<PerpPosition>,
    pub position_effect_type: PositionEffectType,
    pub order_side: OrderSide,
    pub synthetic_token: u64,
    pub synthetic_amount: u64,
    pub collateral_amount: u64,
    pub fee_limit: u64,
    // * specific to Open orders (make this into one struct and wrap it in Option)
    pub open_order_fields: Option<OpenOrderFields>,
    // * Specific to Close orders
    pub close_order_fields: Option<CloseOrderFields>,
    //
    pub hash: BigUint,
}

impl PerpOrder {
    pub fn new_open_order(
        order_id: u64,
        expiration_timestamp: u64,
        order_side: OrderSide,
        synthetic_token: u64,
        synthetic_amount: u64,
        collateral_amount: u64,
        fee_limit: u64,
        open_order_fields: OpenOrderFields,
    ) -> PerpOrder {
        let position_effect_type = PositionEffectType::Open;

        let open_order_fields = Some(open_order_fields);

        let hash = hash_order(
            expiration_timestamp,
            &position_effect_type,
            &order_side,
            synthetic_token,
            synthetic_amount,
            collateral_amount,
            fee_limit,
            &None,
            &open_order_fields,
            &None,
        );

        return PerpOrder {
            order_id,
            expiration_timestamp,
            position: None,
            position_effect_type,
            order_side,
            synthetic_token,
            synthetic_amount,
            collateral_amount,
            fee_limit,
            open_order_fields,
            close_order_fields: None,
            hash,
        };
    }

    pub fn new_modify_order(
        order_id: u64,
        expiration_timestamp: u64,
        position: PerpPosition,
        order_side: OrderSide,
        synthetic_token: u64,
        synthetic_amount: u64,
        collateral_amount: u64,
        fee_limit: u64,
    ) -> PerpOrder {
        let position_effect_type = PositionEffectType::Modify;

        let hash = hash_order(
            expiration_timestamp,
            &position_effect_type,
            &order_side,
            synthetic_token,
            synthetic_amount,
            collateral_amount,
            fee_limit,
            &Some(&position),
            &None,
            &None,
        );

        return PerpOrder {
            order_id,
            expiration_timestamp,
            position: Some(position),
            position_effect_type,
            order_side,
            synthetic_token,
            synthetic_amount,
            collateral_amount,
            fee_limit,
            open_order_fields: None,
            close_order_fields: None,
            hash,
        };
    }

    pub fn new_close_order(
        order_id: u64,
        expiration_timestamp: u64,
        position: PerpPosition,
        order_side: OrderSide,
        synthetic_token: u64,
        synthetic_amount: u64,
        collateral_amount: u64,
        fee_limit: u64,
        close_order_fields: CloseOrderFields,
    ) -> PerpOrder {
        let position_effect_type = PositionEffectType::Close;
        let close_order_fields = Some(close_order_fields);

        let hash = hash_order(
            expiration_timestamp,
            &position_effect_type,
            &order_side,
            synthetic_token,
            synthetic_amount,
            collateral_amount,
            fee_limit,
            &Some(&position),
            &None,
            &close_order_fields,
        );

        return PerpOrder {
            order_id,
            expiration_timestamp,
            position: Some(position),
            position_effect_type,
            order_side,
            synthetic_token,
            synthetic_amount,
            collateral_amount,
            fee_limit,
            open_order_fields: None,
            close_order_fields,
            hash,
        };
    }

    pub fn new_liquidation_order(
        order_id: u64,
        expiration_timestamp: u64,
        position: PerpPosition,
        order_side: OrderSide,
        synthetic_token: u64,
        synthetic_amount: u64,
        collateral_amount: u64,
    ) -> PerpOrder {
        let position_effect_type = PositionEffectType::Liquidation;

        let hash = hash_order(
            expiration_timestamp,
            &position_effect_type,
            &order_side,
            synthetic_token,
            synthetic_amount,
            collateral_amount,
            0,
            &Some(&position),
            &None,
            &None,
        );

        return PerpOrder {
            order_id,
            expiration_timestamp,
            position: Some(position),
            position_effect_type,
            order_side,
            synthetic_token,
            synthetic_amount,
            collateral_amount,
            fee_limit: 0,
            open_order_fields: None,
            close_order_fields: None,
            hash,
        };
    }

    pub fn set_hash(&mut self) {
        let hash = hash_order(
            self.expiration_timestamp,
            &self.position_effect_type,
            &self.order_side,
            self.synthetic_token,
            self.synthetic_amount,
            self.collateral_amount,
            self.fee_limit,
            &self.position.as_ref(),
            &self.open_order_fields,
            &self.close_order_fields,
        );

        self.hash = hash;
    }

    pub fn verify_order_signature(
        &self,
        signature: &Signature,
        position_address: Option<&BigUint>,
    ) -> Result<Option<EcPoint>, PerpSwapExecutionError> {
        let order_hash = &self.hash;

        if self.position_effect_type == PositionEffectType::Open {
            let mut pub_key_sum: EcPoint = EcPoint {
                x: BigInt::zero(),
                y: BigInt::zero(),
            };
            for i in 0..self.open_order_fields.as_ref().unwrap().notes_in.len() {
                pub_key_sum = pub_key_sum
                    .add_point(&self.open_order_fields.as_ref().unwrap().notes_in[i].address);
            }

            let pk_sum = Some(pub_key_sum.clone());

            let valid = verify(
                &pub_key_sum.x.to_biguint().unwrap(),
                &order_hash,
                &signature,
            );

            if valid {
                return Ok(pk_sum);
            } else {
                return Err(send_perp_swap_error(
                    "Invalid Signature".to_string(),
                    Some(self.order_id),
                    Some(format!(
                        "Invalid signature: r:{:?} s:{:?}",
                        &signature.r, &signature.s,
                    )),
                ));
            }
        } else {
            let valid = verify(&position_address.unwrap(), &order_hash, &signature);

            if valid {
                return Ok(None);
            } else {
                return Err(send_perp_swap_error(
                    "Invalid Signature".to_string(),
                    Some(self.order_id),
                    Some(format!(
                        "Invalid signature: r:{:?} s:{:?}",
                        &signature.r, &signature.s,
                    )),
                ));
            }
        }
    }
}

use serde::ser::{Serialize, SerializeStruct, Serializer};

use super::perp_position::PerpPosition;
use super::DUST_AMOUNT_PER_ASSET;

impl Serialize for PerpOrder {
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut note = serializer.serialize_struct("PerpOrder", 13)?;

        note.serialize_field("order_id", &self.order_id)?;
        note.serialize_field("expiration_timestamp", &self.expiration_timestamp)?;

        let pos_addr_string = if self.position_effect_type == PositionEffectType::Open {
            self.open_order_fields
                .as_ref()
                .unwrap()
                .position_address
                .to_string()
        } else {
            self.position.as_ref().unwrap().position_address.to_string()
        };
        note.serialize_field("pos_addr", &pos_addr_string)?;
        note.serialize_field("position_effect_type", &self.position_effect_type)?;
        note.serialize_field("order_side", &self.order_side)?;
        note.serialize_field("synthetic_token", &self.synthetic_token)?;
        note.serialize_field("synthetic_amount", &self.synthetic_amount)?;
        note.serialize_field("collateral_amount", &self.collateral_amount)?;
        note.serialize_field("fee_limit", &self.fee_limit)?;
        note.serialize_field("open_order_fields", &self.open_order_fields)?;
        note.serialize_field("close_order_fields", &self.close_order_fields)?;
        let hash: &BigUint = &self.hash;
        note.serialize_field("hash", &hash.to_string())?;

        return note.end();
    }
}

//

//

//
#[derive(Debug, Clone)]
pub struct OpenOrderFields {
    pub initial_margin: u64,
    pub collateral_token: u64,
    pub notes_in: Vec<Note>,
    pub refund_note: Option<Note>,
    pub position_address: BigUint,
    pub blinding: BigUint,
    //
    // pub unspent_margin: Cell<u64>,
}

impl OpenOrderFields {
    pub fn hash(&self) -> BigUint {
        let mut hash_inputs: Vec<&BigUint> = Vec::new();

        self.notes_in
            .iter()
            .for_each(|note| hash_inputs.push(&note.hash));

        let z = BigUint::zero();

        let refund_note_hash: &BigUint;
        if self.refund_note.is_some() {
            if self.refund_note.as_ref().unwrap().amount
                <= DUST_AMOUNT_PER_ASSET[&self.refund_note.as_ref().unwrap().token.to_string()]
            {
                refund_note_hash = &z;
            } else {
                refund_note_hash = &self.refund_note.as_ref().unwrap().hash;
            }
        } else {
            refund_note_hash = &z;
        }
        hash_inputs.push(refund_note_hash);

        let initial_margin = BigUint::from_u64(self.initial_margin).unwrap();
        hash_inputs.push(&initial_margin);

        let collateral_token = BigUint::from_u64(self.collateral_token).unwrap();
        hash_inputs.push(&collateral_token);

        let addr_x = &self.position_address;
        hash_inputs.push(addr_x);

        hash_inputs.push(&self.blinding);

        return pedersen_on_vec(&hash_inputs);
    }
}

impl Serialize for OpenOrderFields {
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut note = serializer.serialize_struct("OpenOrderFields", 6)?;

        note.serialize_field("initial_margin", &self.initial_margin)?;
        note.serialize_field("collateral_token", &self.collateral_token)?;
        note.serialize_field("notes_in", &self.notes_in)?;
        note.serialize_field("refund_note", &self.refund_note)?;
        note.serialize_field("position_address", &self.position_address.to_string())?;
        note.serialize_field("blinding", &self.blinding.to_string())?;

        return note.end();
    }
}

#[derive(Debug, Clone)]
pub struct CloseOrderFields {
    pub dest_received_address: EcPoint,
    pub dest_received_blinding: BigUint,
}

impl CloseOrderFields {
    pub fn hash(&self) -> BigUint {
        let addr_x = self.dest_received_address.x.to_biguint().unwrap();

        return pedersen(&addr_x, &self.dest_received_blinding);
    }
}

impl Serialize for CloseOrderFields {
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut note = serializer.serialize_struct("CloseOrderFields", 2)?;

        note.serialize_field("dest_received_address", &self.dest_received_address)?;
        note.serialize_field(
            "dest_received_blinding",
            &self.dest_received_blinding.to_string(),
        )?;

        return note.end();
    }
}

fn hash_order(
    expiration_timestamp: u64,
    position_effect_type: &PositionEffectType,
    order_side: &OrderSide,
    synthetic_token: u64,
    synthetic_amount: u64,
    collateral_amount: u64,
    fee_limit: u64,
    position: &Option<&PerpPosition>,
    open_order_fields: &Option<OpenOrderFields>,
    close_order_fields: &Option<CloseOrderFields>,
) -> BigUint {
    let mut hash_inputs: Vec<&BigUint> = Vec::new();

    let expiration_timestamp = BigUint::from_u64(expiration_timestamp).unwrap();
    hash_inputs.push(&expiration_timestamp);
    let pos_addr_string = if *position_effect_type == PositionEffectType::Open {
        &open_order_fields.as_ref().unwrap().position_address
    } else {
        &position.as_ref().unwrap().position_address
    };
    hash_inputs.push(pos_addr_string);

    let position_effect_type_: BigUint;
    match position_effect_type {
        PositionEffectType::Open => position_effect_type_ = BigUint::from_i8(0).unwrap(),
        PositionEffectType::Modify => position_effect_type_ = BigUint::from_i8(1).unwrap(),
        PositionEffectType::Close => position_effect_type_ = BigUint::from_i8(2).unwrap(),
        PositionEffectType::Liquidation => position_effect_type_ = BigUint::from_i8(3).unwrap(),
    }
    hash_inputs.push(&position_effect_type_);

    let order_side: BigUint = if *order_side == OrderSide::Long {
        BigUint::zero()
    } else {
        BigUint::one()
    };
    hash_inputs.push(&order_side);

    let synthetic_token = BigUint::from_u64(synthetic_token).unwrap();
    hash_inputs.push(&synthetic_token);
    let synthetic_amount = BigUint::from_u64(synthetic_amount).unwrap();
    hash_inputs.push(&synthetic_amount);
    let collateral_amount = BigUint::from_u64(collateral_amount).unwrap();
    hash_inputs.push(&collateral_amount);
    let fee_limit = BigUint::from_u64(fee_limit).unwrap();
    hash_inputs.push(&fee_limit);

    let order_hash = pedersen_on_vec(&hash_inputs);

    if *position_effect_type == PositionEffectType::Open {
        return pedersen(&order_hash, &open_order_fields.as_ref().unwrap().hash());
    } else if *position_effect_type == PositionEffectType::Close {
        return pedersen(&order_hash, &close_order_fields.as_ref().unwrap().hash());
    } else {
        return order_hash;
    }
}
