use invisible_backend::utils::firestore::{read_file_from_storage, upload_file_to_storage};

use serde_json::{json, Map};
mod scripts;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let file_name = "test.json";

    let mut json_map = Map::new();
    json_map.insert(
        "hello".to_string(),
        json!({
            "hello": "world",
            "foo": "bar"
        }),
    );
    upload_file_to_storage(file_name.to_string(), json_map)
        .await
        .unwrap();

    read_file_from_storage(file_name.to_string()).await?;

    Ok(())
}

// #[tokio::main]
// async fn main() -> Result<(), Box<dyn std::error::Error>> {
//     //

//     let d = 32;
//     let s = 16;

//     // let mut batch_init_tree = Tree::new(d);

//     let mut preimage = Map::new();
//     let mut update_proofs = HashMap::new();
//     for i in (0..2_u64.pow(21) - 1).step_by(10000) {
//         update_proofs.insert(i, BigUint::from_u64(i).unwrap());
//     }

//     let now = Instant::now();

//     let partitions = split_hashmap(update_proofs, 2_u32.pow(s) as usize);

//     let mut new_roots: HashMap<u64, BigUint> = HashMap::new();
//     for (idx, partition) in partitions {
//         let mut tree_i = Tree::new(s, 0);

//         tree_i.batch_transition_updates(&partition, &mut preimage);

//         new_roots.insert(idx as u64, tree_i.root);
//     }

//     let mut final_tree = Tree::new(d - s, s);
//     final_tree.batch_transition_updates(&new_roots, &mut preimage);

//     let new_root = final_tree.root;
//     let elapsed = now.elapsed();
//     println!(
//         "Time elapsed in batch_transition_updates() is: {:?} {:?}",
//         elapsed, new_root
//     );

//     // ====================================================================================================

//     let mut preimage = Map::new();
//     let mut update_proofs = HashMap::new();
//     for i in (0..2_u64.pow(21) - 1).step_by(10000) {
//         update_proofs.insert(i, BigUint::from_u64(i).unwrap());
//     }

//     let mut final_tree = Tree::new(d, 0);
//     final_tree.batch_transition_updates(&update_proofs, &mut preimage);

//     let new_root = final_tree.root;

//     let elapsed = now.elapsed();
//     println!(
//         "Time elapsed in batch_transition_updates() is: {:?} {:?}",
//         elapsed, new_root
//     );

//     Ok(())
// }
