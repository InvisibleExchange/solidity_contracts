use firestore_db_and_auth::ServiceSession;
use parking_lot::Mutex;
use serde_json::Value;
use std::{
    collections::HashMap,
    sync::Arc,
    thread::{JoinHandle, ThreadId},
    time::Instant,
};

use super::{
    grpc::engine::{
        AmendOrderRequest, AmendOrderResponse, BookEntry, DepositResponse, EmptyReq,
        FinalizeBatchResponse, FundingInfo, FundingReq, FundingRes, GrpcOrderTab, GrpcPerpPosition,
        LimitOrderMessage, LiquidationOrderMessage, LiquidationOrderResponse, LiquidityReq,
        LiquidityRes, OracleUpdateReq, OrderResponse, OrderTabReq, PerpOrderMessage,
        RestoreOrderBookMessage, SpotOrderRestoreMessage, StateInfoReq, StateInfoRes,
        SuccessResponse, WithdrawalMessage,
    },
    server_helpers::{
        amend_order_execution::{
            execute_perp_swaps_after_amend_order, execute_spot_swaps_after_amend_order,
        },
        engine_helpers::{
            handle_cancel_order_repsonse, handle_deposit_repsonse, handle_margin_change_repsonse,
            handle_split_notes_repsonse, handle_withdrawal_repsonse, store_output_json,
            verify_tab_existence,
        },
        perp_swap_execution::{
            process_and_execute_perp_swaps, process_perp_order_request, retry_failed_perp_swaps,
        },
        swap_execution::{
            await_swap_handles, process_and_execute_spot_swaps, process_limit_order_request,
            retry_failed_swaps,
        },
        PERP_MARKET_IDS,
    },
};
use super::{
    grpc::engine::{OrdersReq, OrdersRes},
    server_helpers::{get_market_id_and_order_side, WsConnectionsMap},
};
use super::{
    grpc::{
        engine::{
            ActiveOrder, ActivePerpOrder, CancelOrderMessage, CancelOrderResponse, GrpcNote,
            MarginChangeReq, MarginChangeRes, SplitNotesReq, SplitNotesRes,
        },
        ChangeMarginMessage,
    },
    server_helpers::engine_helpers::{
        verify_notes_existence, verify_position_existence, verify_signature_format,
    },
};
use crate::{
    matching_engine::orders::limit_order_cancel_request,
    perpetual::{perp_helpers::perp_rollback::PerpRollbackInfo, perp_order::PerpOrder},
};
use crate::{
    matching_engine::{
        domain::{Order, OrderSide as OBOrderSide},
        orderbook::OrderBook,
        orders::new_amend_order,
    },
    perpetual::{
        liquidations::{
            liquidation_engine::LiquidationSwap, liquidation_order::LiquidationOrder,
            liquidation_output::LiquidationResponse,
        },
        PositionEffectType,
    },
    transaction_batch::tx_batch_structs::OracleUpdate,
    trees::superficial_tree::SuperficialTree,
    utils::{
        errors::{
            send_amend_order_error_reply, send_funding_error_reply,
            send_liquidation_order_error_reply, PerpSwapExecutionError,
        },
        storage::{BackupStorage, MainStorage},
    },
};

use crate::transactions::{
    deposit::Deposit, limit_order::LimitOrder, transaction_helpers::rollbacks::RollbackInfo,
    withdrawal::Withdrawal,
};
use crate::utils::crypto_utils::Signature;
use crate::utils::{
    errors::{
        send_cancel_order_error_reply, send_deposit_error_reply, send_liquidity_error_reply,
        send_margin_change_error_reply, send_oracle_update_error_reply, send_order_error_reply,
        send_split_notes_error_reply, send_withdrawal_error_reply,
    },
    notes::Note,
};

use error_stack::Report;
use tokio::sync::{
    mpsc::Sender as MpscSender,
    oneshot::{self, Sender as OneshotSender},
    Mutex as TokioMutex, Semaphore,
};
use tokio::task::JoinHandle as TokioJoinHandle;
use tonic::{Request, Response, Status};

