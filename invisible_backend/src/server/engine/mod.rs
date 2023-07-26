use firestore_db_and_auth::ServiceSession;
use parking_lot::Mutex;
use serde_json::Value;
use std::{
    collections::HashMap,
    sync::Arc,
    thread::{JoinHandle, ThreadId},
    time::Instant,
};

use self::{
    onchain_interaction::{execute_deposit_inner, execute_withdrawal_inner},
    order_executions::{
        submit_limit_order_inner, submit_liquidation_order_inner, submit_perpetual_order_inner,
    },
    order_interactions::{amend_order_inner, cancel_order_inner},
};

use super::grpc::{ChangeMarginMessage, GrpcMessage, GrpcTxResponse, MessageType};
use super::{
    grpc::{
        engine_proto::{engine_server::Engine, CloseOrderTabRes, OpenOrderTabRes},
        OrderTabActionMessage,
    },
    server_helpers::WsConnectionsMap,
};
use super::{
    grpc::{
        engine_proto::{
            ActiveOrder, ActivePerpOrder, AmendOrderRequest, AmendOrderResponse, BookEntry,
            CancelOrderMessage, CancelOrderResponse, CloseOrderTabReq, DepositMessage,
            DepositResponse, EmptyReq, FinalizeBatchResponse, FundingInfo, FundingReq, FundingRes,
            GrpcNote, GrpcOrderTab, LimitOrderMessage, LiquidationOrderMessage,
            LiquidationOrderResponse, LiquidityReq, LiquidityRes, MarginChangeReq, MarginChangeRes,
            OpenOrderTabReq, OracleUpdateReq, OrderResponse, OrdersReq, OrdersRes,
            PerpOrderMessage, RestoreOrderBookMessage, SplitNotesReq, SplitNotesRes,
            SpotOrderRestoreMessage, StateInfoReq, StateInfoRes, SuccessResponse,
            WithdrawalMessage,
        },
        OrderTabActionResponse,
    },
    server_helpers::engine_helpers::{handle_margin_change_repsonse, handle_split_notes_repsonse},
};
use crate::{
    matching_engine::{
        domain::{Order, OrderSide as OBOrderSide},
        orderbook::OrderBook,
    },
    perpetual::PositionEffectType,
    transaction_batch::tx_batch_structs::OracleUpdate,
    trees::superficial_tree::SuperficialTree,
    utils::{
        errors::send_funding_error_reply,
        storage::{BackupStorage, MainStorage},
    },
};
use crate::{
    perpetual::perp_helpers::perp_rollback::PerpRollbackInfo,
    utils::errors::{send_close_tab_error_reply, send_open_tab_error_reply},
};

use crate::transactions::transaction_helpers::rollbacks::RollbackInfo;

use crate::utils::{
    errors::{
        send_liquidity_error_reply, send_margin_change_error_reply, send_oracle_update_error_reply,
        send_split_notes_error_reply,
    },
    notes::Note,
};

use tokio::sync::{
    mpsc::Sender as MpscSender,
    oneshot::{self, Sender as OneshotSender},
    Mutex as TokioMutex, Semaphore,
};
use tokio::task::JoinHandle as TokioJoinHandle;
use tonic::{Request, Response, Status};

mod onchain_interaction;
mod order_executions;
mod order_interactions;

// TODO: ALL OPERATIONS SHOULD START A THREAD INCASE SOMETHING FAILS WE CAN CONTINUE ON

