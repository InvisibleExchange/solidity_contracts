use crate::perpetual::DECIMALS_PER_ASSET;

use self::domain::OrderSide;

pub mod domain;
pub mod order_queues;
pub mod orderbook;
pub mod orders;
pub mod sequence;
pub mod validation;

pub fn get_quote_qty(
    qty: u64,
    price: f64,
    base_asset: u64,
    quote_asset: u64,
    _side: Option<OrderSide>,
) -> u64 {
    let base_decimals = DECIMALS_PER_ASSET[base_asset.to_string().as_str()];
    let quote_decimals = DECIMALS_PER_ASSET[quote_asset.to_string().as_str()];

    let qty = qty as f64 / 10_f64.powi(base_decimals as i32);

    // round the number up to ~1c precision
    let quote_qty = qty * price;

    // let quote_qty = (quote_qty * 100.0).floor() / 100.0;

    return (quote_qty * 10_f64.powi(quote_decimals as i32)) as u64;

    // if side.is_none() {
    //     return unrounded_quote_qty as u64;
    // }

    // if side.unwrap() == OrderSide::Bid {
    //     // round up for market bid orders

    //     return ((unrounded_quote_qty / 10000) * 10000 + 10000) as u64;
    // } else {
    //     // round down for market ask orders
    //     return ((unrounded_quote_qty / 10000) * 10000) as u64;
    // }
}

pub fn get_qty_from_quote(quote_qty: u64, price: f64, base_asset: u64, quote_asset: u64) -> u64 {
    let base_decimals = DECIMALS_PER_ASSET[base_asset.to_string().as_str()];
    let quote_decimals = DECIMALS_PER_ASSET[quote_asset.to_string().as_str()];

    let quote_qty = quote_qty as f64 / 10_f64.powi(quote_decimals as i32);

    let qty = quote_qty / price;

    // let qty = (qty * 100.0).floor() / 100.0;

    return (qty * 10_f64.powi(base_decimals as i32)) as u64;
}
