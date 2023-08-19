use crate::perpetual::{
    PositionEffectType, ASSETS, COLLATERAL_TOKEN, DUST_AMOUNT_PER_ASSET, SYNTHETIC_ASSETS,
};
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
    orderbook_order_asset: u32,
    orderbook_price_asset: u32,
    min_sequence_id: u64,
    max_sequence_id: u64,
}

impl OrderRequestValidator {
    pub fn new(
        orderbook_order_asset: u32,
        orderbook_price_asset: u32,
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
        order_asset: u32,
        price_asset: u32,
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

                if !ASSETS.contains(&limit_order.token_spent)
                    || !ASSETS.contains(&limit_order.token_received)
                {
                    return Err("Tokens swapped are not valid");
                }

                // ? Verify order amount is not too small
                if limit_order.amount_spent
                    < DUST_AMOUNT_PER_ASSET[&limit_order.token_spent.to_string()]
                    || limit_order.amount_received
                        < DUST_AMOUNT_PER_ASSET[&limit_order.token_received.to_string()]
                {
                    return Err("Order amount is too small");
                }

                // ? Check that the signature is valid
                let order_tab_lock = if limit_order.order_tab.is_some() {
                    Some(limit_order.order_tab.as_ref().unwrap().lock().clone())
                } else {
                    None
                };
                if let Err(_e) = limit_order.verify_order_signature(&signature, &order_tab_lock) {
                    return Err("Invalid signature");
                }
                drop(order_tab_lock);

                if limit_order.spot_note_info.is_some() {
                    let note_info = limit_order.spot_note_info.as_ref().unwrap();

                    // ? Check that the notes spent are all different
                    let mut spent_indexes: Vec<u64> = Vec::new();
                    for note in &note_info.notes_in {
                        if spent_indexes.contains(&note.index) {
                            return Err("Notes spent are not all different");
                        }
                        spent_indexes.push(note.index);
                    }

                    // ? Check the amounts and tokens match the notes being spent
                    let mut err = false;
                    let note_sum = note_info.notes_in.iter().fold(0, |sum, n| {
                        if n.token != limit_order.token_spent {
                            err = true;
                        }
                        sum + n.amount
                    });

                    if note_sum < limit_order.amount_spent || err {
                        return Err("Invalid notes");
                    }
                } else if limit_order.order_tab.is_some() {
                    // ? Check that the order tab is valid
                    let order_tab = limit_order.order_tab.as_ref().unwrap().lock();
                    if (order_tab.tab_header.base_token != limit_order.token_spent
                        || order_tab.tab_header.quote_token != limit_order.token_received)
                        && (order_tab.tab_header.base_token != limit_order.token_received
                            || order_tab.tab_header.quote_token != limit_order.token_spent)
                    {
                        return Err("Token missmatch");
                    }

                    if limit_order.token_spent == order_tab.tab_header.base_token {
                        if limit_order.amount_spent > order_tab.base_amount {
                            return Err("Overspending base token");
                        }
                    } else {
                        if limit_order.amount_spent > order_tab.quote_amount {
                            return Err("Overspending quote token");
                        }
                    }
                }
            }
            Order::Perp(perp_order) => {
                if !SYNTHETIC_ASSETS.contains(&perp_order.synthetic_token) {
                    return Err("Synthetic token is invalid");
                };

                if perp_order.synthetic_amount
                    < DUST_AMOUNT_PER_ASSET[&perp_order.synthetic_token.to_string()]
                {
                    return Err("Order amount is too small");
                }

                match perp_order.position_effect_type {
                    PositionEffectType::Open => {
                        if COLLATERAL_TOKEN
                            != perp_order
                                .open_order_fields
                                .as_ref()
                                .unwrap()
                                .collateral_token
                        {
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
                            if let Err(_) = perp_order.verify_order_signature(
                                signature,
                                Some(&pos.position_header.position_address),
                            ) {
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
                        if perp_order
                            .position
                            .as_ref()
                            .unwrap()
                            .position_header
                            .synthetic_token
                            != perp_order.synthetic_token
                        {
                            return Err("Position and order should have same synthetic token");
                        }
                    }
                    PositionEffectType::Close => {
                        if let Some(pos) = &perp_order.position {
                            // ? Verify order signature
                            if let Err(_) = perp_order.verify_order_signature(
                                signature,
                                Some(&pos.position_header.position_address),
                            ) {
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
                        if perp_order
                            .position
                            .as_ref()
                            .unwrap()
                            .position_header
                            .synthetic_token
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