// #[derive(Debug)]
pub struct EngineService {
    pub mpsc_tx: MpscSender<(GrpcMessage, OneshotSender<GrpcTxResponse>)>,
    pub session: Arc<Mutex<ServiceSession>>,
    //
    pub main_storage: Arc<Mutex<MainStorage>>,
    pub backup_storage: Arc<Mutex<BackupStorage>>,
    pub swap_output_json: Arc<Mutex<Vec<serde_json::Map<String, Value>>>>,
    //
    pub state_tree: Arc<Mutex<SuperficialTree>>,
    pub perp_state_tree: Arc<Mutex<SuperficialTree>>,
    //
    pub partial_fill_tracker: Arc<Mutex<HashMap<u64, (Option<Note>, u64)>>>,
    pub perpetual_partial_fill_tracker: Arc<Mutex<HashMap<u64, (Option<Note>, u64, u64)>>>,
    //
    pub rollback_safeguard: Arc<Mutex<HashMap<ThreadId, RollbackInfo>>>,
    pub perp_rollback_safeguard: Arc<Mutex<HashMap<ThreadId, PerpRollbackInfo>>>,
    //
    pub order_books: HashMap<u16, Arc<TokioMutex<OrderBook>>>,
    pub perp_order_books: HashMap<u16, Arc<TokioMutex<OrderBook>>>,
    //
    pub ws_connections: Arc<TokioMutex<WsConnectionsMap>>,
    pub privileged_ws_connections: Arc<TokioMutex<Vec<u64>>>,
    //
    pub semaphore: Semaphore,
    pub is_paused: Arc<TokioMutex<bool>>,
}

// #[tokio::]
#[tonic::async_trait]
impl Engine for EngineService {
    async fn submit_limit_order(
        &self,
        request: Request<LimitOrderMessage>,
    ) -> Result<Response<OrderResponse>, Status> {
        return submit_limit_order_inner(
            &self.mpsc_tx,
            &self.session,
            &self.main_storage,
            &self.backup_storage,
            &self.swap_output_json,
            &self.state_tree,
            &self.rollback_safeguard,
            &self.order_books,
            &self.ws_connections,
            &self.privileged_ws_connections,
            &self.semaphore,
            &self.is_paused,
            request,
        )
        .await;
    }

    //
    // * ===================================================================================================================================
    //

    async fn submit_perpetual_order(
        &self,
        request: Request<PerpOrderMessage>,
    ) -> Result<Response<OrderResponse>, Status> {
        return submit_perpetual_order_inner(
            &self.mpsc_tx,
            &self.session,
            &self.main_storage,
            &self.backup_storage,
            &self.swap_output_json,
            &self.state_tree,
            &self.perp_state_tree,
            &self.perp_rollback_safeguard,
            &self.perp_order_books,
            &self.ws_connections,
            &self.privileged_ws_connections,
            &self.semaphore,
            &self.is_paused,
            request,
        )
        .await;
    }

    //
    // * ===================================================================================================================================
    //

    async fn submit_liquidation_order(
        &self,
        request: Request<LiquidationOrderMessage>,
    ) -> Result<Response<LiquidationOrderResponse>, Status> {
        return submit_liquidation_order_inner(
            &self.mpsc_tx,
            &self.main_storage,
            &self.swap_output_json,
            &self.perp_order_books,
            &self.semaphore,
            &self.is_paused,
            request,
        )
        .await;
    }

    //
    // * ===================================================================================================================================
    //

    async fn cancel_order(
        &self,
        request: Request<CancelOrderMessage>,
    ) -> Result<Response<CancelOrderResponse>, Status> {
        return cancel_order_inner(
            &self.partial_fill_tracker,
            &self.perpetual_partial_fill_tracker,
            &self.order_books,
            &self.perp_order_books,
            request,
        )
        .await;
    }

    //
    // * ===================================================================================================================================
    //

    async fn amend_order(
        &self,
        request: Request<AmendOrderRequest>,
    ) -> Result<Response<AmendOrderResponse>, Status> {
        return amend_order_inner(
            &self.mpsc_tx,
            &self.session,
            &self.main_storage,
            &self.backup_storage,
            &self.swap_output_json,
            &self.rollback_safeguard,
            &self.perp_rollback_safeguard,
            &self.order_books,
            &self.perp_order_books,
            &self.ws_connections,
            &self.privileged_ws_connections,
            request,
        )
        .await;
    }

    //
    // * ===================================================================================================================================
    //

    async fn execute_deposit(
        &self,
        request: Request<DepositMessage>,
    ) -> Result<Response<DepositResponse>, Status> {
        return execute_deposit_inner(
            &self.mpsc_tx,
            &self.main_storage,
            &self.swap_output_json,
            &self.semaphore,
            &self.is_paused,
            request,
        )
        .await;
    }

    //
    // * ===================================================================================================================================
    //

