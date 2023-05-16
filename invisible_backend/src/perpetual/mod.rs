use phf::phf_map;
use serde::{Deserialize, Serialize};

pub mod liquidations;
pub mod order_execution;
pub mod perp_helpers;
pub mod perp_order;
pub mod perp_position;
pub mod perp_swap;

#[derive(PartialEq, Debug, Clone, Deserialize, Serialize)]
pub enum OrderSide {
    Long,
    Short,
}
#[derive(PartialEq, Debug, Clone, Deserialize, Serialize)]
pub enum OrderType {
    Limit,
    Market,
}
#[derive(PartialEq, Debug, Clone, Deserialize, Serialize)]
pub enum PositionEffectType {
    Open,
    Close,
    Modify,
}

pub static LEVERAGE_BOUNDS_PER_ASSET: phf::Map<&'static str, [f32; 2]> = phf_map! {
"12345" => [2.5, 50.0], // BTC
"54321" => [25.0, 500.0], // ETH
};

// BTC - 12345
// ETH - 54321
// USDC - 55555
pub static TOKENS: [u64; 2] = [12345, 54321];
pub static VALID_COLLATERAL_TOKENS: [u64; 1] = [55555];

pub static DECIMALS_PER_ASSET: phf::Map<&'static str, u8> = phf_map! {
"12345" => 9, // BTC
"54321" => 9, // ETH
"55555" => 6, // USDC
};

pub static PRICE_DECIMALS_PER_ASSET: phf::Map<&'static str, u8> = phf_map! {
"12345" => 6, // BTC
"54321" => 6, // ETH
};

pub static IMPACT_NOTIONAL_PER_ASSET: phf::Map<&'static str, u64> = phf_map! {
"12345" => 200_000_000, // BTC
"54321" => 2_000_000_000, // ETH
};

// Minimum amount that is worth acknowledging
pub static DUST_AMOUNT_PER_ASSET: phf::Map<&'static str, u64> = phf_map! {
"12345" => 2500, // BTC ~ 5c
"54321" => 25000, // ETH ~ 5c
"55555" => 50000, // USDC ~ 5c
};

// Only allow partial liquidations on positions that are at least this size
pub static MIN_PARTIAL_LIQUIDATION_SIZE: phf::Map<&'static str, u64> = phf_map! {
"12345" => 50_000_000, // BTC
"54321" => 500_000_000, // ETH
};

pub const LEVERAGE_DECIMALS: u8 = 6; // 6 decimals for leverage
pub const COLLATERAL_TOKEN_DECIMALS: u8 = 6; // 6 decimals for USDC/USDT...

// mpact Notional Amount = 500 USDC / Initial Margin Fraction

// notional_size0 => 2 BTC
// 3 BTC > 20X leverage > init_margin = 5%
// 6 BTC > 10X leverage > init_margin = 10%
// 9 BTC > 5X leverage > init_margin = 20%
// 12 BTC > 4X leverage > init_margin = 25%
// 16 BTC > 3X leverage > init_margin = 33.3%
// 20 BTC > 2X leverage > init_margin = 50%
// 25 BTC > 1.5X leverage > init_margin = 66.6%

// 10 BTC min init_margin = 3BTC*5% + 6BTC*10% + 1BTC*20% = 0.95BTC
// max leverage = 10BTC/0.95BTC = 10.5X

pub fn calculate_funding() {
    // link to imapct notional values = https://docs.google.com/document/d/1o7Eg5Shvfjz6oTyQPrhshr3aSnm6CbxFmt9xu6N0DtM/edit

    // Bybit:
    // Premium Index (P) = [Max(0, Impact Bid Price* − Mark Price) − Max(0, Mark Price − Impact Ask Price*)]/Index Price
    // + [(Funding Rate of Current Interval × Time Until Next Interval)/Funding Interval]

    // Basis (Funding) = 8 hour TWAP of (Spot Market Price - Future Market Price)

    // FTX:
    // position size * TWAP of ((future mark price - index) / index) / 24

    //& Maybe combine both ways for something like:
    //& Funding = (position size * TWAP of [Max(0, Impact Bid Price* − Index Price) − Max(0, Index Price − Impact Ask Price*)]/Index Price / 3
}

