use firestore_db_and_auth::ServiceSession;
use num_bigint::BigUint;
use num_traits::Zero;
use parking_lot::Mutex;
use serde_json::{json, to_vec, Map, Value};
use std::{
    collections::HashMap,
    fs,
    path::Path,
    str::FromStr,
    sync::Arc,
    thread::{self, JoinHandle, ThreadId},
    time::SystemTime,
};

use error_stack::Result;

use crate::{
    order_tab::{close_tab::close_order_tab, open_tab::open_order_tab},
    perpetual::{
        liquidations::{
            liquidation_engine::LiquidationSwap, liquidation_output::LiquidationResponse,
        },
        perp_helpers::{
            perp_rollback::PerpRollbackInfo, perp_swap_helpers::get_max_leverage,
            perp_swap_outptut::PerpSwapResponse,
        },
        perp_position::PerpPosition,
        perp_swap::PerpSwap,
        COLLATERAL_TOKEN, SYNTHETIC_ASSETS,
    },
    server::grpc::{OrderTabActionMessage, OrderTabActionResponse},
    smart_contract_mms::{
        add_liquidity::add_liquidity_to_mm, register_mm::onchain_register_mm,
        remove_liquidity::remove_liquidity_from_order_tab,
    },
    transaction_batch::restore_state_helpers::{
        helpers::{restore_margin_update, restore_note_split},
        restore_order_tabs::{
            restore_add_liquidity, restore_close_order_tab, restore_open_order_tab,
            restore_register_mm, restore_remove_liquidity,
        },
        restore_perp_swaps::{restore_liquidation_order_execution, restore_perp_order_execution},
        restore_spot_swap::{
            restore_deposit_update, restore_spot_order_execution, restore_withdrawal_update,
        },
    },
    transactions::{
        transaction_helpers::db_updates::{update_db_after_note_split, DbNoteUpdater},
        Transaction,
    },
    utils::firestore::{start_add_note_thread, start_add_position_thread, upload_file_to_storage},
};
use crate::{server::grpc::RollbackMessage, utils::storage::MainStorage};
use crate::{
    trees::{superficial_tree::SuperficialTree, Tree},
    utils::storage::BackupStorage,
};

use crate::utils::{
    errors::{
        BatchFinalizationError, OracleUpdateError, PerpSwapExecutionError,
        TransactionExecutionError,
    },
    firestore::create_session,
    notes::Note,
};

use crate::transactions::{swap::SwapResponse, transaction_helpers::rollbacks::RollbackInfo};

use crate::server::{
    grpc::{ChangeMarginMessage, FundingUpdateMessage},
    server_helpers::engine_helpers::{verify_margin_change_signature, verify_position_existence},
};

use tx_batch_helpers::{_per_minute_funding_update_inner, get_funding_info, split_hashmap};
use tx_batch_structs::{get_price_info, GlobalConfig};

use crate::transaction_batch::{
    tx_batch_helpers::{
        _init_empty_tokens_map, add_margin_state_updates, get_final_updated_counts,
        get_json_output, reduce_margin_state_updates,
    },
    tx_batch_structs::{FundingInfo, GlobalDexState, OracleUpdate, SwapFundingInfo},
};

use self::tx_batch_helpers::_calculate_funding_rates;

// TODO: This could be weighted sum of different transactions (e.g. 5 for swaps, 1 for deposits, 1 for withdrawals)
// const TRANSACTIONS_PER_BATCH: u16 = 10; // Number of transaction per batch (until batch finalization)

// TODO: Make fields in all classes private where they should be

// TODO: If you get a note doesn't exist error, there should  be a function where you can check the existence of all your notes

pub mod batch_functions;
pub mod restore_state_helpers;
pub mod tx_batch_helpers;
pub mod tx_batch_structs;

// { ETH Mainnet: 9090909, Starknet: 7878787, ZkSync: 5656565 }
pub const CHAIN_IDS: [u32; 3] = [9090909, 7878787, 5656565];
pub const TREE_DEPTH: u32 = 32;

#[derive(Clone, Debug)]
pub enum LeafNodeType {
    Note,
    Position,
    OrderTab,
    MMSpotRegistration,
    MMPerpRegistration,
}
pub struct TransactionBatch {
    pub state_tree: Arc<Mutex<SuperficialTree>>, // current state tree (superficial tree only stores the leaves)
    pub partial_fill_tracker: Arc<Mutex<HashMap<u64, (Option<Note>, u64)>>>, // maps orderIds to partial fill refund notes and filled mounts
    pub updated_state_hashes: Arc<Mutex<HashMap<u64, (LeafNodeType, BigUint)>>>, // info to get merkle proofs at the end of the batch
    pub swap_output_json: Arc<Mutex<Vec<serde_json::Map<String, Value>>>>, // json output map for cairo input
    pub blocked_order_ids: Arc<Mutex<HashMap<u64, bool>>>, // maps orderIds to whether they are blocked while another thread is processing the same order (in case of partial fills)
    //
    // pub perpetual_state_tree: Arc<Mutex<SuperficialTree>>, // current perpetual state tree (superficial tree only stores the leaves)
    pub perpetual_partial_fill_tracker: Arc<Mutex<HashMap<u64, (Option<Note>, u64, u64)>>>, // (pfr_note, amount_filled, spent_margin)
    pub partialy_opened_positions: Arc<Mutex<HashMap<String, (PerpPosition, u64)>>>, // positions that were partially opened in an order that was partially filled
    pub blocked_perp_order_ids: Arc<Mutex<HashMap<u64, bool>>>, // maps orderIds to whether they are blocked while another thread is processing the same order (in case of partial fills)
    pub insurance_fund: Arc<Mutex<i64>>, // insurance fund used to pay for liquidations
    //
    pub latest_index_price: HashMap<u32, u64>,
    pub min_index_price_data: HashMap<u32, (u64, OracleUpdate)>, // maps asset id to the min price, OracleUpdate info of this batch
    pub max_index_price_data: HashMap<u32, (u64, OracleUpdate)>, // maps asset id to the max price, OracleUpdate info of this batch
    //
    pub running_funding_tick_sums: HashMap<u32, i64>, // maps asset id to the sum of all funding ticks in this batch (used for TWAP)
    pub current_funding_count: u16, // maps asset id to the number of funding ticks applied already (used for TWAP, goes up to 480)