    async fn execute_withdrawal(
        &self,
        request: Request<WithdrawalMessage>,
    ) -> Result<Response<SuccessResponse>, Status> {
        return execute_withdrawal_inner(
            &self.mpsc_tx,
            &self.main_storage,
            &self.swap_output_json,
            &self.semaphore,
            &self.is_paused,
            request,
        )
        .await;
    }

    //
    // * ===================================================================================================================================
    //

    async fn get_liquidity(
        &self,
        request: Request<LiquidityReq>,
    ) -> Result<Response<LiquidityRes>, Status> {
        tokio::task::yield_now().await;

        let req: LiquidityReq = request.into_inner();

        let order_book_m: &Arc<TokioMutex<OrderBook>>;

        if req.is_perp {
            if !self.perp_order_books.contains_key(&(req.market_id as u16)) {
                return send_liquidity_error_reply(
                    "No market found for given base and quote token".to_string(),
                );
            }

            order_book_m = self.perp_order_books.get(&(req.market_id as u16)).unwrap();
        } else {
            if !self.order_books.contains_key(&(req.market_id as u16)) {
                return send_liquidity_error_reply(
                    "No market found for given base and quote token".to_string(),
                );
            }

            // ? Get the relevant orderbook from the market_id
            order_book_m = self.order_books.get(&(req.market_id as u16)).unwrap();
        }

        let order_book = order_book_m.lock().await;

        let bid_queue = order_book
            .bid_queue
            .visualize()
            .into_iter()
            .map(|(p, qt, ts, _oid)| BookEntry {
                price: p,
                amount: qt,
                timestamp: ts,
            })
            .collect::<Vec<BookEntry>>();
        let ask_queue = order_book
            .ask_queue
            .visualize()
            .into_iter()
            .map(|(p, qt, ts, _oid)| BookEntry {
                price: p,
                amount: qt,
                timestamp: ts,
            })
            .collect::<Vec<BookEntry>>();

        drop(order_book);

        let reply = LiquidityRes {
            successful: true,
            ask_queue,
            bid_queue,
            error_message: "".to_string(),
        };

        return Ok(Response::new(reply));
    }

    //
    // * ===================================================================================================================================
    //

