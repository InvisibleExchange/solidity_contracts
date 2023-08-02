use std::{fmt::Debug, time::SystemTime};

// let could_be_matched;
//             let opposite_price: f64;
//             match side {
//                 // verify bid/ask price overlap
//                 OrderSide::Bid => {
//                     if is_market_order && price >= opposite_order.price + 0.01 {
//                         could_be_matched = true;
//                         opposite_price = opposite_order.price + 0.01;
//                     } else {
//                         if price >= opposite_order.price {
//                             could_be_matched = true;
//                         } else {
//                             could_be_matched = false;
//                         }
//                         opposite_price = opposite_order.price;
//                     }
//                 }
//                 OrderSide::Ask => {
//                     if is_market_order && price <= opposite_order.price - 0.01 {
//                         could_be_matched = true;
//                         opposite_price = opposite_order.price - 0.01;
//                     } else {
//                         if price <= opposite_order.price {
//                             could_be_matched = true;
//                         } else {
//                             could_be_matched = false;
//                         }
//                         opposite_price = opposite_order.price;
//                     }
//                 }
//             };

//             if could_be_matched {

use crate::{
    perpetual::{
        get_cross_price, perp_order::PerpOrder, OrderSide as PerpOrderSide, VALID_COLLATERAL_TOKENS,
    },
    transactions::limit_order::LimitOrder,
};

use crate::utils::crypto_utils::Signature;

use super::{get_qty_from_quote, get_quote_qty};

#[derive(Debug, Copy, Clone, PartialEq)]
pub enum OrderSide {
    Bid,
    Ask,
}

impl From<PerpOrderSide> for OrderSide {
    fn from(req: PerpOrderSide) -> Self {
        if req == PerpOrderSide::Long {
            return OrderSide::Bid;
        } else {
            return OrderSide::Ask;
        }
    }
}

#[derive(Debug, Clone)]
pub struct OrderWrapper {
    pub order: Order,          // The order to be executed
    pub signature: Signature,  // The order signature
    pub order_id: u64,         // The id of the order
    pub order_side: OrderSide, // The side of the order
    pub qty_left: u64,         // The amount left to be executed
    pub user_id: u64,
}

#[derive(Debug, Clone)]
pub enum Order {
    Spot(LimitOrder),
    Perp(PerpOrder),
}

impl Order {
    pub fn set_id(&mut self, id: u64) {
        match self {
            Order::Spot(ord) => {
                ord.order_id = id;
            }
            Order::Perp(ord) => {
                ord.order_id = id;
            }
        }
    }

    pub fn get_order_and_price_assets(&self, side: OrderSide) -> (u32, u32) {
        // Returns (order asset, price asset)
        match self {
            Order::Spot(ord) => match side {
                OrderSide::Bid => {
                    let order_asset = ord.token_received;
                    let price_asset = ord.token_spent;
                    return (order_asset, price_asset);
                }
                OrderSide::Ask => {
                    let order_asset = ord.token_spent;
                    let price_asset = ord.token_received;
                    return (order_asset, price_asset);
                }
            },
            Order::Perp(ord) => {
                let order_asset = ord.synthetic_token;
                let price_asset = VALID_COLLATERAL_TOKENS[0];
                return (order_asset, price_asset);
            }
        }
    }

    pub fn get_base_and_quote_qty(&self, side: OrderSide, price: f64) -> (u64, u64) {
        match self {
            Order::Spot(ord) => match side {
                OrderSide::Bid => {
                    return (
                        get_qty_from_quote(
                            ord.amount_spent,
                            price,
                            ord.token_received,
                            ord.token_spent,
                        ),
                        ord.amount_spent,
                    );

                    // return ord.amount_received;
                }
                OrderSide::Ask => {
                    return (
                        ord.amount_spent,
                        get_quote_qty(
                            ord.amount_spent,
                            price,
                            ord.token_spent,
                            ord.token_received,
                            None,
                        ),
                    );
                }
            },
            Order::Perp(ord) => {
                return (ord.synthetic_amount, ord.collateral_amount);
            }
        }
    }

    /// Checks if the order has expired, by checking that the expiration time is greater than the current system time
    ///
    /// ### Returns:
    /// * `bool`: True if the order has expired, false if it hasn't
    pub fn has_expired(&self) -> bool {
        let now = SystemTime::now();

        let seconds_since_epoch = now
            .duration_since(SystemTime::UNIX_EPOCH)
            .expect("Time went backwards")
            .as_secs();

        match self {
            Order::Spot(ord) => {
                if ord.expiration_timestamp < seconds_since_epoch {
                    return true;
                }
            }
            Order::Perp(ord) => {
                if ord.expiration_timestamp < seconds_since_epoch {
                    return true;
                }
            }
        }

        false
    }

    pub fn get_price(&self, side: OrderSide, round: Option<bool>) -> f64 {
        match self {
            Order::Spot(ord) => match side {
                OrderSide::Bid => {
                    return get_cross_price(
                        ord.token_received,
                        ord.token_spent,
                        ord.amount_received,
                        ord.amount_spent,
                        round,
                    );
                }
                OrderSide::Ask => {
                    return get_cross_price(
                        ord.token_spent,
                        ord.token_received,
                        ord.amount_spent,
                        ord.amount_received,
                        round,
                    );
                }
            },
            Order::Perp(ord) => {
                return get_cross_price(
                    ord.synthetic_token,
                    VALID_COLLATERAL_TOKENS[0],
                    ord.synthetic_amount,
                    ord.collateral_amount,
                    round,
                );
            }
        }
    }
}

#[derive(Eq, PartialEq, Debug, Copy, Clone)]
pub enum OrderType {
    Market,
    Limit,
}
