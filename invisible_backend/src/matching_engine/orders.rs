use std::fmt::Debug;
use std::time::SystemTime;

use crate::{perpetual::VALID_COLLATERAL_TOKENS, utils::crypto_utils::Signature};

use super::{
    domain::{Order, OrderSide, OrderWrapper},
    get_qty_from_quote, get_quote_qty,
};

#[derive(Debug, Clone)]
pub enum OrderRequest {
    // NewMarketOrder {
    //     order_asset: u64,
    //     price_asset: u64,
    //     side: OrderSide,
    //     qty: u64,
    //     order: OrderWrapper,
    //     ts: SystemTime,
    // },
    NewLimitOrder {
        order_asset: u64,
        price_asset: u64,
        side: OrderSide,
        price: f64,
        qty: u64,
        quote_qty: u64,
        order: OrderWrapper,
        ts: SystemTime,
        is_market: bool,
    },
    AmendOrder {
        id: u64,
        side: OrderSide,
        new_price: f64,
        new_expiration: u64,
        signature: Signature,
        user_id: u64,
        match_only: bool,
    },
    CancelOrder {
        id: u64,
        side: OrderSide,
        user_id: u64,
        //ts: SystemTime,
    },
}

/// Create request for the new limit order
pub fn new_limit_order_request(
    side: OrderSide,
    order: Order,
    signature: Signature,
    ts: SystemTime,
    is_market: bool,
    user_id: u64,
) -> OrderRequest {
    let (order_asset, price_asset) = order.get_order_and_price_assets(side);

    let price: f64 = order.get_price(side, Some(side == OrderSide::Ask));

    let (qty, quote_qty) = order.get_base_and_quote_qty(side, price);

    let order = OrderWrapper {
        order,
        signature,
        qty_left: qty,
        order_id: 0,
        order_side: side,
        user_id,
    };

    OrderRequest::NewLimitOrder {
        order_asset,
        price_asset,
        side,
        price,
        qty,
        quote_qty,
        order,
        ts,
        is_market,
    }
}

/// Create request for cancelling active limit order
pub fn limit_order_cancel_request(order_id: u64, side: OrderSide, user_id: u64) -> OrderRequest {
    OrderRequest::CancelOrder {
        id: order_id,
        side,
        user_id,
    }
}

/// Create request for cancelling active limit order
pub fn new_amend_order(
    order_id: u64,
    side: OrderSide,
    user_id: u64,
    new_price: f64,
    new_expiration: u64,
    signature: Signature,
    match_only: bool,
) -> OrderRequest {
    OrderRequest::AmendOrder {
        id: order_id,
        side,
        new_price,
        new_expiration,
        signature,
        user_id,
        match_only,
    }
}

/// Amend an order
pub fn amend_inner(
    wrapper: &mut OrderWrapper,
    price: f64,
    new_expiration: u64,
    signature: Signature,
) {
    if wrapper.order_side == OrderSide::Bid {
        match &mut wrapper.order {
            Order::Spot(ord) => {
                let base_asset = ord.token_received;
                let quote_asset = ord.token_spent;

                let new_received_amount =
                    get_qty_from_quote(ord.amount_spent, price, base_asset, quote_asset);

                ord.amount_received = new_received_amount;
                ord.expiration_timestamp = new_expiration;
            }
            Order::Perp(ord) => {
                let new_collateral_amount = get_quote_qty(
                    ord.synthetic_amount,
                    price,
                    ord.synthetic_token,
                    VALID_COLLATERAL_TOKENS[0],
                    None,
                );

                ord.collateral_amount = new_collateral_amount;
                ord.expiration_timestamp = new_expiration;
            }
        }
    } else {
        match &mut wrapper.order {
            Order::Spot(ord) => {
                let base_asset = ord.token_spent;
                let quote_asset = ord.token_received;

                let new_received_amount =
                    get_quote_qty(ord.amount_spent, price, base_asset, quote_asset, None);

                ord.amount_received = new_received_amount;
                ord.expiration_timestamp = new_expiration;
            }
            Order::Perp(ord) => {
                let new_collateral_amount = get_quote_qty(
                    ord.synthetic_amount,
                    price,
                    ord.synthetic_token,
                    VALID_COLLATERAL_TOKENS[0],
                    None,
                );

                ord.collateral_amount = new_collateral_amount;
                ord.expiration_timestamp = new_expiration;
            }
        }
    }

    wrapper.signature = signature;
}
