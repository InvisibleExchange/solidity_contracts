use invisible_backend::perpetual::{
    OrderSide, COLLATERAL_TOKEN_DECIMALS, DECIMALS_PER_ASSET, MIN_PARTIAL_LIQUIDATION_SIZE,
    PRICE_DECIMALS_PER_ASSET,
};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    //

    let entry_price = 1800_000_000;
    let margin = 100_000_000;
    let position_size = 1_000_000_000;
    let order_side = &OrderSide::Long;
    let synthetic_token = 54321;

    let p = _get_liquidation_price(
        entry_price,
        margin,
        position_size,
        order_side,
        synthetic_token,
        true,
    );

    println!("liquidation price: {}", p);

    Ok(())
}

fn _get_liquidation_price(
    entry_price: u64,
    margin: u64,
    position_size: u64,
    order_side: &OrderSide,
    synthetic_token: u64,
    is_partial_liquidation: bool,
) -> u64 {
    // maintenance margin
    let mm_fraction = if is_partial_liquidation
        && position_size > MIN_PARTIAL_LIQUIDATION_SIZE[synthetic_token.to_string().as_str()]
    {
        4 //%
    } else {
        3 //%
    };

    let synthetic_decimals: &u8 = DECIMALS_PER_ASSET
        .get(synthetic_token.to_string().as_str())
        .unwrap();

    let synthetic_price_decimals: &u8 = PRICE_DECIMALS_PER_ASSET
        .get(synthetic_token.to_string().as_str())
        .unwrap();

    let dec_conversion1: i8 = *synthetic_decimals as i8 + *synthetic_price_decimals as i8
        - COLLATERAL_TOKEN_DECIMALS as i8;
    let multiplier1 = 10_u128.pow(dec_conversion1 as u32);

    // & price_delta = (margin - mm_fraction * entry_price * size) / ((1 -/+ mm_fraction)*size) ; - for long, + for short

    let d1 = margin as u128 * multiplier1 as u128;
    let d2 = mm_fraction as u128 * entry_price as u128 * position_size as u128 / 100;

    if *order_side == OrderSide::Long {
        if position_size == 0 {
            return 0;
        }

        let price_delta =
            ((d1 - d2) * 100) / ((100_u128 - mm_fraction as u128) * position_size as u128);

        let liquidation_price = entry_price.checked_sub(price_delta as u64);

        return liquidation_price.unwrap_or(0);
    } else {
        if position_size == 0 {
            return 0;
        }

        let price_delta =
            ((d1 - d2) * 100) / ((100_u128 + mm_fraction as u128) * position_size as u128);

        let liquidation_price = entry_price + price_delta as u64;

        return liquidation_price;
    }
}