use super::grpc::{engine, GrpcMessage, GrpcTxResponse, MessageType};
use engine::{engine_server::Engine, DepositMessage};

// TODO: ALL OPERATIONS SHOULD START A THREAD INCASE SOMETHING FAILS WE CAN CONTINUE ON

// TODO: WE HAVE TO CHANGE THE INIT MARGIN FUNCTION IN THE CAIRO CODE SINCE WE CHANGED IT IN THE RUST CODE

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
        let _permit = self.semaphore.acquire().await.unwrap();

        let lock = self.is_paused.lock().await;
        drop(lock);

        tokio::task::yield_now().await;

        // let now = Instant::now();

        let req: LimitOrderMessage = request.into_inner();

        let user_id = req.user_id;
        let is_market: bool = req.is_market;

        // ? Verify the signature is defined and has a valid format
        let signature: Signature;
        match verify_signature_format(&req.signature) {
            Ok(sig) => signature = sig,
            Err(err) => {
                return send_order_error_reply(err);
            }
        }

        // ? Try to parse the grpc input as a LimitOrder
        let limit_order: LimitOrder;
        match LimitOrder::try_from(req) {
            Ok(lo) => limit_order = lo,
            Err(_e) => {
                return send_order_error_reply(
                    "Error unpacking the limit order (verify the format is correct)".to_string(),
                );
            }
        };

        // ? Try to get the market_id and order_side from the limit_order
        let res = get_market_id_and_order_side(limit_order.token_spent, limit_order.token_received);
        if res.is_none() {
            return send_order_error_reply("Market (token pair) not found".to_string());
        }
        let (market_id, side) = res.unwrap();

        if limit_order.spot_note_info.is_some() {
            // ? Verify the notes spent exist in the state tree
            if let Err(err_msg) = verify_notes_existence(
                &limit_order.spot_note_info.as_ref().unwrap().notes_in,
                &self.state_tree,
            ) {
                return send_order_error_reply(err_msg);
            }
        } else {
            if limit_order.order_tab.is_none() {
                return send_order_error_reply(
                    "Order tab is not defined for this limit order".to_string(),
                );
            }

            // ? Verify the order tab exist in the state tree
            if let Err(err_msg) =
                verify_tab_existence(&limit_order.order_tab.as_ref().unwrap(), &self.state_tree)
            {
                return send_order_error_reply(err_msg);
            }
        }

        let mut processed_res = process_limit_order_request(
            self.order_books.get(&market_id).clone().unwrap(),
            limit_order.clone(),
            side,
            signature.clone(),
            user_id,
            is_market,
            false,
            0,
            0,
            None,
        )
        .await;

        // This matches the orders and creates the swaps that can be executed
        let handles;
        let new_order_id;
        match process_and_execute_spot_swaps(
            &self.mpsc_tx,
            &self.rollback_safeguard,
            self.order_books.get(&market_id).clone().unwrap(),
            &self.session,
            &self.backup_storage,
            &mut processed_res,
        )
        .await
        {
            Ok((h, oid)) => {
                handles = h;
                new_order_id = oid;
            }
            Err(err) => {
                return send_order_error_reply(err);
            }
        };

        // this executes the swaps in parallel
        let retry_messages;
        match await_swap_handles(
            &self.ws_connections,
            &self.privileged_ws_connections,
            handles,
            user_id,
        )
        .await
        {
            Ok(rm) => retry_messages = rm,
            Err(e) => return send_order_error_reply(e),
        };

        if retry_messages.len() > 0 {
            if let Err(e) = retry_failed_swaps(
                &self.mpsc_tx,
                &self.rollback_safeguard,
                self.order_books.get(&market_id).clone().unwrap(),
                &self.session,
                &self.backup_storage,
                limit_order,
                side,
                signature,
                user_id,
                is_market,
                &self.ws_connections,
                &self.privileged_ws_connections,
                retry_messages,
                None,
            )
            .await
            {
                return send_order_error_reply(e);
            }
        }

        store_output_json(&self.swap_output_json, &self.main_storage);

        // Send a successul reply to the caller
        let reply = OrderResponse {
            successful: true,
            error_message: "".to_string(),
            order_id: new_order_id,
        };

        return Ok(Response::new(reply));
    }

    //
    // * ===================================================================================================================================
    //

    async fn submit_perpetual_order(
        &self,
        request: Request<PerpOrderMessage>,
    ) -> Result<Response<OrderResponse>, Status> {
        let _permit = self.semaphore.acquire().await.unwrap();

        let lock = self.is_paused.lock().await;
        drop(lock);

        tokio::task::yield_now().await;

        let req: PerpOrderMessage = request.into_inner();

        let user_id = req.user_id;
        let is_market: bool = req.is_market;

        // ? Verify the signature is defined and has a valid format
        let signature: Signature;
        match verify_signature_format(&req.signature) {
            Ok(sig) => signature = sig,
            Err(err) => {
                return send_order_error_reply(err);
            }
        }

        // ? Try to parse the grpc input as a LimitOrder
        let perp_order: PerpOrder;
        match PerpOrder::try_from(req) {
            Ok(po) => perp_order = po,
            Err(_e) => {
                return send_order_error_reply(
                    "Error unpacking the limit order (verify the format is correct)".to_string(),
                );
            }
        };

        // ? market for perpetuals can be just the synthetic token
        let market = PERP_MARKET_IDS.get(&perp_order.synthetic_token.to_string());
        if market.is_none() {
            return send_order_error_reply(
                "Market (token pair) does not exist for this token".to_string(),
            );
        }

        // ? Verify the notes spent and position modified exist in the state tree
        if perp_order.position_effect_type == PositionEffectType::Open {
            if let Err(err_msg) = verify_notes_existence(
                &perp_order.open_order_fields.as_ref().unwrap().notes_in,
                &self.state_tree,
            ) {
                return send_order_error_reply(err_msg);
            }
        } else {
            if let Err(err_msg) = verify_position_existence(
                &perp_order.position.as_ref().unwrap(),
                &self.perp_state_tree,
            ) {
                return send_order_error_reply(err_msg);
            }
        }

        let side: OBOrderSide = perp_order.order_side.clone().into();

        let mut processed_res = process_perp_order_request(
            self.perp_order_books.get(&market.unwrap()).clone().unwrap(),
            perp_order.clone(),
            side,
            signature.clone(),
            user_id,
            is_market,
            false,
            0,
            0,
            None,
        )
        .await;

        // This matches the orders and creates the swaps that can be executed
        let retry_messages;
        let new_order_id;
        match process_and_execute_perp_swaps(
            &self.mpsc_tx,
            &self.perp_rollback_safeguard,
            self.perp_order_books.get(&market.unwrap()).clone().unwrap(),
            &self.session,
            &self.backup_storage,
            &self.ws_connections,
            &self.privileged_ws_connections,
            &mut processed_res,
            user_id,
        )
        .await
        {
            Ok((h, oid)) => {
                retry_messages = h;
                new_order_id = oid;
            }
            Err(err) => {
                return send_order_error_reply(err);
            }
        };

        if let Err(e) = retry_failed_perp_swaps(
            &self.mpsc_tx,
            &self.perp_rollback_safeguard,
            self.perp_order_books.get(&market.unwrap()).clone().unwrap(),
            &self.session,
            &self.backup_storage,
            perp_order,
            side,
            signature,
            user_id,
            is_market,
            &self.ws_connections,
            &self.privileged_ws_connections,
            retry_messages,
            None,
        )
        .await
        {
            return send_order_error_reply(e);
        }

        store_output_json(&self.swap_output_json, &self.main_storage);

        // Send a successful reply to the caller
        let reply = OrderResponse {
            successful: true,
            error_message: "".to_string(),
            order_id: new_order_id,
        };

        return Ok(Response::new(reply));
    }

    //
    // * ===================================================================================================================================
    //

    async fn submit_liquidation_order(
        &self,
        request: Request<LiquidationOrderMessage>,
    ) -> Result<Response<LiquidationOrderResponse>, Status> {
        let _permit = self.semaphore.acquire().await.unwrap();

        let lock = self.is_paused.lock().await;
        drop(lock);

        tokio::task::yield_now().await;

        let req: LiquidationOrderMessage = request.into_inner();

        // ? Verify the signature is defined and has a valid format
        let signature: Signature;
        match verify_signature_format(&req.signature) {
            Ok(sig) => signature = sig,
            Err(err) => {
                return send_liquidation_order_error_reply(err);
            }
        }

        // ? Try to parse the grpc input as a LimitOrder
        let liquidation_order: LiquidationOrder;
        match LiquidationOrder::try_from(req) {
            Ok(lo) => liquidation_order = lo,
            Err(_e) => {
                return send_liquidation_order_error_reply(
                    "Error unpacking the liquidation order (verify the format is correct)"
                        .to_string(),
                );
            }
        };

        // ? market for perpetuals can be just the synthetic token
        let market = PERP_MARKET_IDS.get(&liquidation_order.synthetic_token.to_string());
        if market.is_none() {
            return send_liquidation_order_error_reply(
                "Market (token pair) does not exist for this token".to_string(),
            );
        }

        let mut perp_orderbook = self
            .perp_order_books
            .get(&market.unwrap())
            .clone()
            .unwrap()
            .lock()
            .await;
        let market_price;
        match perp_orderbook.get_market_price() {
            Ok(mp) => market_price = mp,
            Err(e) => {
                return send_liquidation_order_error_reply(e);
            }
        };
        drop(perp_orderbook);

        let liquidation_swap = LiquidationSwap::new(liquidation_order, signature, market_price);

        // TODO ==================================================================================

        let transaction_mpsc_tx = self.mpsc_tx.clone();

        let handle: TokioJoinHandle<
            JoinHandle<Result<LiquidationResponse, Report<PerpSwapExecutionError>>>,
        > = tokio::spawn(async move {
            let (resp_tx, resp_rx) = oneshot::channel();

            let mut grpc_message = GrpcMessage::new();
            grpc_message.msg_type = MessageType::LiquidationMessage;
            grpc_message.liquidation_message = Some(liquidation_swap);

            transaction_mpsc_tx
                .send((grpc_message, resp_tx))
                .await
                .ok()
                .unwrap();
            let res = resp_rx.await.unwrap();

            return res.liquidation_tx_handle.unwrap();
        });

        let liquidation_handle = handle.await.unwrap();

        let liquidation_response = liquidation_handle.join();

        // TODO ==================================================================================

        match liquidation_response {
            Ok(res1) => match res1 {
                Ok(response) => {
                    store_output_json(&self.swap_output_json, &self.main_storage);

                    // TODO Send message to the user whose position was liquidated

                    store_output_json(&self.swap_output_json, &self.main_storage);

                    let reply = LiquidationOrderResponse {
                        successful: true,
                        error_message: "".to_string(),
                        new_position: Some(GrpcPerpPosition::from(response.new_position)),
                    };

                    return Ok(Response::new(reply));
                }
                Err(err) => {
                    println!("\n{:?}", err);

                    let error_message_response: String = err.current_context().err_msg.to_string();

                    return send_liquidation_order_error_reply(error_message_response);
                }
            },
            Err(_e) => {
                println!("Unknown Error in liquidation execution");

                return send_liquidation_order_error_reply(
                    "Unknown Error occurred in the liquidation execution".to_string(),
                );
            }
        }
    }

    //
    // * ===================================================================================================================================
    //

    async fn cancel_order(
        &self,
        request: Request<CancelOrderMessage>,
    ) -> Result<Response<CancelOrderResponse>, Status> {
        tokio::task::yield_now().await;

        let req: CancelOrderMessage = request.into_inner();

        let market_id = req.market_id as u16;

        let order_book_m: &Arc<TokioMutex<OrderBook>>;
        if req.is_perp {
            let order_book_m_ = self.perp_order_books.get(&market_id);
            if order_book_m_.is_none() {
                return send_cancel_order_error_reply("Market not found".to_string());
            }

            order_book_m = order_book_m_.unwrap();
        } else {
            let order_book_m_ = self.order_books.get(&market_id);
            if order_book_m_.is_none() {
                return send_cancel_order_error_reply("Market not found".to_string());
            }

            order_book_m = order_book_m_.unwrap();
        }

        let order_side: OBOrderSide = if req.order_side {
            OBOrderSide::Bid
        } else {
            OBOrderSide::Ask
        };

        let cancel_request = limit_order_cancel_request(req.order_id, order_side, req.user_id);

        let mut order_book = order_book_m.lock().await;

        let res = order_book.process_order(cancel_request);

        return handle_cancel_order_repsonse(
            &res[0],
            req.is_perp,
            req.order_id,
            &self.partial_fill_tracker,
            &self.perpetual_partial_fill_tracker,
        );
    }

    //
    // * ===================================================================================================================================
    //

    async fn amend_order(
        &self,
        request: Request<AmendOrderRequest>,
    ) -> Result<Response<AmendOrderResponse>, Status> {
        tokio::task::yield_now().await;

        let req: AmendOrderRequest = request.into_inner();

        // ? Verify the signature is defined and has a valid format
        let signature: Signature;
        match verify_signature_format(&req.signature) {
            Ok(sig) => signature = sig,
            Err(err) => {
                return send_amend_order_error_reply(err);
            }
        }

        let market_id = req.market_id as u16;

        let order_book_m: &Arc<TokioMutex<OrderBook>>;
        if req.is_perp {
            let order_book_m_ = self.perp_order_books.get(&market_id);
            if order_book_m_.is_none() {
                return send_amend_order_error_reply("Market not found".to_string());
            }

            order_book_m = order_book_m_.unwrap();
        } else {
            let order_book_m_ = self.order_books.get(&market_id);
            if order_book_m_.is_none() {
                return send_amend_order_error_reply("Market not found".to_string());
            }

            order_book_m = order_book_m_.unwrap();
        }

        let order_side: OBOrderSide = if req.order_side {
            OBOrderSide::Bid
        } else {
            OBOrderSide::Ask
        };

        let amend_request = new_amend_order(
            req.order_id,
            order_side,
            req.user_id,
            req.new_price,
            req.new_expiration,
            signature.clone(),
            req.match_only,
        );

        let mut order_book = order_book_m.lock().await;
        let mut processed_res = order_book.process_order(amend_request);
        drop(order_book);

        if req.is_perp {
            if let Err(e) = execute_perp_swaps_after_amend_order(
                &self.mpsc_tx,
                &self.perp_rollback_safeguard,
                &order_book_m,
                &self.session,
                &self.backup_storage,
                &self.ws_connections,
                &self.privileged_ws_connections,
                &mut processed_res,
                req.order_id,
                order_side,
                signature,
                req.user_id,
            )
            .await
            {
                return send_amend_order_error_reply(e);
            }
        } else {
            if let Err(e) = execute_spot_swaps_after_amend_order(
                &self.mpsc_tx,
                &self.rollback_safeguard,
                &order_book_m,
                &self.session,
                &self.backup_storage,
                processed_res,
                &self.ws_connections,
                &self.privileged_ws_connections,
                req.order_id,
                order_side,
                signature,
                req.user_id,
            )
            .await
            {
                return send_amend_order_error_reply(e);
            }
        }

        store_output_json(&self.swap_output_json, &self.main_storage);

        let reply: AmendOrderResponse = AmendOrderResponse {
            successful: true,
            error_message: "".to_string(),
        };

        return Ok(Response::new(reply));
    }

    //
    // * ===================================================================================================================================
    //

    async fn execute_deposit(
        &self,
        request: Request<DepositMessage>,
    ) -> Result<Response<DepositResponse>, Status> {
        let _permit = self.semaphore.acquire().await.unwrap();

        let lock = self.is_paused.lock().await;
        drop(lock);

        tokio::task::yield_now().await;

        let transaction_mpsc_tx = self.mpsc_tx.clone();
        let swap_output_json = self.swap_output_json.clone();
        let main_storage = self.main_storage.clone();

        let handle = tokio::spawn(async move {
            let req: DepositMessage = request.into_inner();

            let deposit: Deposit;
            match Deposit::try_from(req) {
                Ok(d) => deposit = d,
                Err(_e) => {
                    return send_deposit_error_reply(
                        "Erroc unpacking the swap message (verify the format is correct)"
                            .to_string(),
                    );
                }
            };

            let handle: TokioJoinHandle<GrpcTxResponse> = tokio::spawn(async move {
                let (resp_tx, resp_rx) = oneshot::channel();

                let mut grpc_message = GrpcMessage::new();
                grpc_message.msg_type = MessageType::DepositMessage;
                grpc_message.deposit_message = Some(deposit);

                transaction_mpsc_tx
                    .send((grpc_message, resp_tx))
                    .await
                    .ok()
                    .unwrap();
                return resp_rx.await.unwrap();
            });

            return handle_deposit_repsonse(handle, &swap_output_json, &main_storage).await;
        });

        match handle.await {
            Ok(res) => {
                return res;
            }
            Err(_e) => {
                return send_deposit_error_reply(
                    "Unknown Error occured in the withdrawal execution".to_string(),
                );
            }
        }
    }

    //
    // * ===================================================================================================================================
    //

    async fn execute_withdrawal(
        &self,
        request: Request<WithdrawalMessage>,
    ) -> Result<Response<SuccessResponse>, Status> {
        let _permit = self.semaphore.acquire().await.unwrap();

        let lock = self.is_paused.lock().await;
        drop(lock);

        tokio::task::yield_now().await;

        let transaction_mpsc_tx = self.mpsc_tx.clone();
        let swap_output_json = self.swap_output_json.clone();
        let main_storage = self.main_storage.clone();

        let handle = tokio::spawn(async move {
            let req: WithdrawalMessage = request.into_inner();

            let withdrawal: Withdrawal;
            match Withdrawal::try_from(req) {
                Ok(w) => withdrawal = w,
                Err(_e) => {
                    return send_withdrawal_error_reply(
                        "Erroc unpacking the withdrawal message (verify the format is correct)"
                            .to_string(),
                    );
                }
            };

            let handle: TokioJoinHandle<GrpcTxResponse> = tokio::spawn(async move {
                let (resp_tx, resp_rx) = oneshot::channel();

                let mut grpc_message = GrpcMessage::new();
                grpc_message.msg_type = MessageType::WithdrawalMessage;
                grpc_message.withdrawal_message = Some(withdrawal);

                transaction_mpsc_tx
                    .send((grpc_message, resp_tx))
                    .await
                    .ok()
                    .unwrap();
                return resp_rx.await.unwrap();
            });

            return handle_withdrawal_repsonse(handle, &swap_output_json, &main_storage).await;
        });

        match handle.await {
            Ok(res) => {
                return res;
            }
            Err(_e) => {
                return send_withdrawal_error_reply(
                    "Unknown Error occured in the withdrawal execution".to_string(),
                );
            }
        }
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
        req: Request<OrderTabReq>,
    ) -> Result<Response<SuccessResponse>, Status> {
        tokio::task::yield_now().await;

        let req: OrderTabReq = req.into_inner();

        let is_perp = req.is_perp;

        // ===================================================================================

        let reply = SuccessResponse {
            successful: true,
            error_message: "".to_string(),
        };

        return Ok(Response::new(reply));
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
