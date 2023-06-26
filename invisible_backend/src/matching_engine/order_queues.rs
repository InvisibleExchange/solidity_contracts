use std::cmp::Ordering;
use std::collections::{BinaryHeap, HashMap};
use std::sync::Arc;
use std::time::{self, SystemTime};

use parking_lot::Mutex;

use crate::perpetual::perp_position::PerpPosition;
use crate::utils::crypto_utils::Signature;

use super::domain::{Order, OrderSide, OrderWrapper, SharedOrderInner};
use super::orders::amend_inner;

#[derive(Clone)]
struct OrderIndex {
    id: u64,
    price: f64,
    timestamp: time::SystemTime,
    order_side: OrderSide,
    order: OrderWrapper,
}

// Arrange at first by price and after that by time
impl Ord for OrderIndex {
    fn cmp(&self, other: &Self) -> Ordering {
        if self.price < other.price {
            match self.order_side {
                OrderSide::Bid => Ordering::Less,
                OrderSide::Ask => Ordering::Greater,
            }
        } else if self.price > other.price {
            match self.order_side {
                OrderSide::Bid => Ordering::Greater,
                OrderSide::Ask => Ordering::Less,
            }
        } else {
            // FIFO
            other.timestamp.cmp(&self.timestamp)
        }
    }
}

impl PartialOrd for OrderIndex {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl PartialEq for OrderIndex {
    fn eq(&self, other: &Self) -> bool {
        if self.price > other.price || self.price < other.price {
            false
        } else {
            self.timestamp == other.timestamp
        }
    }
}

impl Eq for OrderIndex {}

/// Public methods
pub struct OrderQueue {
    // use Option in order to replace heap in mutable borrow
    idx_queue: Option<BinaryHeap<OrderIndex>>,
    // orders: HashMap<u64, OrderWrapper>,
    // op_counter: u64,
    // max_stalled: u64,
    queue_side: OrderSide,
    pending_orders: HashMap<u64, Vec<OrderWrapper>>,
}

impl OrderQueue {
    /// Create new order queue
    ///
    /// Queue is universal and could be used for both asks and bids
    pub fn new(side: OrderSide, _max_stalled: u64, capacity: usize) -> Self {
        OrderQueue {
            idx_queue: Some(BinaryHeap::with_capacity(capacity)),
            // orders: HashMap::with_capacity(capacity),
            // op_counter: 0,
            // max_stalled,
            queue_side: side,
            pending_orders: HashMap::with_capacity(capacity),
        }
    }

    pub fn peek(&self) -> Option<&OrderWrapper> {
        // get best order ID
        let order_idx = self.idx_queue.as_ref()?.peek()?;

        Some(&order_idx.order)
    }

    pub fn pop(&mut self) -> Option<(OrderWrapper, SystemTime)> {
        // remove order index from queue in any case
        let index_item = self.idx_queue.as_mut()?.pop()?;

        Some((index_item.order, index_item.timestamp))
    }

    pub fn pop_with_failed_ids(
        &mut self,
        failed_order_ids: &Vec<u64>,
    ) -> Vec<(OrderWrapper, SystemTime)> {
        let mut pending_orders: Vec<(OrderWrapper, SystemTime)> = vec![];
        let mut other_orders = vec![];

        // loop over all the orders in the opposite_queue and store the orders with failed_order_ids in pending_orders
        // and the rest in other_orders
        loop {
            if let Some((order, ts)) = self.pop() {
                let ord_id = order.order.lock().order_id;

                if failed_order_ids.contains(&ord_id) {
                    pending_orders.push((order, ts));
                } else {
                    other_orders.push((order, ts));
                }
            } else {
                break;
            }
        }

        for (order, ts) in other_orders.into_iter().rev() {
            let ord_id = order.order.lock().order_id;

            self.insert(ord_id, order.price, ts, order.clone());
        }

        pending_orders
    }

