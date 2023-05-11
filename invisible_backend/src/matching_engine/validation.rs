use crate::perpetual::{PositionEffectType, TOKENS, VALID_COLLATERAL_TOKENS};
use crate::utils::crypto_utils::Signature;

use super::{domain::Order, orders::OrderRequest};

/// Validation errors
const ERR_BAD_ORDER_ASSET: &str = "bad order asset";
const ERR_BAD_PRICE_ASSET: &str = "bad price asset";
const ERR_BAD_PRICE_VALUE: &str = "price must be non-negative";
const ERR_EXPIRED_ORDER: &str = "order has expired";
const ERR_BAD_SEQ_ID: &str = "order ID out of range";

/* Validators */

pub struct OrderRequestValidator {
    orderbook_order_asset: u64,
    orderbook_price_asset: u64,
    min_sequence_id: u64,
    max_sequence_id: u64,
}

impl OrderRequestValidator {
    pub fn new(
        orderbook_order_asset: u64,
        orderbook_price_asset: u64,
        min_sequence_id: u64,
        max_sequence_id: u64,
    ) -> Self {
        OrderRequestValidator {
            orderbook_order_asset,
            orderbook_price_asset,
            min_sequence_id,
            max_sequence_id,
        }
    }

    pub fn validate(&self, request: &OrderRequest) -> Result<(), &str> {
        match request {
            OrderRequest::NewLimitOrder {
                order_asset,
                price_asset,
                side: _side,
                price,
                qty,
                order,
                ..
            } => {
                if *price <= 0.0 {
                    return Err(ERR_BAD_PRICE_VALUE);
                };
                return self.validate_order(
                    *order_asset,
                    *price_asset,
                    *qty,
                    &order.order,
                    &order.signature,
                );
            }

            OrderRequest::CancelOrder { id, .. } => self.validate_cancel(*id),

            OrderRequest::AmendOrder { id, .. } => self.validate_cancel(*id),
        }
    }

    /* Internal validators */