    pub funding_rates: HashMap<u32, Vec<i64>>, // maps asset id to an array of funding rates (not reset at new batch)
    pub funding_prices: HashMap<u32, Vec<u64>>, // maps asset id to an array of funding prices (corresponding to the funding rates) (not reset at new batch)
    pub current_funding_idx: u32, // the current index of the funding rates and prices arrays
    pub funding_idx_shift: HashMap<u32, u32>, // maps asset id to an funding idx shift
    pub min_funding_idxs: Arc<Mutex<HashMap<u32, u32>>>, // the min funding index of a position being updated in this batch for each asset
    //
    pub rollback_safeguard: Arc<Mutex<HashMap<ThreadId, RollbackInfo>>>, // used to rollback the state in case of errors
    pub perp_rollback_safeguard: Arc<Mutex<HashMap<ThreadId, PerpRollbackInfo>>>, // used to rollback the perp_state in case of errors
    //
    pub firebase_session: Arc<Mutex<ServiceSession>>, // Firebase session for updating the database in the cloud
    pub main_storage: Arc<Mutex<MainStorage>>,        // Storage Connection to store data on disk
    pub backup_storage: Arc<Mutex<BackupStorage>>,    // Storage for failed database updates
    //
    pub running_tx_count: u16, // number of transactions in the current micro batch
    pub running_index_price_count: u16, // number of index price updates in the current micro batch
}

impl TransactionBatch {
    pub fn new(
        tree_depth: u32,
        rollback_safeguard: Arc<Mutex<HashMap<ThreadId, RollbackInfo>>>,
        perp_rollback_safeguard: Arc<Mutex<HashMap<ThreadId, PerpRollbackInfo>>>,
    ) -> TransactionBatch {
        let state_tree = SuperficialTree::new(tree_depth);
        let partial_fill_tracker: HashMap<u64, (Option<Note>, u64)> = HashMap::new();
        let updated_state_hashes: HashMap<u64, (LeafNodeType, BigUint)> = HashMap::new();
        let swap_output_json: Vec<serde_json::Map<String, Value>> = Vec::new();
        let blocked_order_ids: HashMap<u64, bool> = HashMap::new();

        // let perpetual_state_tree = SuperficialTree::new(perp_tree_depth);
        let perpetual_partial_fill_tracker: HashMap<u64, (Option<Note>, u64, u64)> = HashMap::new();
        let partialy_opened_positions: HashMap<String, (PerpPosition, u64)> = HashMap::new();
        let blocked_perp_order_ids: HashMap<u64, bool> = HashMap::new();

        // let order_tabs_state_tree = SuperficialTree::new(16);

        let mut latest_index_price: HashMap<u32, u64> = HashMap::new();
        let mut min_index_price_data: HashMap<u32, (u64, OracleUpdate)> = HashMap::new();
        let mut max_index_price_data: HashMap<u32, (u64, OracleUpdate)> = HashMap::new();

        let mut running_funding_tick_sums: HashMap<u32, i64> = HashMap::new();
        let mut funding_rates: HashMap<u32, Vec<i64>> = HashMap::new();
        let mut funding_prices: HashMap<u32, Vec<u64>> = HashMap::new();
        let mut min_funding_idxs: HashMap<u32, u32> = HashMap::new();
        let mut funding_idx_shift: HashMap<u32, u32> = HashMap::new();

        let session = create_session();
        let session = Arc::new(Mutex::new(session));

        // Init empty maps
        _init_empty_tokens_map::<u64>(&mut latest_index_price);
        _init_empty_tokens_map::<(u64, OracleUpdate)>(&mut min_index_price_data);
        _init_empty_tokens_map::<(u64, OracleUpdate)>(&mut max_index_price_data);
        _init_empty_tokens_map::<i64>(&mut running_funding_tick_sums);
        _init_empty_tokens_map::<Vec<i64>>(&mut funding_rates);
        _init_empty_tokens_map::<Vec<u64>>(&mut funding_prices);
        _init_empty_tokens_map::<u32>(&mut funding_idx_shift);
        _init_empty_tokens_map::<u32>(&mut min_funding_idxs);

        // TODO: For testing only =================================================
        latest_index_price.insert(54321, 2000 * 10u64.pow(6));
        latest_index_price.insert(12345, 30000 * 10u64.pow(6));
        latest_index_price.insert(66666, 10800);
        // TODO: For testing only =================================================

        let tx_batch = TransactionBatch {
            state_tree: Arc::new(Mutex::new(state_tree)),
            partial_fill_tracker: Arc::new(Mutex::new(partial_fill_tracker)),
            updated_state_hashes: Arc::new(Mutex::new(updated_state_hashes)),
            swap_output_json: Arc::new(Mutex::new(swap_output_json)),
            blocked_order_ids: Arc::new(Mutex::new(blocked_order_ids)),
            //
            perpetual_partial_fill_tracker: Arc::new(Mutex::new(perpetual_partial_fill_tracker)),
            partialy_opened_positions: Arc::new(Mutex::new(partialy_opened_positions)),
            blocked_perp_order_ids: Arc::new(Mutex::new(blocked_perp_order_ids)),
            insurance_fund: Arc::new(Mutex::new(0)),
            //
            latest_index_price,
            min_index_price_data,
            max_index_price_data,
            //
            running_funding_tick_sums,
            current_funding_count: 0,
            funding_rates,
            funding_prices,
            current_funding_idx: 0,
            funding_idx_shift,
            min_funding_idxs: Arc::new(Mutex::new(min_funding_idxs)),
            //
            rollback_safeguard,
            perp_rollback_safeguard,
            //
            firebase_session: session,
            main_storage: Arc::new(Mutex::new(MainStorage::new())),
            backup_storage: Arc::new(Mutex::new(BackupStorage::new())),
            //
            running_tx_count: 0,
            running_index_price_count: 0,
        };

        return tx_batch;
    }

