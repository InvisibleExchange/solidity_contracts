use num_traits::Pow;

use crate::perpetual::{DECIMALS_PER_ASSET, PRICE_DECIMALS_PER_ASSET};

use self::domain::OrderSide;

pub mod domain;
pub mod order_queues;
pub mod orderbook;
pub mod orders;
pub mod sequence;
pub mod validation;

fn get_quote_qty(
    qty: u64,
    price: f64,
    base_asset: u64,
    quote_asset: u64,
    side: Option<OrderSide>,
) -> u64 {
    let base_decimals = DECIMALS_PER_ASSET[base_asset.to_string().as_str()];
    let quote_decimals = DECIMALS_PER_ASSET[quote_asset.to_string().as_str()];
    let price_decimals = PRICE_DECIMALS_PER_ASSET[base_asset.to_string().as_str()];

    let price = (price * 10_f64.pow(price_decimals)) as u64;

    let mutliplier = 10_u64.pow((base_decimals + price_decimals - quote_decimals) as u32);

    // round the number up to ~1c precision
    let unrounded_quote_qty = qty as u128 * price as u128 / mutliplier as u128;

    if side.is_none() {
        return unrounded_quote_qty as u64;
    }

    if side.unwrap() == OrderSide::Bid {
        // round up for market bid orders

        return ((unrounded_quote_qty / 10000) * 10000 + 10000) as u64;
    } else {
        // round down for market ask orders
        return ((unrounded_quote_qty / 10000) * 10000) as u64;
    }
}

fn get_qty_from_quote(quote_qty: u64, price: f64, base_asset: u64, quote_asset: u64) -> u64 {
    let base_decimals = DECIMALS_PER_ASSET[base_asset.to_string().as_str()];
    let quote_decimals = DECIMALS_PER_ASSET[quote_asset.to_string().as_str()];
    let price_decimals = PRICE_DECIMALS_PER_ASSET[base_asset.to_string().as_str()];

    let price = (price * 10_f64.pow(price_decimals)) as u128;

    let mutliplier = 10_u128.pow((base_decimals + price_decimals - quote_decimals) as u32);

    return (quote_qty as u128 * mutliplier / price) as u64;
}