    fn validate_order(
        &self,
        order_asset: u64,
        price_asset: u64,
        _qty: u64,
        order: &Order,
        signature: &Signature,
    ) -> Result<(), &str> {
        if self.orderbook_order_asset != order_asset {
            return Err(ERR_BAD_ORDER_ASSET);
        }

        if self.orderbook_price_asset != price_asset {
            return Err(ERR_BAD_PRICE_ASSET);
        }

        if order.has_expired() {
            return Err(ERR_EXPIRED_ORDER);
        }

        match order {
            Order::Spot(limit_order) => {
                // ? Chack that the tokens are valid
                if (!TOKENS.contains(&limit_order.token_spent)
                    && !VALID_COLLATERAL_TOKENS.contains(&limit_order.token_spent))
                    || (!TOKENS.contains(&limit_order.token_received)
                        && !VALID_COLLATERAL_TOKENS.contains(&limit_order.token_received))
                {
                    return Err("Tokens swapped are not valid");
                }

                // ? Check that the notes spent are all different
                let mut spent_indexes: Vec<u64> = Vec::new();
                for note in &limit_order.notes_in {
                    if spent_indexes.contains(&note.index) {
                        return Err("Notes spent are not all different");
                    }
                    spent_indexes.push(note.index);
                }

                // ? Check that the signature is valid
                if let Err(_e) = limit_order.verify_order_signature(&signature) {
                    return Err("Invalid signature");
                }

                // Check the amounts and tokens match the notes being spent
                let mut err = false;
                let note_sum = limit_order.notes_in.iter().fold(0, |sum, n| {
                    if n.token != limit_order.token_spent {
                        err = true;
                    }
                    sum + n.amount
                });

                if note_sum < limit_order.amount_spent || err {
                    return Err("Invalid notes");
                }
            }
            Order::Perp(perp_order) => {
                if !TOKENS.contains(&perp_order.synthetic_token) {
                    return Err("Synthetic token is invalid");
                };
                match perp_order.position_effect_type {
                    PositionEffectType::Open => {
                        if !VALID_COLLATERAL_TOKENS.contains(
                            &perp_order
                                .open_order_fields
                                .as_ref()
                                .unwrap()
                                .collateral_token,
                        ) {
                            return Err("collateral token not valid");
                        }

                        // ? Verify order signature
                        if let Err(_) = perp_order.verify_order_signature(signature, None) {
                            return Err("Invalid signature");
                        }

                        let mut spent_indexes: Vec<u64> = Vec::new();
                        let mut sum: u64 = 0;
                        for note in &perp_order.open_order_fields.as_ref().unwrap().notes_in {
                            if note.token
                                != perp_order
                                    .open_order_fields
                                    .as_ref()
                                    .unwrap()
                                    .collateral_token
                            {
                                return Err("Invalid collateral token notes");
                            }

                            if spent_indexes.contains(&note.index) {
                                return Err("Notes spent are not all different");
                            }
                            spent_indexes.push(note.index);
                            sum += note.amount;
                        }
                        if sum
                            < perp_order
                                .open_order_fields
                                .as_ref()
                                .unwrap()
                                .initial_margin
                        {
                            return Err("Notes spent are not enough to cover initial margin");
                        }
                    }
                    PositionEffectType::Modify => {
                        if let Some(pos) = &perp_order.position {
                            // ? Verify order signature
                            if let Err(_) = perp_order
                                .verify_order_signature(signature, Some(&pos.position_address))
                            {
                                return Err("Invalid signature");
                            }
                        } else {
                            return Err("Position to update is undefined");
                        }

                        // ? Verify the position hash is valid and exists in the state
                        if perp_order.position.as_ref().unwrap().hash
                            != perp_order.position.as_ref().unwrap().hash_position()
                        {
                            return Err("position hash not valid");
                        }

                        // ? Check that order token matches synthetic token
                        if perp_order.position.as_ref().unwrap().synthetic_token
                            != perp_order.synthetic_token
                        {
                            return Err("Position and order should have same synthetic token");
                        }
                    }
                    PositionEffectType::Close => {
                        if let Some(pos) = &perp_order.position {
                            // ? Verify order signature
                            if let Err(_) = perp_order
                                .verify_order_signature(signature, Some(&pos.position_address))
                            {
                                return Err("Invalid signature");
                            }
                        } else {
                            return Err("Position to update is undefined");
                        }

                        // ? Verify the position hash is valid and exists in the state
                        if perp_order.position.as_ref().unwrap().hash
                            != perp_order.position.as_ref().unwrap().hash_position()
                        {
                            return Err("position hash not valid");
                        }

                        // ? Check that order token matches synthetic token
                        if perp_order.position.as_ref().unwrap().synthetic_token
                            != perp_order.synthetic_token
                        {
                            return Err("Position and order should have same synthetic token");
                        }
                    }
                    PositionEffectType::Liquidation => {
                        if let None = &perp_order.position {
                            return Err("Position to update is undefined");
                        }

                        // ? Verify the position hash is valid and exists in the state
                        if perp_order.position.as_ref().unwrap().hash
                            != perp_order.position.as_ref().unwrap().hash_position()
                        {
                            return Err("position hash not valid");
                        }

                        // ? Check that order token matches synthetic token
                        if perp_order.position.as_ref().unwrap().synthetic_token
                            != perp_order.synthetic_token
                        {
                            return Err("Position and order should have same synthetic token");
                        }
                    }
                }
            }
        }

        Ok(())
    }

    fn validate_cancel(&self, id: u64) -> Result<(), &str> {
        let seq_id = id % 2_u64.pow(16);

        if self.min_sequence_id > seq_id || self.max_sequence_id < seq_id {
            return Err(ERR_BAD_SEQ_ID);
        }

        Ok(())
    }
}
