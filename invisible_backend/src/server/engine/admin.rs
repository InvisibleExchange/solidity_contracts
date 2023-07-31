use std::{collections::HashMap, sync::Arc, time::Instant};

use super::super::grpc::engine_proto::{
    EmptyReq, FinalizeBatchResponse, OracleUpdateReq, RestoreOrderBookMessage,
    SpotOrderRestoreMessage, SuccessResponse,
};
use super::super::grpc::{GrpcMessage, GrpcTxResponse, MessageType};

use crate::{
    matching_engine::orderbook::OrderBook, transaction_batch::tx_batch_structs::OracleUpdate,
};

use crate::utils::errors::send_oracle_update_error_reply;

use tokio::sync::{
    mpsc::Sender as MpscSender,
    oneshot::{self, Sender as OneshotSender},
    Mutex as TokioMutex, Semaphore,
};
use tokio::task::JoinHandle as TokioJoinHandle;
use tonic::{Request, Response, Status};

pub async fn finalize_batch_inner(
    mpsc_tx: &MpscSender<(GrpcMessage, OneshotSender<GrpcTxResponse>)>,
    semaphore: &Semaphore,
    is_paused: &Arc<TokioMutex<bool>>,
    //
    _: Request<EmptyReq>,
) -> Result<Response<FinalizeBatchResponse>, Status> {
    let _permit = semaphore.acquire().await.unwrap();

    let lock = is_paused.lock().await;

    let now = Instant::now();

    tokio::task::yield_now().await;

    let transaction_mpsc_tx = mpsc_tx.clone();
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

pub async fn update_index_price_inner(
    mpsc_tx: &MpscSender<(GrpcMessage, OneshotSender<GrpcTxResponse>)>,
    //
    request: Request<OracleUpdateReq>,
) -> Result<Response<SuccessResponse>, Status> {
    tokio::task::yield_now().await;

    let transaction_mpsc_tx = mpsc_tx.clone();
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

pub async fn restore_orderbook_inner(
    order_books: &HashMap<u16, Arc<TokioMutex<OrderBook>>>,
    perp_order_books: &HashMap<u16, Arc<TokioMutex<OrderBook>>>,
    //
    request: Request<RestoreOrderBookMessage>,
) -> Result<Response<SuccessResponse>, Status> {
    tokio::task::yield_now().await;

    let req: RestoreOrderBookMessage = request.into_inner();

    let spot_order_messages: Vec<SpotOrderRestoreMessage> = req.spot_order_restore_messages;

    for message in spot_order_messages {
        let market_id = message.market_id as u16;

        let bid_order_restore_messages = message.bid_order_restore_messages;
        let ask_order_restore_messages = message.ask_order_restore_messages;

        let order_book_ = order_books.get(&market_id);
        if let Some(order_book) = order_book_ {
            let mut order_book = order_book.lock().await;

            order_book
                .restore_spot_order_book(bid_order_restore_messages, ask_order_restore_messages);
        }
    }

    // ? ===========================================================================================

    let perp_order_messages = req.perp_order_restore_messages;

    for message in perp_order_messages {
        let market_id = message.market_id as u16;

        let bid_order_restore_messages = message.bid_order_restore_messages;
        let ask_order_restore_messages = message.ask_order_restore_messages;

        let order_book_ = perp_order_books.get(&market_id);
        if let Some(order_book) = order_book_ {
            let mut order_book = order_book.lock().await;

            order_book
                .restore_perp_order_book(bid_order_restore_messages, ask_order_restore_messages);
        }
    }

    let reply = SuccessResponse {
        successful: true,
        error_message: "".to_string(),
    };

    return Ok(Response::new(reply));
}
