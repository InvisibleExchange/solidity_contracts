use std::{str::FromStr, time::Instant};

use num_bigint::BigUint;
use starknet_core::{crypto::pedersen_hash, types::FieldElement};

pub fn main() {
    let a = BigUint::from_str("123172847185412547818724871373286458723589265352349278352461274")
        .unwrap();
    let now = Instant::now();
    let a_str = a.to_bytes_be();
    println!("Time elapsed:  {:?}", now.elapsed());

    let f1 = FieldElement::from_dec_str(&a.to_string()).unwrap();

    let now = Instant::now();
    let f_str: String = f1.inner.0.to_string();
    println!("f_str: {:?}", f_str);
    println!("Time elapsed:  {:?}", now.elapsed());

    // let now4 = Instant::now();
    // for i in 0..100000 {
    //     let f1 = FieldElement::from_dec_str(&a.to_string()).unwrap();
    // }
    // println!("Time elapsed4:  {:?}", now4.elapsed());

    // let f2 = FieldElement::from_str(&"456".to_string()).unwrap();

    // let res = pedersen_hash(&f1, &f2);
}
