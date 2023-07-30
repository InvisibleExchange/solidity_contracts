// TODO: Check that the tab has enough funds to cover the order
// Check that the tab hash is valid
// Check that the tokens are valid
// Check that the tab hash exists in the state

use std::{collections::HashMap, sync::Arc, time::SystemTime};

use error_stack::Result;
use num_bigint::BigUint;
use parking_lot::Mutex;

use crate::{
    order_tab::OrderTab,
    perpetual::DUST_AMOUNT_PER_ASSET,
    transactions::limit_order::LimitOrder,
    trees::superficial_tree::SuperficialTree,
    utils::errors::{send_swap_error, SwapThreadExecutionError},
};

// * CHECK ORDER VALIDITY FUNCTION * --------------------------------------------
pub fn check_tab_order_validity(
    order_tabs_state_tree: &Arc<Mutex<SuperficialTree>>,
    order: &LimitOrder,
    spent_amount: u64,
) -> Result<(), SwapThreadExecutionError> {
    // ? Check that the order tab is valid --------------------------------------------
    if order.order_tab.is_none() {
        return Err(send_swap_error(
            "order_tab is not defined".to_string(),
            Some(order.order_id),
            None,
        ));
    }

    let order_tab = order.order_tab.as_ref().unwrap();
    let order_tab = order_tab.lock();

    // ? Check that the tokens are valid --------------------------------------------
    if (order_tab.tab_header.base_token != order.token_spent
        || order_tab.tab_header.quote_token != order.token_received)
        && (order_tab.tab_header.base_token != order.token_received
            || order_tab.tab_header.quote_token != order.token_spent)
    {
        return Err(send_swap_error(
            "tokens swapped are invalid".to_string(),
            Some(order.order_id),
            None,
        ));
    }

    // ? Check that the tab has not expired  --------------------------------------------
    let now = SystemTime::now();
    let seconds_since_epoch = now
        .duration_since(SystemTime::UNIX_EPOCH)
        .expect("Time went backwards")
        .as_secs();

    if order_tab.tab_header.expiration_timestamp < seconds_since_epoch {
        return Err(send_swap_error(
            "order_tab has expired".to_string(),
            Some(order.order_id),
            None,
        ));
    }

    let is_buy = order_tab.tab_header.base_token == order.token_received;

    // ? Check that the order tab has sufficiennt balance to cover the order ---------------
    if is_buy {
        if spent_amount > order_tab.quote_amount {
            return Err(send_swap_error(
                "order_tab does not have enough funds for this the order".to_string(),
                Some(order.order_id),
                None,
            ));
        }
    } else {
        if spent_amount > order_tab.base_amount {
            return Err(send_swap_error(
                "order_tab does not have enough funds for this the order".to_string(),
                Some(order.order_id),
                None,
            ));
        }
    }

    // ? Check that the order is not overspending --------------------------------------------
    if spent_amount > order.amount_spent + DUST_AMOUNT_PER_ASSET[&order.token_spent.to_string()] {
        return Err(send_swap_error(
            "order is overspending".to_string(),
            Some(order.order_id),
            None,
        ));
    }

    // ? Check that the order tab hash exists in the state --------------------------------------------
    let tabs_state_tree = order_tabs_state_tree.lock();
    let leaf_hash = tabs_state_tree.get_leaf_by_index(order_tab.tab_idx as u64);

    if leaf_hash != order_tab.hash {
        println!("leaves: {:?}", tabs_state_tree.leaf_nodes);
        println!(
            "order_tab.hash: {:?} - {:?}",
            order_tab.hash, order_tab.tab_idx
        );

        return Err(send_swap_error(
            "order_tab hash does not exist in the state".to_string(),
            Some(order.order_id),
            None,
        ));
    }

    drop(order_tab);

    Ok(())
}
//

//

// TODO: Subtract the spent amount from the tab balance and add the received amount to the tab balance
pub fn execute_tab_order_modifications(
    prev_filled_amount: u64,
    order: &LimitOrder,
    mut order_tab: OrderTab,
    spent_amount_x: u64,
    spent_amount_y: u64,
    fee_taken_x: u64,
) -> (bool, OrderTab, u64) {
    let is_buy = order.token_received == order_tab.tab_header.base_token;

    if is_buy {
        order_tab.quote_amount -= spent_amount_x;
        order_tab.base_amount += spent_amount_y - fee_taken_x;
    } else {
        order_tab.base_amount -= spent_amount_x;
        order_tab.quote_amount += spent_amount_y - fee_taken_x;
    }

    order_tab.update_hash();

    let new_amount_filled = prev_filled_amount + spent_amount_y;
    let is_partially_filled = new_amount_filled
        + DUST_AMOUNT_PER_ASSET[&order.token_spent.to_string()]
        < order.amount_received;

    return (is_partially_filled, order_tab, new_amount_filled);
}

//

//

// ? update the state with the new order tab hash
pub fn update_state_after_tab_order(
    tabs_state_tree: &Arc<Mutex<SuperficialTree>>,
    updated_tab_hashes_m: &Arc<Mutex<HashMap<u32, BigUint>>>,
    order: &LimitOrder,
    updated_order_tab: &OrderTab,
) -> Result<(), SwapThreadExecutionError> {
    let mut tabs_state_tree_ = tabs_state_tree.lock();
    let mut updated_tab_hashes = updated_tab_hashes_m.lock();

    let prev_tab_hash = order.order_tab.as_ref().unwrap().lock().hash.clone();

    // ? Check that the order tab hash exists in the state --------------------------------------------
    let leaf_hash = tabs_state_tree_.get_leaf_by_index(updated_order_tab.tab_idx as u64);

    if leaf_hash != prev_tab_hash {
        return Err(send_swap_error(
            "order_tab hash does not exist in the state".to_string(),
            Some(order.order_id),
            None,
        ));
    }

    tabs_state_tree_.update_leaf_node(&updated_order_tab.hash, updated_order_tab.tab_idx as u64);
    updated_tab_hashes.insert(updated_order_tab.tab_idx, updated_order_tab.hash.clone());

    drop(tabs_state_tree_);
    drop(updated_tab_hashes);

    Ok(())
}