    async fn get_orders(&self, request: Request<OrdersReq>) -> Result<Response<OrdersRes>, Status> {
        tokio::task::yield_now().await;

        let req: OrdersReq = request.into_inner();

        let mut bad_order_ids: Vec<u64> = Vec::new();
        let mut active_orders: Vec<ActiveOrder> = Vec::new();
        let mut pfr_notes: Vec<Note> = Vec::new();

        for order_id in req.order_ids {
            let market_id = order_id as u16;

            if !self.order_books.contains_key(&market_id) {
                // ? order is non-existent or invalid
                bad_order_ids.push(order_id);

                continue;
            }

            let order_book = self.order_books.get(&market_id).unwrap().lock().await;
            let wrapper_ = order_book.get_order(order_id);

            if let Some(wrapper) = wrapper_ {
                let order_side = wrapper.order_side;
                let price = wrapper.order.get_price(order_side, None);
                let qty_left = wrapper.qty_left;
                if let Order::Spot(limit_order) = &wrapper.order {
                    let base_asset: u64;
                    let quote_asset: u64;
                    if order_side == OBOrderSide::Bid {
                        base_asset = limit_order.token_received;
                        quote_asset = limit_order.token_spent;
                    } else {
                        base_asset = limit_order.token_spent;
                        quote_asset = limit_order.token_received
                    }

                    let notes_in: Vec<GrpcNote>;
                    let refund_note;
                    if limit_order.spot_note_info.is_some() {
                        let notes_info = limit_order.spot_note_info.as_ref().unwrap();

                        notes_in = notes_info
                            .notes_in
                            .iter()
                            .map(|n| GrpcNote::from(n.clone()))
                            .collect();

                        refund_note = if notes_info.refund_note.is_some() {
                            Some(GrpcNote::from(
                                notes_info.refund_note.as_ref().unwrap().clone(),
                            ))
                        } else {
                            None
                        };
                    } else {
                        notes_in = vec![];
                        refund_note = None;
                    };

                    let order_tab = if limit_order.order_tab.is_some() {
                        let lock = limit_order.order_tab.as_ref().unwrap().lock();
                        Some(GrpcOrderTab::from(lock.clone()))
                    } else {
                        None
                    };

                    let active_order = ActiveOrder {
                        order_id: limit_order.order_id,
                        expiration_timestamp: limit_order.expiration_timestamp,
                        base_asset,
                        quote_asset,
                        order_side: order_side == OBOrderSide::Bid,
                        fee_limit: limit_order.fee_limit,
                        price,
                        qty_left,
                        notes_in,
                        refund_note,
                        order_tab,
                    };

                    active_orders.push(active_order);
                }
            } else {
                bad_order_ids.push(order_id);
            }
            drop(order_book);

            let partial_fill_tracker_m = self.partial_fill_tracker.lock();
            let pfr_info = partial_fill_tracker_m.get(&(order_id % 2_u64.pow(32)));
            if pfr_info.is_some() && pfr_info.unwrap().0.is_some() {
                pfr_notes.push(pfr_info.unwrap().0.as_ref().unwrap().clone());
            }
            drop(partial_fill_tracker_m);
        }

        let mut bad_perp_order_ids: Vec<u64> = Vec::new();
        let mut active_perp_orders: Vec<ActivePerpOrder> = Vec::new();

        for order_id in req.perp_order_ids {
            let market_id = order_id as u16;

            if !self.perp_order_books.contains_key(&market_id) {
                // ? order is non-existent or invalid
                bad_order_ids.push(order_id);

                continue;
            }

            let order_book = self.perp_order_books.get(&market_id).unwrap().lock().await;
            let wrapper = order_book.get_order(order_id);

            if let Some(wrapper) = wrapper {
                let order_side = wrapper.order_side;
                let price = wrapper.order.get_price(order_side, None);
                let qty_left = wrapper.qty_left;
                if let Order::Perp(perp_order) = &wrapper.order {
                    let position_effect_type = match perp_order.position_effect_type {
                        PositionEffectType::Open => 0,
                        PositionEffectType::Modify => 1,
                        PositionEffectType::Close => 2,
                    };

                    let initial_margin: u64;
                    let notes_in: Vec<GrpcNote>;
                    let refund_note: Option<GrpcNote>;
                    let position_address: String;
                    if position_effect_type == 0 {
                        let open_order_fields = perp_order.open_order_fields.clone().unwrap();
                        initial_margin = open_order_fields.initial_margin;
                        notes_in = open_order_fields
                            .notes_in
                            .into_iter()
                            .map(|n| GrpcNote::from(n))
                            .collect();
                        refund_note = if open_order_fields.refund_note.is_some() {
                            Some(GrpcNote::from(open_order_fields.refund_note.unwrap()))
                        } else {
                            None
                        };
                        position_address = "".to_string();
                    } else {
                        initial_margin = 0;
                        notes_in = vec![];
                        refund_note = None;
                        position_address = perp_order
                            .position
                            .clone()
                            .unwrap()
                            .position_address
                            .to_string();
                    }

                    let active_order = ActivePerpOrder {
                        order_id: perp_order.order_id,
                        expiration_timestamp: perp_order.expiration_timestamp,
                        synthetic_token: perp_order.synthetic_token,
                        position_effect_type,
                        order_side: order_side == OBOrderSide::Bid,
                        fee_limit: perp_order.fee_limit,
                        price,
                        qty_left,
                        initial_margin,
                        notes_in,
                        refund_note,
                        position_address,
                    };

                    active_perp_orders.push(active_order)
                }
            } else {
                bad_perp_order_ids.push(order_id);
            }

            let perpetual_partial_fill_tracker_m = self.perpetual_partial_fill_tracker.lock();
            let pfr_info = perpetual_partial_fill_tracker_m.get(&order_id);
            if let Some(pfr_info) = pfr_info {
                if let Some(pfr_note) = &pfr_info.0 {
                    pfr_notes.push(pfr_note.clone());
                }
            }
            drop(perpetual_partial_fill_tracker_m);
        }

        let reply = OrdersRes {
            bad_order_ids,
            orders: active_orders,
            bad_perp_order_ids,
            perp_orders: active_perp_orders,
            pfr_notes: pfr_notes.into_iter().map(|n| GrpcNote::from(n)).collect(),
        };

        return Ok(Response::new(reply));
    }