// * Price functions * // ====================================================================
pub fn get_price(synthetic_token: u64, collateral_amount: u64, synthetic_amount: u64) -> u64 {
    let synthetic_decimals: &u8 = DECIMALS_PER_ASSET
        .get(synthetic_token.to_string().as_str())
        .unwrap();

    let synthetic_price_decimals: &u8 = PRICE_DECIMALS_PER_ASSET
        .get(synthetic_token.to_string().as_str())
        .unwrap();

    let decimal_conversion: i8 = *synthetic_decimals as i8 + *synthetic_price_decimals as i8
        - COLLATERAL_TOKEN_DECIMALS as i8;
    let multiplier = 10_u128.pow(decimal_conversion as u32);

    let price = ((collateral_amount as u128 * multiplier) / synthetic_amount as u128) as u64;

    return price;
}

pub fn get_cross_price(
    base_token: u64,
    quote_token: u64,
    base_amount: u64,
    quote_amount: u64,
    round: Option<bool>,
) -> f64 {
    // Price of two tokens in terms of each other (possible to get ETH/BTC price)

    if VALID_COLLATERAL_TOKENS.contains(&quote_token) {
        let base_price_decimals: &u8 = PRICE_DECIMALS_PER_ASSET
            .get(base_token.to_string().as_str())
            .unwrap();
        let price = get_price(base_token, quote_amount, base_amount);

        let price = price as f64 / 10_f64.powi(*base_price_decimals as i32);

        if round.is_none() {
            return price;
        }

        // ? If tound == true, round up else round down
        if round.unwrap() {
            // round price to 5 decimals
            return (price * 100000.0).ceil() / 100000.0;
        } else {
            // round price to 5 decimals
            return (price * 100000.0).floor() / 100000.0;
        }
    } else {
        panic!("quote token is not a valid collateral token");
    }

    // TODO: What is the quote token is not a valid collateral token?

    // let base_decimals: &u8 = DECIMALS_PER_ASSET
    //     .get(base_token.to_string().as_str())
    //     .unwrap();
    // let base_price_decimals: &u8 = PRICE_DECIMALS_PER_ASSET
    //     .get(base_token.to_string().as_str())
    //     .unwrap();

    // let quote_decimals: &u8 = DECIMALS_PER_ASSET
    //     .get(quote_token.to_string().as_str())
    //     .unwrap();

    // let decimal_conversion = *base_decimals + *base_price_decimals - quote_decimals;
    // let multiplier = 10_u128.pow(decimal_conversion as u32);

    // let price = (quote_amount as u128 * multiplier) as u64 / base_amount;

    // return price as f64 / 10_f64.powi(*base_price_decimals as i32);
}

pub fn calculate_quote_amount(
    base_token: u64,
    quote_token: u64,
    base_amount: u64,
    base_price: f64,
) -> u64 {
    let base_decimals: &u8 = DECIMALS_PER_ASSET
        .get(base_token.to_string().as_str())
        .unwrap();
    let base_price_decimals: &u8 = PRICE_DECIMALS_PER_ASSET
        .get(base_token.to_string().as_str())
        .unwrap();

    if !VALID_COLLATERAL_TOKENS.contains(&quote_token) {
        panic!("quote token is not a valid collateral token");
    }

    let base_price = base_price * 10_f64.powi(*base_price_decimals as i32);

    let decimal_conversion = *base_decimals + *base_price_decimals - 6;
    let multiplier = 10_u128.pow(decimal_conversion as u32);

    let quote_amount = (base_amount as u128 * base_price as u128) / multiplier;

    return quote_amount as u64;
}

pub fn scale_up_price(price: f64, token: u64) -> u64 {
    let price_decimals: &u8 = PRICE_DECIMALS_PER_ASSET
        .get(token.to_string().as_str())
        .unwrap();

    let price = price * 10_f64.powi(*price_decimals as i32);

    return price as u64;
}

pub fn scale_down_price(price: u64, token: u64) -> f64 {
    let price_decimals: &u8 = PRICE_DECIMALS_PER_ASSET
        .get(token.to_string().as_str())
        .unwrap();

    let price = price as f64 / 10_f64.powi(*price_decimals as i32);

    return price;
}
