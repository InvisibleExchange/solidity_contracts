pub mod matching_engine;
pub mod order_tab;
pub mod perpetual;
pub mod server;
pub mod smart_contract_mms;
pub mod transaction_batch;
pub mod transactions;
pub mod trees;
pub mod utils;

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::trees::build_tree;
    use super::trees::Tree;
    use num_bigint::BigUint;
    use num_traits::FromPrimitive;

    #[test]
    fn test1() -> Result<(), Box<dyn std::error::Error>> {
        let mut updates_hashes: HashMap<u64, BigUint> = HashMap::new();

        updates_hashes.insert(0, BigUint::from_u16(1).unwrap());
        updates_hashes.insert(1, BigUint::from_u16(2).unwrap());
        updates_hashes.insert(3, BigUint::from_u16(4).unwrap());
        updates_hashes.insert(4, BigUint::from_u16(5).unwrap());

        let mut init_tree = Tree::new(16, 0);

        let mut preimage = serde_json::Map::new();
        init_tree.batch_transition_updates(&updates_hashes, &mut preimage);

        println!("{:?}", init_tree.root);

        let leaves = vec![1, 2, 0, 4, 5];
        let leaves = leaves
            .iter()
            .map(|x| BigUint::from_u16(*x).unwrap())
            .collect::<Vec<BigUint>>();

        let state_root = build_tree(16, &leaves, 0);
        println!("state root: {:?}", state_root);
        Ok(())
    }
}