    //
    // * ===================================================================================================================================
    //

    async fn restore_orderbook(
        &self,
        request: Request<RestoreOrderBookMessage>,
    ) -> Result<Response<SuccessResponse>, Status> {
        tokio::task::yield_now().await;

        let req: RestoreOrderBookMessage = request.into_inner();

        let spot_order_messages: Vec<SpotOrderRestoreMessage> = req.spot_order_restore_messages;

        for message in spot_order_messages {
            let market_id = message.market_id as u16;

            let bid_order_restore_messages = message.bid_order_restore_messages;
            let ask_order_restore_messages = message.ask_order_restore_messages;

            let order_book_ = self.order_books.get(&market_id);
            if let Some(order_book) = order_book_ {
                let mut order_book = order_book.lock().await;

                order_book.restore_spot_order_book(
                    bid_order_restore_messages,
                    ask_order_restore_messages,
                );
            }
        }

        // ? ===========================================================================================

        let perp_order_messages = req.perp_order_restore_messages;

        for message in perp_order_messages {
            let market_id = message.market_id as u16;

            let bid_order_restore_messages = message.bid_order_restore_messages;
            let ask_order_restore_messages = message.ask_order_restore_messages;

            let order_book_ = self.perp_order_books.get(&market_id);
            if let Some(order_book) = order_book_ {
                let mut order_book = order_book.lock().await;

                order_book.restore_perp_order_book(
                    bid_order_restore_messages,
                    ask_order_restore_messages,
                );
            }
        }

        let reply = SuccessResponse {
            successful: true,
            error_message: "".to_string(),
        };

        return Ok(Response::new(reply));
    }

    //
    // * ===================================================================================================================================
    //

    async fn split_notes(
        &self,
        req: Request<SplitNotesReq>,
    ) -> Result<Response<SplitNotesRes>, Status> {
        let _permit = self.semaphore.acquire().await.unwrap();

        let lock = self.is_paused.lock().await;
        drop(lock);

        tokio::task::yield_now().await;

        let control_mpsc_tx = self.mpsc_tx.clone();
        let swap_output_json = self.swap_output_json.clone();
        let main_storage = self.main_storage.clone();

        let handle = tokio::spawn(async move {
            let req: SplitNotesReq = req.into_inner();

            let mut notes_in: Vec<Note> = Vec::new();
            for n in req.notes_in.iter() {
                let note = Note::try_from(n.clone());

                if let Ok(n) = note {
                    notes_in.push(n);
                } else {
                    return send_split_notes_error_reply("Invalid note".to_string());
                }
            }
            let new_note: Note;
            let mut refund_note: Option<Note> = None;
            if req.note_out.is_some() {
                let note_out = Note::try_from(req.note_out.unwrap());

                if let Ok(n) = note_out {
                    new_note = n;
                } else {
                    return send_split_notes_error_reply("Invalid note".to_string());
                }
            } else {
                return send_split_notes_error_reply("Invalid note".to_string());
            }
            if req.refund_note.is_some() {
                let refund_note_ = Note::try_from(req.refund_note.unwrap());

                if let Ok(n) = refund_note_ {
                    refund_note = Some(n);
                } else {
                    return send_split_notes_error_reply("Invalid note".to_string());
                }
            }

            let handle: TokioJoinHandle<GrpcTxResponse> = tokio::spawn(async move {
                let (resp_tx, resp_rx) = oneshot::channel();

                let mut grpc_message = GrpcMessage::new();
                grpc_message.msg_type = MessageType::SplitNotes;
                grpc_message.split_notes_message = Some((notes_in, new_note, refund_note));

                control_mpsc_tx
                    .send((grpc_message, resp_tx))
                    .await
                    .ok()
                    .unwrap();

                return resp_rx.await.unwrap();
            });

            return handle_split_notes_repsonse(handle, &swap_output_json, &main_storage).await;
        });

        match handle.await {
            Ok(res) => {
                return res;
            }
            Err(_e) => {
                return send_split_notes_error_reply(
                    "Unexpected error occured splitting notes".to_string(),
                );
            }
        }
    }