    /// This initializes the transaction batch from a previous state
    pub fn init(&mut self) {
        let storage = self.main_storage.lock();
        if !storage.funding_db.is_empty() {
            if let Ok((funding_rates, funding_prices, funding_idx, min_funding_idxs)) =
                storage.read_funding_info()
            {
                let mut funding_idx_shift = HashMap::new();
                for t in SYNTHETIC_ASSETS {
                    let rates_arr_len = funding_rates.get(&t).unwrap_or(&vec![]).len();

                    let shift = funding_idx - rates_arr_len as u32;

                    funding_idx_shift.insert(t, shift);
                }

                self.funding_rates = funding_rates;
                self.funding_prices = funding_prices;
                self.current_funding_idx = funding_idx;
                self.funding_idx_shift = funding_idx_shift;

                self.min_funding_idxs = Arc::new(Mutex::new(min_funding_idxs));
            } else {
                panic!("Error reading funding info from storage");
            }
        }

        if !storage.price_db.is_empty() {
            if let Some((latest_index_price, min_index_price_data, max_index_price_data)) =
                storage.read_price_data()
            {
                self.latest_index_price = latest_index_price;
                self.min_index_price_data = min_index_price_data;
                self.max_index_price_data = max_index_price_data;
            }
        }

        let state_tree = match SuperficialTree::from_disk() {
            Ok(tree) => tree,
            Err(_) => SuperficialTree::new(32),
        };

        self.state_tree = Arc::new(Mutex::new(state_tree));
        // let perp_state_tree = match SuperficialTree::from_disk(&TreeStateType::Perpetual) {
        //     Ok(tree) => tree,
        //     Err(_) => SuperficialTree::new(32),
        // };
        // self.perpetual_state_tree = Arc::new(Mutex::new(perp_state_tree));

        if !storage.tx_db.is_empty() {
            let swap_output_json = storage.read_storage(0);
            drop(storage);
            self.restore_state(swap_output_json);
        }
    }

    pub fn revert_current_tx_batch(&mut self) {
        // TODO: Copy the state_tree_backup file to the current state_tree file

        // ? Attempt to delete the file
        let latest_batch_index = self.main_storage.lock().latest_batch;
        match fs::remove_file(
            "./storage/transaction_data/".to_string() + latest_batch_index.to_string().as_str(),
        ) {
            Ok(()) => println!("File deleted successfully"),
            Err(err) => eprintln!("Error deleting file: {}", err),
        }
    }

