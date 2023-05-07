use std::fmt::Debug;
use std::time::SystemTime;

use crate::utils::crypto_utils::Signature;

use super::domain::{Order, OrderSide, OrderWrapper};

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
    },
    CancelOrder {
        id: u64,
        side: OrderSide,
        user_id: u64,
        //ts: SystemTime,
    },
}

// pub fn new_market_order_request(
//     side: OrderSide,
//     order: Order,
//     signature: Signature,
//     ts: SystemTime,
//     user_id: u64,
// ) -> OrderRequest {
//     let (order_asset, price_asset) = order.get_order_and_price_assets(side);

//     let qty: u64 = order.get_qty(side);
//     let order = OrderWrapper {
//         order,
//         signature,
//         qty_left: qty,
//         order_id: 0,
//         order_side: side,
//         user_id,
//     };

//     OrderRequest::NewMarketOrder {
//         order_asset,
//         price_asset,
//         side,
//         qty,
//         order,
//         ts,
//     }
// }

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

    let price: f64 = order.get_price(side, None);

    let qty: u64 = order.get_qty(side, price);

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
) -> OrderRequest {
    OrderRequest::AmendOrder {
        id: order_id,
        side,
        new_price,
        new_expiration,
        signature,
        user_id,
    }
}