    //
    // * ===================================================================================================================================
    //

    async fn change_position_margin(
        &self,
        req: Request<MarginChangeReq>,
    ) -> Result<Response<MarginChangeRes>, Status> {
        let _permit = self.semaphore.acquire().await.unwrap();

        let lock = self.is_paused.lock().await;
        drop(lock);

        tokio::task::yield_now().await;

        let control_mpsc_tx = self.mpsc_tx.clone();
        let swap_output_json = self.swap_output_json.clone();
        let main_storage = self.main_storage.clone();
        let perp_order_books = self.perp_order_books.clone();
        let ws_connections = self.ws_connections.clone();

        let handle = tokio::spawn(async move {
            let req: MarginChangeReq = req.into_inner();

            let change_margin_message = ChangeMarginMessage::try_from(req).ok();

            if change_margin_message.is_none() {
                return send_margin_change_error_reply("Invalid change margin message".to_string());
            }

            let user_id = change_margin_message.as_ref().unwrap().user_id;

            let handle: TokioJoinHandle<GrpcTxResponse> = tokio::spawn(async move {
                let (resp_tx, resp_rx) = oneshot::channel();

                let mut grpc_message = GrpcMessage::new();
                grpc_message.msg_type = MessageType::MarginChange;
                grpc_message.change_margin_message = change_margin_message;

                control_mpsc_tx
                    .send((grpc_message, resp_tx))
                    .await
                    .ok()
                    .unwrap();

                return resp_rx.await.unwrap();
            });

            return handle_margin_change_repsonse(
                handle,
                user_id,
                &swap_output_json,
                &main_storage,
                &perp_order_books,
                &ws_connections,
            )
            .await;
        });

        match handle.await {
            Ok(res) => {
                return res;
            }
            Err(_e) => {
                println!("Unexpected error occured updating margin");

                return send_margin_change_error_reply(
                    "Unexpected error occured updating margin".to_string(),
                );
            }
        }
    }

    //
    // * ===================================================================================================================================
    //

    async fn open_order_tab(
        &self,
        req: Request<OpenOrderTabReq>,
    ) -> Result<Response<OpenOrderTabRes>, Status> {
        tokio::task::yield_now().await;

        let req: OpenOrderTabReq = req.into_inner();

        let transaction_mpsc_tx = self.mpsc_tx.clone();

        let handle: TokioJoinHandle<JoinHandle<OrderTabActionResponse>> =
            tokio::spawn(async move {
                let (resp_tx, resp_rx) = oneshot::channel();

                let mut grpc_message = GrpcMessage::new();
                grpc_message.msg_type = MessageType::OrderTabAction;
                grpc_message.order_tab_action_message = Some(OrderTabActionMessage {
                    open_order_tab_req: Some(req),
                    close_order_tab_req: None,
                });

                transaction_mpsc_tx
                    .send((grpc_message, resp_tx))
                    .await
                    .ok()
                    .unwrap();
                let res = resp_rx.await.unwrap();

                return res.order_tab_action_response.unwrap();
            });

        let order_action_handle = handle.await.unwrap();
        let order_action_response = order_action_handle.join();

        match order_action_response {
            Ok(res) => match res.new_order_tab.unwrap() {
                Ok(order_tab) => {
                    let order_tab = GrpcOrderTab::from(order_tab);
                    let reply = OpenOrderTabRes {
                        successful: true,
                        error_message: "".to_string(),
                        order_tab: Some(order_tab),
                    };

                    return Ok(Response::new(reply));
                }
                Err(err) => {
                    println!("Error in open order tab execution: {}", err);

                    return send_open_tab_error_reply(
                        "Error occurred in the open order tab execution".to_string() + &err,
                    );
                }
            },
            Err(_e) => {
                println!("Unknown Error in open order tab execution");

                return send_open_tab_error_reply(
                    "Unknown Error occurred in the open order tab execution".to_string(),
                );
            }
        }
    }

    //
    // * ===================================================================================================================================
    //