    // Add new limit order to the queue
    pub fn insert(
        &mut self,
        id: u64,
        price: f64,
        ts: time::SystemTime,
        order: OrderWrapper,
    ) -> bool {
        order.order.lock().order_id = id;
        order.order.lock().order.set_id(id);

        // store new order
        self.idx_queue.as_mut().unwrap().push(OrderIndex {
            id,
            price,
            timestamp: ts,
            order_side: self.queue_side,
            order,
        });

        true
    }

    // use it when price was changed
    pub fn amend(
        &mut self,
        id: u64,
        user_id: u64,
        prices: &Vec<f64>,
        new_expiration: u64,
        signature: Signature,
        ts: time::SystemTime,
    ) -> Option<Vec<OrderWrapper>> {
        if prices.len() == 0 {
            return None;
        }

        let mut idx_queue = self.idx_queue.as_ref().unwrap().clone().into_sorted_vec();
        idx_queue.reverse();
        let mut active_idxs = vec![];
        for idx in idx_queue {
            if idx.id == id {
                active_idxs.push(idx)
            }
        }

        if active_idxs.len() == 0 {
            return None;
        }

        let wrapper = &active_idxs[0].order;
        let mut inner_order = wrapper.order.lock();

        if inner_order.user_id != user_id {
            return None;
        };
        amend_inner(&mut inner_order, prices[0], new_expiration, signature);
        drop(inner_order);

        let mut new_indexes = vec![];
        for (i, idx) in active_idxs.into_iter().enumerate() {
            if prices.len() <= i {
                break;
            }

            let mut wrapper = idx.order;
            wrapper.price = prices[i];

            let new_index = OrderIndex {
                id,
                price: prices[i],
                timestamp: ts,
                order_side: self.queue_side,
                order: wrapper,
            };

            new_indexes.push(new_index)
        }

        let wrappers: Vec<OrderWrapper> = new_indexes.iter().map(|idx| idx.order.clone()).collect();
        self.rebuild_idx(id, new_indexes);

        Some(wrappers)
    }

    /// This cancels all orders with order_id. \
    /// If force is true, then order will be cancelled even if it's not owned by user_id
    pub fn cancel(&mut self, order_id: u64, user_id: u64, force: bool) {
        //

        let mut idx_queue = self.idx_queue.as_ref().unwrap().clone().into_vec();
        idx_queue.retain(|order_ptr| {
            order_ptr.id != order_id && (order_ptr.order.order.lock().user_id != user_id || force)
        });

        let amended_queue = BinaryHeap::from(idx_queue);
        self.idx_queue = Some(amended_queue);
    }

    pub fn remove_order(
        &mut self,
        order_id: u64,
        user_id: u64,
        force: bool,
    ) -> Option<OrderWrapper> {
        let mut idx_queue = self.idx_queue.as_mut().unwrap().clone().into_sorted_vec();
        idx_queue.reverse();

        let mut wrapper = None;
        if let Some(index) = idx_queue
            .iter()
            .position(|x| x.id == order_id && (x.order.order.lock().user_id == user_id || force))
        {
            wrapper = Some(idx_queue.remove(index).order);
        }

        let amended_queue = BinaryHeap::from(idx_queue);
        self.idx_queue = Some(amended_queue);

        wrapper
    }

    pub fn replace_order(&mut self, order_id: u64, new_wrapper: OrderWrapper) {
        let mut idx_queue = self.idx_queue.as_mut().unwrap().clone().into_sorted_vec();
        idx_queue.reverse();

        for wrapp in idx_queue.iter_mut() {
            if wrapp.id == order_id {
                wrapp.price = new_wrapper.price;
                wrapp.order = new_wrapper;
                break;
            }
        }

        let amended_queue = BinaryHeap::from(idx_queue);
        self.idx_queue = Some(amended_queue);
    }

