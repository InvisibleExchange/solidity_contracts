use invisible_backend::utils::{cairo_output::parse_cairo_output, crypto_utils::pedersen};
use num_bigint::BigUint;
use num_traits::{One, Zero};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let output_str = "";

    // let output = output_str.split_whitespace().collect::<Vec<&str>>();

    // let program_output = parse_cairo_output(output);

    // println!("{:#?}", program_output);

    let x = pedersen(&BigUint::one(), &BigUint::zero());
    let x = x - 1_u32;

    println!("{:#?}", x);

    let x_half = x / 2_u32;

    println!("{:#?}", x_half);

    Ok(())
}