    async fn close_order_tab(
        &self,
        req: Request<CloseOrderTabReq>,
    ) -> Result<Response<CloseOrderTabRes>, Status> {
        tokio::task::yield_now().await;

        let req: CloseOrderTabReq = req.into_inner();

        let transaction_mpsc_tx = self.mpsc_tx.clone();

        let handle: TokioJoinHandle<JoinHandle<OrderTabActionResponse>> =
            tokio::spawn(async move {
                let (resp_tx, resp_rx) = oneshot::channel();

                let mut grpc_message = GrpcMessage::new();
                grpc_message.msg_type = MessageType::OrderTabAction;
                grpc_message.order_tab_action_message = Some(OrderTabActionMessage {
                    open_order_tab_req: None,
                    close_order_tab_req: Some(req),
                });

                transaction_mpsc_tx
                    .send((grpc_message, resp_tx))
                    .await
                    .ok()
                    .unwrap();
                let res = resp_rx.await.unwrap();

                return res.order_tab_action_response.unwrap();
            });

        let order_action_handle = handle.await.unwrap();
        let order_action_response = order_action_handle.join();

        match order_action_response {
            Ok(res) => match res.return_notes.unwrap() {
                Ok((base_r_note, quote_r_note)) => {
                    let base_return_note = Some(GrpcNote::from(base_r_note));
                    let quote_return_note = Some(GrpcNote::from(quote_r_note));
                    let reply = CloseOrderTabRes {
                        successful: true,
                        error_message: "".to_string(),
                        base_return_note,
                        quote_return_note,
                    };

                    return Ok(Response::new(reply));
                }
                Err(err) => {
                    println!("Error in close order tab execution: {}", err);

                    return send_close_tab_error_reply(
                        "Error occurred in the close order tab execution".to_string() + &err,
                    );
                }
            },
            Err(_e) => {
                println!("Unknown Error in close order tab execution");

                return send_close_tab_error_reply(
                    "Unknown Error occurred in the close order tab execution".to_string(),
                );
            }
        }
    }

    //
    // * ===================================================================================================================================
    //

    async fn finalize_batch(
        &self,
        _: Request<EmptyReq>,
    ) -> Result<Response<FinalizeBatchResponse>, Status> {
        let _permit = self.semaphore.acquire().await.unwrap();

        let lock = self.is_paused.lock().await;

        let now = Instant::now();

        tokio::task::yield_now().await;

        let transaction_mpsc_tx = self.mpsc_tx.clone();
        let handle = tokio::spawn(async move {
            let res: TokioJoinHandle<GrpcTxResponse> = tokio::spawn(async move {
                let (resp_tx, resp_rx) = oneshot::channel();

                let mut grpc_message = GrpcMessage::new();
                grpc_message.msg_type = MessageType::FinalizeBatch;

                transaction_mpsc_tx
                    .send((grpc_message, resp_tx))
                    .await
                    .ok()
                    .unwrap();
                let res = resp_rx.await.unwrap();

                return res;
            });

            println!("time: {:?}", now.elapsed());

            if let Ok(res) = res.await {
                if res.successful {
                    // OK

                    println!("batch finalized sucessfuly");
                } else {
                    println!("batch finalization failed");
                }
            } else {
                println!("batch finalization failed");
            }
        });

        drop(lock);

        match handle.await {
            Ok(_) => {
                return Ok(Response::new(FinalizeBatchResponse {}));
            }
            Err(_e) => {
                return Ok(Response::new(FinalizeBatchResponse {}));
            }
        }
    }

    //
    // * ===================================================================================================================================
    //

