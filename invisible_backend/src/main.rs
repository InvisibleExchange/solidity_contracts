use std::str::FromStr;

use invisible_backend::utils::crypto_utils::{pedersen, pedersen_on_vec};
use num_bigint::BigUint;
use num_traits::{One, Zero};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let testCases = [
        (BigUint::zero(), BigUint::zero()),
        (
            BigUint::from_str("1").unwrap(),
            BigUint::from_str("2").unwrap(),
        ),
        (
            BigUint::from_str(
                "1740729136829561885683894917751815192814966525555656371386868611731128807883",
            )
            .unwrap(),
            BigUint::from_str(
                "919869093895560023824014392670608914007817594969197822578496829435657368346",
            )
            .unwrap(),
        ),
        (
            BigUint::from_str(
                "2514830971251288745316508723959465399194546626755475650431255835704887319877",
            )
            .unwrap(),
            BigUint::from_str(
                "3405079826265633459083097571806844574925613129801245865843963067353416465931",
            )
            .unwrap(),
        ),
        (
            BigUint::from_str(
                "1740729136829561885683894917751815192814966525555656371386868611731128807883",
            )
            .unwrap(),
            BigUint::from_str(
                "3405079826265633459083097571806844574925613129801245865843963067353416465931",
            )
            .unwrap(),
        ),
        (
            BigUint::from_str(
                "1382171651951541052082654537810074813456022260470662576358627909045455537762",
            )
            .unwrap(),
            BigUint::from_str(
                "1382171651951541052082654537810074813456022260470662576358627909045455537762",
            )
            .unwrap(),
        ),
        (
            BigUint::from_str(
                "2989412688956151835214942290957251459324068990196122440338678175328331631005",
            )
            .unwrap(),
            BigUint::from_str(
                "302882861881474297194517227166123224282434798024530844043336825523175500303",
            )
            .unwrap(),
        ),
        (
            BigUint::from_str(
                "2989412688956152873067793738364302026827296306684834408992777575367789250973",
            )
            .unwrap(),
            BigUint::from_str(
                "302882861881474297194517227166123224384544373449910391112128153707888323087",
            )
            .unwrap(),
        ),
    ];

    for (x, y) in testCases.iter() {
        let res = pedersen(&x, &y);

        println!("{:#?}", res);
    }

    Ok(())
}