    pub fn execute_transaction<T: Transaction + std::marker::Send + 'static>(
        &mut self,
        mut transaction: T,
    ) -> JoinHandle<Result<(Option<SwapResponse>, Option<Vec<u64>>), TransactionExecutionError>>
    {
        //

        let tx_type = String::from_str(transaction.transaction_type()).unwrap();

        let state_tree = self.state_tree.clone();
        let partial_fill_tracker = self.partial_fill_tracker.clone();
        let updated_state_hashes = self.updated_state_hashes.clone();
        let swap_output_json = self.swap_output_json.clone();
        let blocked_order_ids = self.blocked_order_ids.clone();
        let rollback_safeguard = self.rollback_safeguard.clone();
        let session = self.firebase_session.clone();
        let backup_storage = self.backup_storage.clone();

        let handle = thread::spawn(move || {
            let res = transaction.execute_transaction(
                state_tree,
                partial_fill_tracker,
                updated_state_hashes,
                swap_output_json,
                blocked_order_ids,
                rollback_safeguard,
                &session,
                &backup_storage,
            );
            return res;
        });

        return handle;
    }

    pub fn execute_perpetual_transaction(
        &mut self,
        transaction: PerpSwap,
    ) -> JoinHandle<Result<PerpSwapResponse, PerpSwapExecutionError>> {
        let state_tree = self.state_tree.clone();
        let updated_state_hashes = self.updated_state_hashes.clone();
        let swap_output_json = self.swap_output_json.clone();

        let perpetual_partial_fill_tracker = self.perpetual_partial_fill_tracker.clone();
        let partialy_opened_positions = self.partialy_opened_positions.clone();
        let blocked_perp_order_ids = self.blocked_perp_order_ids.clone();

        let session = self.firebase_session.clone();
        let backup_storage = self.backup_storage.clone();

        let current_index_price = *self
            .latest_index_price
            .get(&transaction.order_a.synthetic_token)
            .unwrap();
        let min_funding_idxs = self.min_funding_idxs.clone();

        let perp_rollback_safeguard = self.perp_rollback_safeguard.clone();

        let swap_funding_info = SwapFundingInfo::new(
            &self.funding_rates,
            &self.funding_prices,
            self.current_funding_idx,
            &self.funding_idx_shift,
            transaction.order_a.synthetic_token,
            &transaction.order_a.position,
            &transaction.order_b.position,
        );

        let handle = thread::spawn(move || {
            return transaction.execute(
                state_tree,
                updated_state_hashes,
                swap_output_json,
                blocked_perp_order_ids,
                perpetual_partial_fill_tracker,
                partialy_opened_positions,
                current_index_price,
                min_funding_idxs,
                swap_funding_info,
                perp_rollback_safeguard,
                session,
                backup_storage,
            );
        });

        self.running_tx_count += 1;

        return handle;
    }

    pub fn execute_liquidation_transaction(
        &mut self,
        liquidation_transaction: LiquidationSwap,
    ) -> JoinHandle<Result<LiquidationResponse, PerpSwapExecutionError>> {
        let state_tree = self.state_tree.clone();
        let updated_state_hashes = self.updated_state_hashes.clone();
        let swap_output_json = self.swap_output_json.clone();

        let session = self.firebase_session.clone();
        let backup_storage = self.backup_storage.clone();

        let insurance_fund = self.insurance_fund.clone();

        let current_index_price = *self
            .latest_index_price
            .get(&liquidation_transaction.liquidation_order.synthetic_token)
            .unwrap();
        let min_funding_idxs = self.min_funding_idxs.clone();

        let swap_funding_info = SwapFundingInfo::new(
            &self.funding_rates,
            &self.funding_prices,
            self.current_funding_idx,
            &self.funding_idx_shift,
            liquidation_transaction.liquidation_order.synthetic_token,
            &Some(liquidation_transaction.liquidation_order.position.clone()),
            &None,
        );

        let handle = thread::spawn(move || {
            return liquidation_transaction.execute(
                state_tree,
                updated_state_hashes,
                swap_output_json,
                insurance_fund,
                current_index_price,
                min_funding_idxs,
                swap_funding_info,
                session,
                backup_storage,
            );
        });

        self.running_tx_count += 1;

        return handle;
    }

    // * Rollback the transaction execution state updates
    pub fn rollback_transaction(&mut self, _rollback_info_message: (ThreadId, RollbackMessage)) {
        // let thread_id = rollback_info_message.0;
        // let rollback_message = rollback_info_message.1;

        println!(
            "Rolling back transaction: {:?}",
            _rollback_info_message.1.tx_type
        );

        // if rollback_message.tx_type == "deposit" {
        //     // ? rollback the deposit execution state updates

        //     let rollback_info = self.rollback_safeguard.lock().remove(&thread_id).unwrap();

        //     rollback_deposit_updates(&self.state_tree, &self.updated_state_hashes, rollback_info);
        // } else if rollback_message.tx_type == "swap" {
        //     // ? rollback the swap execution state updates

        //     let rollback_info = self.rollback_safeguard.lock().remove(&thread_id).unwrap();

        //     rollback_swap_updates(
        //         &self.state_tree,
        //         &self.updated_state_hashes,
        //         rollback_message,
        //         rollback_info,
        //     );
        // } else if rollback_message.tx_type == "withdrawal" {
        //     // ? rollback the withdrawal execution state updates

        //     rollback_withdrawal_updates(
        //         &self.state_tree,
        //         &self.updated_state_hashes,
        //         rollback_message,
        //     );
        // } else if rollback_message.tx_type == "perp_swap" {
        //     // ? rollback the perp swap execution state updates

        //     let rollback_info = self
        //         .perp_rollback_safeguard
        //         .lock()
        //         .remove(&thread_id)
        //         .unwrap();

        //     rollback_perp_swap(
        //         &self.state_tree,
        //         &self.updated_state_hashes,
        //         &self.perpetual_state_tree,
        //         &self.perpetual_updated_position_hashes,
        //         rollback_message,
        //         rollback_info,
        //     );
        // }
    }

    // * =================================================================
    // TODO: These two functions should take a constant fee to ensure not being DOSed
    pub fn split_notes(
        &mut self,
        notes_in: Vec<Note>,
        mut new_note: Note,
        mut refund_note: Option<Note>,
    ) -> std::result::Result<Vec<u64>, String> {
        let token = notes_in[0].token;

        let mut sum_in: u64 = 0;

        let mut state_tree = self.state_tree.lock();
        for note in notes_in.iter() {
            if note.token != token {
                return Err("Invalid token".to_string());
            }

            let leaf_hash = state_tree.get_leaf_by_index(note.index);

            if leaf_hash != note.hash {
                return Err("Note does not exist".to_string());
            }

            sum_in += note.amount;
        }

        if new_note.token != token {
            return Err("Invalid token".to_string());
        }

        let note_in1 = &notes_in[0];
        if new_note.blinding != note_in1.blinding || new_note.address.x != note_in1.address.x {
            return Err("Mismatch od address and blinding between input/output notes".to_string());
        }
        let new_amount = new_note.amount;

        // ? get and set new index
        let new_index = state_tree.first_zero_idx();
        new_note.index = new_index;

        let mut new_indexes = vec![new_index];

        let mut refund_amount: u64 = 0;
        if refund_note.is_some() {
            let refund_note = refund_note.as_mut().unwrap();

            if refund_note.token != token {
                return Err("Invalid token".to_string());
            }

            let note_in2 = &notes_in[notes_in.len() - 1];
            if refund_note.blinding != note_in2.blinding
                || refund_note.address.x != note_in2.address.x
            {
                return Err(
                    "Mismatch of address and blinding between input/output notes".to_string(),
                );
            }

            refund_amount = refund_note.amount;

            let new_index = state_tree.first_zero_idx();
            refund_note.index = new_index;
            new_indexes.push(new_index)
        }

        if sum_in != new_amount + refund_amount {
            return Err("New note amounts exceed old note amounts".to_string());
        }

        // ? Remove notes in from state
        let mut updated_state_hashes = self.updated_state_hashes.lock();
        for note in notes_in.iter() {
            state_tree.update_leaf_node(&BigUint::zero(), note.index);
            updated_state_hashes.insert(note.index, (LeafNodeType::Note, BigUint::zero()));
        }

        // ? Add return in to state
        state_tree.update_leaf_node(&new_note.hash, new_note.index);
        updated_state_hashes.insert(new_note.index, (LeafNodeType::Note, new_note.hash.clone()));

        if let Some(note) = refund_note.as_ref() {
            state_tree.update_leaf_node(&note.hash, note.index);
            updated_state_hashes.insert(note.index, (LeafNodeType::Note, note.hash.clone()));
        }

        drop(updated_state_hashes);
        drop(state_tree);

        // ----------------------------------------------

        update_db_after_note_split(
            &self.firebase_session,
            &self.backup_storage,
            &notes_in,
            new_note.clone(),
            refund_note.clone(),
        );

        // ----------------------------------------------

        let mut json_map = serde_json::map::Map::new();
        json_map.insert(
            String::from("transaction_type"),
            serde_json::to_value("note_split").unwrap(),
        );
        json_map.insert(
            String::from("note_split"),
            json!({"token": token, "notes_in": notes_in, "new_note": new_note, "refund_note": refund_note}),
        );

        let mut swap_output_json = self.swap_output_json.lock();
        swap_output_json.push(json_map);
        drop(swap_output_json);

        Ok(new_indexes)
    }

    pub fn change_position_margin(
        &self,
        margin_change: ChangeMarginMessage,
    ) -> std::result::Result<(u64, PerpPosition), String> {
        let current_index_price = *self
            .latest_index_price
            .get(&margin_change.position.position_header.synthetic_token)
            .unwrap();

        verify_margin_change_signature(&margin_change)?;

        let mut position = margin_change.position.clone();
        verify_position_existence(&position, &self.state_tree)?;

        position.modify_margin(margin_change.margin_change)?;

        let leverage = position
            .get_current_leverage(current_index_price)
            .map_err(|e| e.to_string())?;

        // ? Check that leverage is valid relative to the notional position size after increasing size
        if get_max_leverage(
            position.position_header.synthetic_token,
            position.position_size,
        ) < leverage
        {
            println!(
                "Leverage would be too high {} > {}",
                leverage,
                get_max_leverage(
                    position.position_header.synthetic_token,
                    position.position_size
                ),
            );
            return Err("Leverage would be too high".to_string());
        }

        let mut z_index: u64 = 0;
        let mut valid: bool = true;
        if margin_change.margin_change >= 0 {
            let amount_in = margin_change
                .notes_in
                .as_ref()
                .unwrap()
                .iter()
                .fold(0, |acc, n| {
                    if n.token != COLLATERAL_TOKEN {
                        valid = true;
                    }
                    return acc + n.amount;
                });
            let refund_amount = if margin_change.refund_note.is_some() {
                margin_change.refund_note.as_ref().unwrap().amount
            } else {
                0
            };

            if !valid {
                return Err("Invalid token".to_string());
            }
            if amount_in < margin_change.margin_change.abs() as u64 + refund_amount {
                return Err("Invalid amount in".to_string());
            }

            add_margin_state_updates(
                &self.state_tree,
                &self.updated_state_hashes,
                margin_change.notes_in.as_ref().unwrap(),
                margin_change.refund_note.clone(),
                position.index as u64,
                &position.hash.clone(),
            )?;

            let _handle = start_add_position_thread(
                position.clone(),
                &self.firebase_session,
                &self.backup_storage,
            );

            let delete_notes = margin_change
                .notes_in
                .as_ref()
                .unwrap()
                .iter()
                .map(|n| (n.index, n.address.x.to_string()))
                .collect::<Vec<(u64, String)>>();
            let mut add_notes = vec![];
            if margin_change.refund_note.is_some() {
                add_notes.push(margin_change.refund_note.as_ref().unwrap());
            }

            let updater = DbNoteUpdater {
                session: &self.firebase_session,
                backup_storage: &self.backup_storage,
                delete_notes,
                add_notes,
            };

            let _handles = updater.update_db();
        } else {
            let mut tree = self.state_tree.lock();

            let index = tree.first_zero_idx();
            drop(tree);

            let return_collateral_note = Note::new(
                index,
                margin_change
                    .close_order_fields
                    .as_ref()
                    .unwrap()
                    .dest_received_address
                    .clone(),
                COLLATERAL_TOKEN,
                margin_change.margin_change.abs() as u64,
                margin_change
                    .close_order_fields
                    .as_ref()
                    .unwrap()
                    .dest_received_blinding
                    .clone(),
            );

            reduce_margin_state_updates(
                &self.state_tree,
                &self.updated_state_hashes,
                return_collateral_note.clone(),
                position.index as u64,
                &position.hash.clone(),
            );

            let _handle = start_add_position_thread(
                position.clone(),
                &self.firebase_session,
                &self.backup_storage,
            );

            let _handle = start_add_note_thread(
                return_collateral_note,
                &self.firebase_session,
                &self.backup_storage,
            );

            z_index = index;
        }

        // ----------------------------------------------

        let mut json_map = serde_json::map::Map::new();
        json_map.insert(
            String::from("transaction_type"),
            serde_json::to_value("margin_change").unwrap(),
        );
        json_map.insert(
            String::from("margin_change"),
            serde_json::to_value(margin_change).unwrap(),
        );
        json_map.insert(
            String::from("new_position_hash"),
            serde_json::to_value(position.hash.to_string()).unwrap(),
        );
        json_map.insert(
            String::from("zero_idx"),
            serde_json::to_value(z_index).unwrap(),
        );

        let mut swap_output_json = self.swap_output_json.lock();
        swap_output_json.push(json_map);
        drop(swap_output_json);

        Ok((z_index, position))
    }

    pub fn execute_order_tab_modification(
        &mut self,
        tab_action_message: OrderTabActionMessage,
    ) -> JoinHandle<OrderTabActionResponse> {
        let state_tree = self.state_tree.clone();
        let updated_state_hashes = self.updated_state_hashes.clone();
        let session = self.firebase_session.clone();
        let backup_storage = self.backup_storage.clone();
        let swap_output_json = self.swap_output_json.clone();

        let latest_index_price = self.latest_index_price.clone();

        let handle = thread::spawn(move || {
            if tab_action_message.open_order_tab_req.is_some() {
                let open_order_tab_req = tab_action_message.open_order_tab_req.unwrap();

                let new_order_tab = open_order_tab(
                    &session,
                    &backup_storage,
                    open_order_tab_req,
                    &state_tree,
                    &updated_state_hashes,
                    &swap_output_json,
                );

                let order_tab_action_response = OrderTabActionResponse {
                    open_tab_response: Some(new_order_tab),
                    close_tab_response: None,
                    add_liq_response: None,
                    register_mm_response: None,
                    remove_liq_response: None,
                };

                return order_tab_action_response;
            } else if tab_action_message.close_order_tab_req.is_some() {
                let close_order_tab_req = tab_action_message.close_order_tab_req.unwrap();

                let close_tab_response = close_order_tab(
                    &session,
                    &backup_storage,
                    &state_tree,
                    &updated_state_hashes,
                    &swap_output_json,
                    close_order_tab_req,
                );

                let order_tab_action_response = OrderTabActionResponse {
                    open_tab_response: None,
                    close_tab_response: Some(close_tab_response),
                    add_liq_response: None,
                    register_mm_response: None,
                    remove_liq_response: None,
                };

                return order_tab_action_response;
            } else if tab_action_message.onchain_register_mm_req.is_some() {
                let register_mm_req = tab_action_message.onchain_register_mm_req.unwrap();

                let index_price = *latest_index_price
                    .get(&register_mm_req.base_token)
                    .unwrap_or(&0);

                let register_mm_response = onchain_register_mm(
                    &session,
                    &backup_storage,
                    register_mm_req,
                    &state_tree,
                    &updated_state_hashes,
                    &swap_output_json,
                    index_price,
                );

                let order_tab_action_response = OrderTabActionResponse {
                    open_tab_response: None,
                    close_tab_response: None,
                    add_liq_response: None,
                    register_mm_response: Some(register_mm_response),
                    remove_liq_response: None,
                };

                return order_tab_action_response;
            } else if tab_action_message.onchain_add_liq_req.is_some() {
                let add_liquidity_req = tab_action_message.onchain_add_liq_req.unwrap();

                let index_price = *latest_index_price
                    .get(&add_liquidity_req.base_token)
                    .unwrap_or(&0);

                let result = add_liquidity_to_mm(
                    &session,
                    &backup_storage,
                    add_liquidity_req,
                    &state_tree,
                    &updated_state_hashes,
                    &swap_output_json,
                    index_price,
                );

                let order_tab_action_response = OrderTabActionResponse {
                    open_tab_response: None,
                    close_tab_response: None,
                    add_liq_response: Some(result),
                    register_mm_response: None,
                    remove_liq_response: None,
                };

                return order_tab_action_response;
            } else {
                let remove_liquidity_req = tab_action_message.onchain_remove_liq_req.unwrap();

                let index_price = *latest_index_price
                    .get(&remove_liquidity_req.base_token)
                    .unwrap_or(&0);

                let remove_liq_response = remove_liquidity_from_order_tab(
                    &session,
                    &backup_storage,
                    remove_liquidity_req,
                    &state_tree,
                    &updated_state_hashes,
                    &swap_output_json,
                    index_price,
                );

                let order_tab_action_response = OrderTabActionResponse {
                    open_tab_response: None,
                    close_tab_response: None,
                    add_liq_response: None,
                    register_mm_response: None,
                    remove_liq_response: Some(remove_liq_response),
                };

                return order_tab_action_response;
            }
        });

        return handle;
    }

    // * =================================================================
    // * FINALIZE BATCH

    pub fn finalize_batch(&mut self) -> Result<(), BatchFinalizationError> {
        // & Get the merkle trees from the beginning of the batch from disk

        let state_tree = self.state_tree.clone();
        let mut state_tree = state_tree.lock();
        state_tree.update_zero_idxs();

        let main_storage = self.main_storage.clone();
        let mut main_storage = main_storage.lock();
        let latest_output_json = self.swap_output_json.clone();
        let latest_output_json = latest_output_json.lock();

        let current_batch_index = main_storage.latest_batch;
        let (n_deposits, n_withdrawals) = (main_storage.n_deposits, main_storage.n_withdrawals);

        // ? Store the latest output json
        main_storage.store_micro_batch(&latest_output_json);
        main_storage.transition_to_new_batch();

        let min_funding_idxs = &self.min_funding_idxs;
        let funding_rates = &self.funding_rates;
        let funding_prices = &self.funding_prices;
        let min_index_price_data = &self.min_index_price_data;
        let max_index_price_data = &self.max_index_price_data;

        let mut updated_state_hashes_c = self.updated_state_hashes.lock();
        let updated_state_hashes: HashMap<u64, (LeafNodeType, BigUint)> =
            updated_state_hashes_c.clone();

        // ?  Get the funding info
        let funding_info: FundingInfo =
            get_funding_info(min_funding_idxs, funding_rates, funding_prices);

        // ? Get the price info
        let price_info_json = get_price_info(min_index_price_data, max_index_price_data);

        // ? Get the final updated counts for the cairo program input
        let [n_output_notes, n_output_positions, n_output_tabs, n_zero_indexes, n_mm_registrations] =
            get_final_updated_counts(&updated_state_hashes);

        updated_state_hashes_c.clear();

        // ? Drop the locks before updating the trees
        drop(state_tree);
        drop(main_storage);
        drop(updated_state_hashes_c);

        // ? Reset the batch
        self.reset_batch();

        // ? Update the merkle trees and get the new roots and preimages
        let (prev_spot_root, new_spot_root, preimage_json) =
            self.update_trees(updated_state_hashes)?;

        // ? Construct the global state and config
        let global_expiration_timestamp = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .expect("Time went backwards")
            .as_secs() as u32;
        let global_dex_state: GlobalDexState = GlobalDexState::new(
            current_batch_index,
            &prev_spot_root,
            &new_spot_root,
            TREE_DEPTH,
            global_expiration_timestamp,
            n_output_notes,
            n_output_positions,
            n_output_tabs,
            n_zero_indexes,
            n_deposits,
            n_withdrawals,
            n_mm_registrations,
        );

        let global_config: GlobalConfig = GlobalConfig::new();

        let main_storage = self.main_storage.lock();
        let swap_output_json = main_storage.read_storage(1);
        drop(main_storage);

        let output_json: Map<String, Value> = get_json_output(
            &global_dex_state,
            &global_config,
            &funding_info,
            price_info_json,
            &swap_output_json,
            preimage_json,
        );

        // Todo: This is for testing only ----------------------------
        let path = Path::new("../cairo_contracts/transaction_batch/tx_batch_input.json");
        std::fs::write(path, serde_json::to_string(&output_json).unwrap()).unwrap();
        // Todo: This is for testing only ----------------------------

        // & Write transaction batch json to database
        let serialized_data = to_vec(&output_json).expect("Serialization failed");
        let _handle = tokio::spawn(async move {
            if let Err(e) = upload_file_to_storage(
                "tx_batches/".to_string() + &current_batch_index.to_string(),
                serialized_data,
            )
            .await
            {
                println!("Error uploading file to storage: {:?}", e);
            }
        });

        println!("Transaction batch finalized successfully!");

        Ok(())
    }

    const PARTITION_SIZE_EXPONENT: u32 = 12;
    pub fn update_trees(
        &mut self,
        updated_state_hashes: HashMap<u64, (LeafNodeType, BigUint)>,
    ) -> Result<(BigUint, BigUint, Map<String, Value>), BatchFinalizationError> {
        // * UPDATE SPOT TREES  -------------------------------------------------------------------------------------
        let mut updated_root_hashes: HashMap<u64, BigUint> = HashMap::new(); // the new roots of all tree partitions

        let mut preimage_json: Map<String, Value> = Map::new();

        let partitioned_hashes = split_hashmap(
            updated_state_hashes,
            2_usize.pow(Self::PARTITION_SIZE_EXPONENT) as usize,
        );

        // ? Loop over all partitions and update the trees
        for (partition_index, partition) in partitioned_hashes {
            if partition.is_empty() {
                continue;
            }

            let (_, new_root) =
                self.tree_partition_update(partition, &mut preimage_json, partition_index as u32)?;

            updated_root_hashes.insert(partition_index as u64, new_root);
        }

        // ? use the newly generated roots to update the state tree
        let (prev_spot_root, new_spot_root) =
            self.tree_partition_update(updated_root_hashes, &mut preimage_json, u32::MAX)?;

        Ok((prev_spot_root, new_spot_root, preimage_json))
    }

    pub fn tree_partition_update(
        &mut self,
        updated_state_hashes: HashMap<u64, BigUint>,
        preimage_json: &mut Map<String, Value>,
        tree_index: u32,
    ) -> Result<(BigUint, BigUint), BatchFinalizationError> {
        let shift = if tree_index == u32::MAX {
            Self::PARTITION_SIZE_EXPONENT
        } else {
            0
        };
        let depth = if tree_index == u32::MAX {
            TREE_DEPTH - Self::PARTITION_SIZE_EXPONENT
        } else {
            Self::PARTITION_SIZE_EXPONENT
        };

        let mut batch_init_tree =
            Tree::from_disk(tree_index, depth, shift).map_err(|_| BatchFinalizationError {})?;

        let prev_root = batch_init_tree.root.clone();

        // ? Store the current tree to disk as a backup
        batch_init_tree
            .store_to_disk(tree_index, true)
            .map_err(|e| {
                println!("Error storing backup tree to disk: {:?}", e);
                BatchFinalizationError {}
            })?;

        batch_init_tree.batch_transition_updates(&updated_state_hashes, preimage_json);

        let new_root = batch_init_tree.root.clone();

        // ? Store the current tree to disk as a backup
        batch_init_tree
            .store_to_disk(tree_index, false)
            .map_err(|e| {
                println!("Error storing updated tree to disk: {:?}", e);
                BatchFinalizationError {}
            })?;

        Ok((prev_root, new_root))
    }

    // * =================================================================
    // * RESTORE STATE

    pub fn restore_state(&mut self, transactions: Vec<Map<String, Value>>) {
        // println!("Restoring state from {:?} transactions", transactions);

        let mut n_deposits = 0;
        let mut n_withdrawals = 0;
        for transaction in transactions {
            let transaction_type = transaction
                .get("transaction_type")
                .unwrap()
                .as_str()
                .unwrap();

            match transaction_type {
                "deposit" => {
                    let deposit_notes = transaction
                        .get("deposit")
                        .unwrap()
                        .get("notes")
                        .unwrap()
                        .as_array()
                        .unwrap();

                    restore_deposit_update(
                        &self.state_tree,
                        &self.updated_state_hashes,
                        deposit_notes,
                    );

                    n_deposits += 1;
                }
                "withdrawal" => {
                    let withdrawal_notes_in = transaction
                        .get("withdrawal")
                        .unwrap()
                        .get("notes_in")
                        .unwrap()
                        .as_array()
                        .unwrap();
                    let refund_note = transaction.get("withdrawal").unwrap().get("refund_note");

                    restore_withdrawal_update(
                        &self.state_tree,
                        &self.updated_state_hashes,
                        withdrawal_notes_in,
                        refund_note,
                    );

                    n_withdrawals += 1;
                }
                "swap" => {
                    // * Order a ------------------------

                    restore_spot_order_execution(
                        &self.state_tree,
                        &self.updated_state_hashes,
                        &transaction,
                        true,
                    );

                    // * Order b ------------------------

                    restore_spot_order_execution(
                        &self.state_tree,
                        &self.updated_state_hashes,
                        &transaction,
                        false,
                    );

                    self.running_tx_count += 1;
                }
                "perpetual_swap" => {
                    // * Order a ------------------------
                    restore_perp_order_execution(
                        &self.state_tree,
                        &self.updated_state_hashes,
                        &self.perpetual_partial_fill_tracker,
                        &transaction,
                        true,
                    );

                    // * Order b ------------------------
                    restore_perp_order_execution(
                        &self.state_tree,
                        &self.updated_state_hashes,
                        &self.perpetual_partial_fill_tracker,
                        &transaction,
                        false,
                    );

                    self.running_tx_count += 1;
                }
                "liquidation_order" => restore_liquidation_order_execution(
                    &self.state_tree,
                    &self.updated_state_hashes,
                    &transaction,
                ),
                "margin_change" => restore_margin_update(
                    &self.state_tree,
                    &self.updated_state_hashes,
                    &transaction,
                ),
                "note_split" => {
                    restore_note_split(&self.state_tree, &self.updated_state_hashes, &transaction)
                }
                "open_order_tab" => {
                    restore_open_order_tab(
                        &self.state_tree,
                        &self.updated_state_hashes,
                        &transaction,
                    );
                }
                "close_order_tab" => restore_close_order_tab(
                    &self.state_tree,
                    &self.updated_state_hashes,
                    &transaction,
                ),
                "onchain_register_mm" => {
                    restore_register_mm(&self.state_tree, &self.updated_state_hashes, &transaction)
                }
                "add_liquidity" => restore_add_liquidity(
                    &self.state_tree,
                    &self.updated_state_hashes,
                    &transaction,
                ),
                "remove_liquidity" => restore_remove_liquidity(
                    &self.state_tree,
                    &self.updated_state_hashes,
                    &transaction,
                ),
                _ => {
                    panic!("Invalid transaction type");
                }
            }
        }

        let mut storage = self.main_storage.lock();
        storage.n_deposits = n_deposits;
        storage.n_withdrawals = n_withdrawals;
        drop(storage);
    }

    // * FUNDING CALCULATIONS * //

    pub fn per_minute_funding_updates(&mut self, funding_update: FundingUpdateMessage) {
        let mut running_sums: Vec<(u32, i64)> = Vec::new();
        for tup in self.running_funding_tick_sums.drain() {
            running_sums.push(tup);
        }

        for (token, sum) in running_sums {
            let index_price = self.latest_index_price.get(&token).unwrap().clone();

            if !funding_update.impact_prices.contains_key(&token) {
                continue;
            };
            let (impact_bid, impact_ask) = funding_update.impact_prices.get(&token).unwrap();
            let new_sum =
                _per_minute_funding_update_inner(*impact_bid, *impact_ask, sum, index_price);

            self.running_funding_tick_sums.insert(token, new_sum);
        }

        self.current_funding_count += 1;

        if self.current_funding_count == 480 {
            // Do we want 1 or 8 hours
            let fundings = _calculate_funding_rates(&mut self.running_funding_tick_sums);

            for (token, funding) in fundings.iter() {
                self.funding_rates.get_mut(token).unwrap().push(*funding);
                let price = self.latest_index_price.get(token).unwrap().clone();
                self.funding_prices.get_mut(token).unwrap().push(price);
            }

            self.current_funding_idx += 1;

            // Reinitialize the funding tick sums
            self.current_funding_count = 0;
            _init_empty_tokens_map::<i64>(&mut self.running_funding_tick_sums);

            let storage = self.main_storage.lock();
            storage.store_funding_info(
                &self.funding_rates,
                &self.funding_prices,
                &self.current_funding_idx,
                &self.min_funding_idxs.lock(),
            );
            drop(storage);
        }
    }

    // * PRICE FUNCTIONS * //

    pub fn update_index_prices(
        &mut self,
        oracle_updates: Vec<OracleUpdate>,
    ) -> Result<(), OracleUpdateError> {
        // Oracle prices received from the oracle provider (e.g. Chainlink, Pontis, Stork)

        // Todo: check signatures only if the price is more/less then the max/min price this batch
        // Todo: Should also check signatures (at least a few) if the price deviates from the previous price by more than some threshold

        // TODO: VERIFY TIMESTAMP OF ORACLE UPDATE !!!!!!!!!!!!!!!!!!!!!!!!!!!

        for mut update in oracle_updates {
            let token = update.token;
            let mut median = update.median_price();

            if self.min_index_price_data.get(&update.token).unwrap().0 == 0 {
                update.verify_update()?;
                median = update.median_price();

                self.latest_index_price.insert(token, median);

                self.min_index_price_data
                    .insert(update.token, (median, update.clone()));

                if self.max_index_price_data.get(&token).unwrap().0 == 0 {
                    self.max_index_price_data.insert(token, (median, update));
                }
            } else if median < self.min_index_price_data.get(&update.token).unwrap().0 {
                // ? This disregards the invalid observations and just uses the valid ones to get the median
                update.verify_update()?;
                median = update.median_price();

                if median >= self.min_index_price_data.get(&update.token).unwrap().0 {
                    self.latest_index_price.insert(token, median);
                    continue;
                }

                self.min_index_price_data
                    .insert(update.token, (median, update));

                //
            } else if median > self.max_index_price_data.get(&update.token).unwrap().0 {
                update.verify_update()?;
                median = update.median_price();

                if median <= self.max_index_price_data.get(&update.token).unwrap().0 {
                    self.latest_index_price.insert(token, median);
                    continue;
                }

                self.max_index_price_data
                    .insert(update.token, (median, update));
            }

            self.latest_index_price.insert(token, median);
        }

        self.running_index_price_count += 1;

        if self.running_index_price_count == 10 {
            let main_storage = self.main_storage.lock();
            main_storage.store_price_data(
                &self.latest_index_price,
                &self.min_index_price_data,
                &self.max_index_price_data,
            );
            drop(main_storage);
        }

        Ok(())
    }

    pub fn get_index_price(&self, token: u32) -> u64 {
        // returns latest oracle price

        return self.latest_index_price.get(&token).unwrap().clone();
    }

    // * RESET * //
    fn reset_batch(&mut self) {
        _init_empty_tokens_map::<(u64, OracleUpdate)>(&mut self.min_index_price_data);
        _init_empty_tokens_map::<(u64, OracleUpdate)>(&mut self.max_index_price_data);
        // ? Funding is seperate from batch execution so it is not reset
        // ? min_funding_idxs is the exception since it's reletive to the batch
        let mut min_funding_idxs = self.min_funding_idxs.lock();
        min_funding_idxs.clear();
        _init_empty_tokens_map::<u32>(&mut min_funding_idxs);

        self.running_tx_count = 0;
    }
}

//

//

//

//