    /// Returns order by id
    pub fn get_order(&self, id: u64) -> Option<OrderWrapper> {
        let mut idx_queue = self.idx_queue.as_ref().unwrap().clone().into_sorted_vec();
        idx_queue.reverse();
        let res = idx_queue.iter().find(|x| x.id == id);

        if res.is_none() {
            return None;
        }

        return Some(res.unwrap().order.clone());
    }

    /* Internal methods */

    /// Used internally when current order is partially matched.
    ///
    /// Note: do not modify price or time, because index doesn't change!
    pub fn modify_current_order(&mut self, id: u64, new_qty: u64) {
        let mut active_orders = self.idx_queue.as_ref().unwrap().clone().into_sorted_vec();
        active_orders.reverse();
        for mut ord in active_orders.iter_mut() {
            if ord.id == id {
                ord.order.qty_left = new_qty;
                break;
            }
        }

        let amended_queue = BinaryHeap::from(active_orders);
        self.idx_queue = Some(amended_queue);
    }

    // /// Verify if queue should be cleaned
    // fn clean_check(&mut self) {
    //     if self.op_counter > self.max_stalled {
    //         self.op_counter = 0;
    //         self.remove_stalled()
    //     } else {
    //         self.op_counter += 1;
    //     }
    // }

    // /// Remove dangling indices without orders from queue
    // fn remove_stalled(&mut self) {
    //     if let Some(idx_queue) = self.idx_queue.take() {
    //         let mut active_orders = idx_queue.into_sorted_vec();
    //         active_orders.retain(|order_ptr| self.orders.contains_key(&order_ptr.id));
    //         self.idx_queue = Some(BinaryHeap::from(active_orders));
    //     }
    // }

    /// Recreate order-index queue with changed index info
    fn rebuild_idx(&mut self, id: u64, idxs: Vec<OrderIndex>) {
        if let Some(idx_queue) = self.idx_queue.take() {
            // deconstruct queue
            let mut active_orders = idx_queue.into_vec();
            // remove old idx value
            active_orders.retain(|order_ptr| order_ptr.id != id);
            // insert new one
            for idx in idxs {
                active_orders.push(idx);
            }
            // construct new queue
            let amended_queue = BinaryHeap::from(active_orders);
            self.idx_queue = Some(amended_queue);
        }
    }

    /// Return ID of current order in queue
    // fn get_current_order_id(&self) -> Option<u64> {
    //     let order_id = self.idx_queue.as_ref()?.peek()?;
    //     Some(order_id.id)
    // }

    /// Remove expired orders from the queue
    pub fn remove_expired_orders(&mut self) {
        let mut active_orders = self.idx_queue.as_ref().unwrap().clone().into_vec();
        active_orders.retain(|ord| !ord.order.order.lock().order.has_expired());

        let amended_queue = BinaryHeap::from(active_orders);
        self.idx_queue = Some(amended_queue);
    }

    /// Returns the liquidity of the queue
    /// ### Returns:
    /// * liquidity: Vec<(f64, u64)> - vector of tuples (price, liquidity)
    pub fn visualize(&self) -> Vec<(f64, u64, u64, u64)> {
        // sort the idx queue
        let mut idx_queue = self.idx_queue.as_ref().unwrap().clone().into_vec();
        idx_queue.sort_by(|a, b| a.partial_cmp(b).unwrap());

        let book = idx_queue
            .iter()
            .rev()
            .filter_map(|idx| {
                let order_ptr = idx.order.order.lock();
                let order_id = order_ptr.order_id;
                drop(order_ptr);

                // Get the order time in seconds since UNIX_EPOCH
                let ts = idx.timestamp;
                let timestamp = ts
                    .duration_since(SystemTime::UNIX_EPOCH)
                    .expect("Time went backwards")
                    .as_secs();

                return Some((idx.price, idx.order.qty_left, timestamp, order_id));
            })
            .collect::<Vec<(f64, u64, u64, u64)>>();

        return book;
    }

    // *-----------------------------------------------------------------------------