    async fn update_index_price(
        &self,
        request: Request<OracleUpdateReq>,
    ) -> Result<Response<SuccessResponse>, Status> {
        tokio::task::yield_now().await;

        let transaction_mpsc_tx = self.mpsc_tx.clone();
        let handle = tokio::spawn(async move {
            let req: OracleUpdateReq = request.into_inner();

            let mut oracle_updates: Vec<OracleUpdate> = Vec::new();
            for update in req.oracle_price_updates {
                match OracleUpdate::try_from(update) {
                    Ok(oracle_update) => oracle_updates.push(oracle_update),
                    Err(err) => {
                        return send_oracle_update_error_reply(format!(
                            "Error occurred while parsing the oracle update: {:?}",
                            err.current_context()
                        ));
                    }
                }
            }

            let execution_handle: TokioJoinHandle<GrpcTxResponse> = tokio::spawn(async move {
                let (resp_tx, resp_rx) = oneshot::channel();

                let mut grpc_message = GrpcMessage::new();
                grpc_message.msg_type = MessageType::IndexPriceUpdate;
                grpc_message.price_update_message = Some(oracle_updates);

                transaction_mpsc_tx
                    .send((grpc_message, resp_tx))
                    .await
                    .ok()
                    .unwrap();

                return resp_rx.await.unwrap();
            });

            let grpc_res = execution_handle.await.unwrap();
            if grpc_res.successful {
                let reply = SuccessResponse {
                    successful: true,
                    error_message: "".to_string(),
                };

                return Ok(Response::new(reply));
            } else {
                println!("Error updating the index price");

                return send_oracle_update_error_reply(
                    "Error occurred while updating index price ".to_string(),
                );
            }
        });

        match handle.await {
            Ok(res) => {
                return res;
            }
            Err(_e) => {
                println!("Unknown Error in update index price");

                return send_oracle_update_error_reply(
                    "Unknown Error occurred while updating index price".to_string(),
                );
            }
        }
    }

    async fn get_state_info(
        &self,
        _: Request<StateInfoReq>,
    ) -> Result<Response<StateInfoRes>, Status> {
        tokio::task::yield_now().await;

        let state_tree = self.state_tree.lock();
        let spot_tree_leaves = state_tree
            .leaf_nodes
            .iter()
            .map(|x| x.to_string())
            .collect();
        let perp_state_tree = self.perp_state_tree.lock();
        let perp_tree_leaves = perp_state_tree
            .leaf_nodes
            .iter()
            .map(|x| x.to_string())
            .collect();
        drop(state_tree);
        drop(perp_state_tree);

        // let backup_storage = self.backup_storage.lock();
        // let (failed_position_additions, _failed_position_deletions) =
        //     backup_storage.read_positions();
        // let notes = backup_storage.read_notes();
        // drop(backup_storage);

        // let perp_state = self.perp_state_tree.lock();
        // for position in failed_position_additions {
        //     let leaf_hash = perp_state.get_leaf_by_index(position.index as u64);

        //     if position.hash == leaf_hash {
        //         if position.hash == position.hash_position() {

        //             // TODO
        //         }
        //     }
        // }

        let reply = StateInfoRes {
            state_tree: spot_tree_leaves,
            perpetual_state_tree: perp_tree_leaves,
        };

        return Ok(Response::new(reply));
    }

    async fn get_funding_info(
        &self,
        _: Request<FundingReq>,
    ) -> Result<Response<FundingRes>, Status> {
        tokio::task::yield_now().await;

        let control_mpsc_tx = self.mpsc_tx.clone();

        let handle: TokioJoinHandle<GrpcTxResponse> = tokio::spawn(async move {
            let (resp_tx, resp_rx) = oneshot::channel();

            let mut grpc_message = GrpcMessage::new();
            grpc_message.msg_type = MessageType::FundingUpdate;

            control_mpsc_tx
                .send((grpc_message, resp_tx))
                .await
                .ok()
                .unwrap();

            return resp_rx.await.unwrap();
        });

        if let Ok(grpc_res) = handle.await {
            match grpc_res.funding_info {
                Some((funding_rates, funding_prices)) => {
                    let mut fundings = Vec::new();
                    for token in funding_rates.keys() {
                        let rates = funding_rates.get(token).unwrap();
                        let prices = funding_prices.get(token).unwrap();

                        let funding_info = FundingInfo {
                            token: *token,
                            funding_rates: rates.clone(),
                            funding_prices: prices.clone(),
                        };

                        fundings.push(funding_info);
                    }

                    let reply = FundingRes {
                        successful: true,
                        fundings,
                        error_message: "".to_string(),
                    };

                    return Ok(Response::new(reply));
                }
                None => {
                    return send_funding_error_reply("failed to get funding info".to_string());
                }
            }
        } else {
            println!("Unknown error in get funding info");

            return send_funding_error_reply("failed to get funding info".to_string());
        }
    }
}
