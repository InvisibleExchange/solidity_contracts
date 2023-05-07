use num_bigint::BigUint;
use num_traits::Zero;

use super::Tree;

pub struct SuperficialTree {
    pub leaf_nodes: Vec<BigUint>,
    pub depth: u32,
    pub count: u64,
    pub zero_idxs: Vec<u64>,
}

impl SuperficialTree {
    pub fn new(depth: u32) -> Self {
        Self {
            leaf_nodes: vec![],
            depth,
            count: 0,
            zero_idxs: vec![],
        }
    }

    pub fn update_leaf_node(&mut self, leaf_hash: &BigUint, idx: u64) {
        assert!(idx < 2_u64.pow(self.depth), "idx is greater than tree size");

        if leaf_hash.ne(&BigUint::zero()) {
            if idx > self.count {
                for i in self.count..idx {
                    self.zero_idxs.push(i);
                }
                self.count = idx;
            } else if idx == self.count {
                self.count += 1;
            } else {
                self.zero_idxs = self
                    .zero_idxs
                    .iter()
                    .filter(|&x| *x != idx)
                    .map(|&x| x)
                    .collect::<Vec<u64>>();
            }
        } else {
            self.zero_idxs.push(idx);
        }

        if self.leaf_nodes.len() > idx as usize {
            self.leaf_nodes[idx as usize] = leaf_hash.clone();
        } else {
            let len_diff = idx as usize - self.leaf_nodes.len();

            for _ in 0..len_diff {
                self.leaf_nodes.push(BigUint::zero());
            }

            self.leaf_nodes.push(leaf_hash.clone())
        }
    }

    // -----------------------------------------------------------------
    // * GETTERS * //
    pub fn first_zero_idx(&mut self) -> u64 {
        if self.zero_idxs.len() == 0 {
            let idx = self.count;
            self.count += 1;

            return idx;
        } else {
            return self.zero_idxs.pop().unwrap();
        }
    }

    pub fn get_leaf_by_index(&self, index: u64) -> BigUint {
        return self.nth_leaf_node(index);
    }

    // -----------------------------------------------------------------
    // Helpers

    fn nth_leaf_node(&self, n: u64) -> BigUint {
        assert!(n < 2_u64.pow(self.depth), "n is bigger than tree size");

        if self.leaf_nodes.get(n as usize).is_some() {
            return self.leaf_nodes[n as usize].clone();
        } else {
            return BigUint::zero();
        }
    }

    // -----------------------------------------------------------------

    pub fn from_tree(tree: Tree) -> Self {
        let count = tree.leaf_nodes.len() as u64;

        let mut zero_idxs = vec![];
        for (idx, leaf) in tree.leaf_nodes.iter().enumerate() {
            if leaf.eq(&BigUint::zero()) {
                zero_idxs.push(idx as u64);
            }
        }

        let superficial_tree = SuperficialTree {
            leaf_nodes: tree.leaf_nodes,
            depth: tree.depth,
            count,
            zero_idxs,
        };

        return superficial_tree;
    }
}