    /// Update the order position
    pub fn update_order_position(&mut self, user_id: u64, new_position: &Option<PerpPosition>) {
        if new_position.is_some() {
            let mut idx_queue = self.idx_queue.as_ref().unwrap().clone().into_vec();

            idx_queue.iter_mut().for_each(|idx| {
                let mut order_ptr = idx.order.order.lock();

                if order_ptr.user_id == user_id {
                    if let Order::Perp(ord) = &mut order_ptr.order {
                        if ord.position.is_some()
                            && ord.position.as_ref().unwrap().position_address
                                == new_position.as_ref().unwrap().position_address
                        {
                            ord.position = new_position.clone();
                        }
                    }
                }

                drop(order_ptr)
            });
        }

        return;
    }

    /// Gets the impact price from the impact notional value
    pub fn get_impact_price(&self, impact_notional: u64) -> f64 {
        let mut sum = 0;

        let mut idx_queue = self.idx_queue.as_ref().unwrap().clone().into_sorted_vec();
        idx_queue.reverse();

        let mut price: f64 = 0.0;
        for i in idx_queue {
            sum += i.order.qty_left;
            price = i.price;
            if sum >= impact_notional {
                break;
            }
        }

        price
    }

    // *-----------------------------------------------------------------------------

    /// Stores a pending order!
    ///
    /// Stores the signature and order_side for order_id in case that order fails and needs to
    /// be reinserted into the orderbook.
    pub fn store_pending_order(&mut self, wrapper: OrderWrapper) {
        let order_ptr = wrapper.order.lock();
        let order_id = order_ptr.order_id;
        drop(order_ptr);

        if self.pending_orders.contains_key(&order_id) {
            let current_pending = self.pending_orders.get_mut(&order_id).unwrap();

            current_pending.push(wrapper);
        } else {
            self.pending_orders.insert(order_id, vec![wrapper]);
        }
    }

    /// Removes a pending order!
    ///
    /// Removes reduce_qty amount from the pending order with order_id from
    /// when that order is filled.
    /// In case of cancellations or rejections set force to true to remove the order
    pub fn reduce_pending_order(&mut self, order_id: u64, reduce_qty: u64, force: bool) {
        if !self.pending_orders.contains_key(&order_id) {
            return;
        }

        let wrapper = self.pending_orders.get_mut(&order_id).unwrap();

        wrapper[0].qty_left = wrapper[0].qty_left - reduce_qty;

        if wrapper[0].qty_left <= 0 || force {
            wrapper.remove(0);

            if wrapper.len() == 0 {
                self.pending_orders.remove(&order_id);
            }
        }
    }

    /// Restores a pending order!
    ///
    /// Reinsert the order back into the order book with the signature, side, and qty from the pending order,
    /// or increase the qty of that order if it has already been reinserted, by another partial fill
    pub fn restore_pending_order(&mut self, order_id: u64, order_qty: u64) {
        if self.pending_orders.contains_key(&order_id) {
            let wrappers = self.pending_orders.get_mut(&order_id).unwrap();

            let mut wrapper = wrappers.remove(0);
            wrapper.qty_left += order_qty;

            let l = wrappers.len();
            drop(wrappers);

            if l == 0 {
                self.pending_orders.remove(&order_id);
            }

            let ts = time::SystemTime::now();
            self.insert(order_id, wrapper.price, ts, wrapper);
        } else {
            let wrapper = self.get_order(order_id);

            if let Some(wrapper) = wrapper {
                self.modify_current_order(order_id, wrapper.qty_left + order_qty)
            }
        }
    }

    pub fn get_pending_inner_order(&self, order_id: u64) -> Option<Arc<Mutex<SharedOrderInner>>> {
        if !self.pending_orders.contains_key(&order_id) {
            return None;
        }

        let wrappers = self.pending_orders.get(&order_id).unwrap();

        let order = wrappers[0].order.clone();

        Some(order)
    }
}
