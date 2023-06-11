use std::{collections::HashMap, path::Path, str::FromStr};

use invisible_backend::{
    transaction_batch::tx_batch_helpers::split_hashmap,
    trees::{Tree, TreeStateType},
    utils::{
        crypto_utils::{verify, Signature},
        firestore::{read_file_from_storage, upload_file_to_storage},
    },
};

use num_bigint::BigUint;
use num_traits::FromPrimitive;
use reqwest::header::PUBLIC_KEY_PINS;
use serde_json::{json, Map};
mod scripts;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let file_name = "test.json";

    // let inp = [
    //     "1594448415587643418616815765143960997352150768813634459965837461368791318237",
    //     "2906760248968904635814562164066531430587131666418302748707225232243020334737",
    //     "1584973261628710075069514800485778481865158355986112239425466311312550461781",
    //     "542861493083138354867756884239348564241586569166992711200164398616931191470",
    //     "1106467810081430397361500078936325835169710586396733341854541137686480274359",
    //     "2544859323889680480346558046123373755088554104609673986113805654026651748110",
    //     "3475145494590000707065761774792012222589733246536088151151592704845664093421",
    //     "3442994763591498320021128881449341011051790606622580733695894872336051146345",
    //     "1474590873194121771497559520911555546488839879463980038730642937517906118907",
    //     "0",
    //     "0",
    //     "2770300307984240278047587542494900247449601573317770110578926635090203601708",
    //     "3018495424615721295946320401190108381972579495270319900346628704278828475240",
    //     "1041621955374120737097181498628072935608716592294743750851834676457613211775",
    // ];

    // let inp = inp
    //     .iter()
    //     .map(|x| BigUint::from_str(x).unwrap())
    //     .collect::<Vec<BigUint>>();

    // let mut updated_note_hashes = HashMap::new();
    // for (i, num) in inp.into_iter().enumerate() {
    //     updated_note_hashes.insert(i as u64, num);
    // }

    // let mut preimage = Map::new();

    // let mut tree = Tree::new(32, 0);
    // tree.batch_transition_updates(&updated_note_hashes, &mut preimage);

    // let path = Path::new("./src/test.json");
    // std::fs::write(path, serde_json::to_string(&preimage).unwrap()).unwrap();

    // println!("tree root: {:?}", tree.root);

    // Signature (1819493212820948508787831207611602747188392968195012412851549448377641368319, 260092933020772422848914131560193898423071337866243647383395753532756437289),
    // public key 3603523822862985385489814729276731479624340734252720259242862569397485528146, and the message hash 1353275388731212278516215269414311739131254826970923102657737223034604933314.

    // =================================================================================
    // let mut updated_roots = HashMap::new();
    // updated_roots.insert(0, tree.root);

    // let mut tree2 = Tree::new(16, 16);

    // tree2.batch_transition_updates(&updated_roots, &mut preimage);

    // // println!("preimage: {:?}", preimage);

    // println!("tree2 root: {:?}", tree2.root);

    Ok(())
}

