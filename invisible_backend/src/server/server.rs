use invisible_backend::server::server_helpers::periodic_updates::start_periodic_updates;
use invisible_backend::transaction_batch::transaction_batch::TransactionBatch;
use parking_lot::Mutex;
use std::{collections::HashMap, net::SocketAddr, sync::Arc, thread::ThreadId};
use tokio::net::TcpListener;

use invisible_backend::perpetual::perp_helpers::perp_rollback::PerpRollbackInfo;
use invisible_backend::server::{
    engine::EngineService,
    grpc::{engine, GrpcMessage, GrpcTxResponse, MessageType},
    server_helpers::{handle_connection, init_order_books, WsConnectionsMap},
};

use invisible_backend::transactions::transaction_helpers::rollbacks::RollbackInfo;

use tokio::sync::{mpsc, oneshot, Mutex as TokioMutex};
use tonic::transport::Server;

use engine::engine_server::EngineServer;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // env_logger::init();

    // * =============================================================================================================================

    // ? A channel between the state_update thread and all the client connection threads that open
    let (mpsc_tx, mut transaction_mpsc_rx) =
        mpsc::channel::<(GrpcMessage, oneshot::Sender<GrpcTxResponse>)>(100);

    // ? A map shared between threads that checks if the state has been updated before an error occured and requires a rollback
    let rollback_safeguard: Arc<Mutex<HashMap<ThreadId, RollbackInfo>>> =
        Arc::new(Mutex::new(HashMap::new()));
    let perp_rollback_safeguard: Arc<Mutex<HashMap<ThreadId, PerpRollbackInfo>>> =
        Arc::new(Mutex::new(HashMap::new()));

    let mut tx_batch = TransactionBatch::new(
        40,
        32,
        rollback_safeguard.clone(),
        perp_rollback_safeguard.clone(),
    );
    tx_batch.init();

    // TODO: TESTING ==========================================================
    println!("\nstate tree: {:?}", tx_batch.state_tree.lock().leaf_nodes);
    println!(
        "\nperp state tree: {:?}",
        tx_batch.perpetual_state_tree.lock().leaf_nodes
    );
    println!("\nrunning_tx_count: {:?}", tx_batch.running_tx_count);

    // println!("\nlatest_index_price: {:?}", tx_batch.latest_index_price);
    // println!(
    //     "\nmin_index_price_data: {:?}",
    //     tx_batch.min_index_price_data
    // );
    // println!(
    //     "\nmax_index_price_data: {:?}",
    //     tx_batch.max_index_price_data
    // );

    // println!("\nfunding_rates: {:?}", tx_batch.funding_rates);
    // println!("\nfunding_prices: {:?}", tx_batch.funding_prices);
    // println!("\nfunding index: {:?}", tx_batch.current_funding_idx);
    // println!("\nmin funding indexes: {:?}", tx_batch.min_funding_idxs);

    // TODO: TESTING ==========================================================

    let session = Arc::clone(&tx_batch.firebase_session);
    let main_storage = Arc::clone(&tx_batch.main_storage);
    let backup_storage = Arc::clone(&tx_batch.backup_storage);
    let swap_output_json = Arc::clone(&tx_batch.swap_output_json);

    let state_tree = Arc::clone(&tx_batch.state_tree);
    let perp_state_tree = Arc::clone(&tx_batch.perpetual_state_tree);

    let partial_fill_tracker = Arc::clone(&tx_batch.partial_fill_tracker);
    let perpetual_partial_fill_tracker = Arc::clone(&tx_batch.perpetual_partial_fill_tracker);

    // ? Spawn a thread to handle the state update
    tokio::spawn(async move {
        // ? This gets the request from the client_connection thread and sends a response back
        while let Some((grpc_message, response)) = transaction_mpsc_rx.recv().await {
            // ? This should perform the state update and send a response back to the client_connection thread

            match grpc_message.msg_type {
                MessageType::DepositMessage => {
                    let handle =
                        tx_batch.execute_transaction(grpc_message.deposit_message.unwrap());

                    let grpc_res = GrpcTxResponse {
                        tx_handle: Some(handle),
                        perp_tx_handle: None,
                        liquidation_tx_handle: None,
                        new_idxs: None,
                        successful: true,
                    };

                    response
                        .send(grpc_res)
                        .expect("failed sending back the TxResponse in deposit");
                }
                MessageType::SwapMessage => {
                    let handle = tx_batch.execute_transaction(grpc_message.swap_message.unwrap());

                    let grpc_res = GrpcTxResponse {
                        tx_handle: Some(handle),
                        perp_tx_handle: None,
                        liquidation_tx_handle: None,
                        new_idxs: None,
                        successful: true,
                    };

                    response
                        .send(grpc_res)
                        .expect("failed sending back the TxResponse in swap");
                }
                MessageType::WithdrawalMessage => {
                    let handle =
                        tx_batch.execute_transaction(grpc_message.withdrawal_message.unwrap());

                    let grpc_res = GrpcTxResponse {
                        tx_handle: Some(handle),
                        perp_tx_handle: None,
                        liquidation_tx_handle: None,
                        new_idxs: None,
                        successful: true,
                    };

                    response
                        .send(grpc_res)
                        .expect("failed sending back the TxResponse in withdrawal");
                }
                MessageType::PerpSwapMessage => {
                    let handle = tx_batch
                        .execute_perpetual_transaction(grpc_message.perp_swap_message.unwrap());

                    let grpc_res = GrpcTxResponse {
                        tx_handle: None,
                        perp_tx_handle: Some(handle),
                        liquidation_tx_handle: None,
                        new_idxs: None,
                        successful: true,
                    };

                    response
                        .send(grpc_res)
                        .expect("failed sending back the TxResponse in perp swap");
                }
                MessageType::LiquidationMessage => {
                    let handle = tx_batch
                        .execute_liquidation_transaction(grpc_message.liquidation_message.unwrap());

                    let grpc_res = GrpcTxResponse {
                        tx_handle: None,
                        perp_tx_handle: None,
                        liquidation_tx_handle: Some(handle),
                        new_idxs: None,
                        successful: true,
                    };

                    response
                        .send(grpc_res)
                        .expect("failed sending back the TxResponse in perp swap");
                }
                MessageType::SplitNotes => {
                    let (notes_in, notes_out) = grpc_message.split_notes_message.unwrap();
                    let zero_idxs = tx_batch.split_notes(notes_in, notes_out);

                    let grpc_res = GrpcTxResponse {
                        tx_handle: None,
                        perp_tx_handle: None,
                        liquidation_tx_handle: None,
                        new_idxs: Some(zero_idxs),
                        successful: true,
                    };

                    response
                        .send(grpc_res)
                        .expect("failed sending back the TxResponse in split notes");
                }
                MessageType::MarginChange => {
                    let new_idxs = tx_batch
                        .change_position_margin(grpc_message.change_margin_message.unwrap());

                    let grpc_res = GrpcTxResponse {
                        tx_handle: None,
                        perp_tx_handle: None,
                        liquidation_tx_handle: None,
                        new_idxs: Some(new_idxs),
                        successful: true,
                    };

                    response
                        .send(grpc_res)
                        .expect("failed sending back the TxResponse in margin change");
                }
                MessageType::Rollback => {
                    tx_batch.rollback_transaction(grpc_message.rollback_info_message.unwrap());

                    let grpc_res = GrpcTxResponse {
                        tx_handle: None,
                        perp_tx_handle: None,
                        liquidation_tx_handle: None,
                        new_idxs: None,
                        successful: true,
                    };

                    response
                        .send(grpc_res)
                        .expect("failed sending back the TxResponse in rollback");
                }
                MessageType::FundingUpdate => {
                    let funding_update = grpc_message.funding_update_message.unwrap();

                    tx_batch.per_minute_funding_updates(funding_update);

                    let grpc_res = GrpcTxResponse {
                        tx_handle: None,
                        perp_tx_handle: None,
                        liquidation_tx_handle: None,
                        new_idxs: None,
                        successful: true,
                    };

                    response
                        .send(grpc_res)
                        .expect("failed sending back the TxResponse in funding update");
                }
                MessageType::IndexPriceUpdate => {
                    let oracle_updates = grpc_message.price_update_message.unwrap();

                    let updated_prices = tx_batch.update_index_prices(oracle_updates).ok();

                    let grpc_res = GrpcTxResponse {
                        tx_handle: None,
                        perp_tx_handle: None,
                        liquidation_tx_handle: None,
                        new_idxs: None,
                        successful: updated_prices.is_some(),
                    };

                    response
                        .send(grpc_res)
                        .expect("failed sending back the TxResponse in funding update");
                }
                MessageType::Undefined => {
                    println!("Undefined message type");
                }
            }
        }
    });

    // ? Spawn the server
    let addr: SocketAddr = "0.0.0.0:50052".parse()?;

    println!("Listening on {:?}", addr);

    // * =============================================================================================================================

    let (order_books, perp_order_books) = init_order_books();

    let privileged_ws_connections: Arc<TokioMutex<Vec<u64>>> =
        Arc::new(TokioMutex::new(Vec::new()));

    let ws_addr: SocketAddr = "0.0.0.0:50053".parse()?;
    println!("Listening for updates on {:?}", ws_addr);

    // Create the event loop and TCP listener we'll accept connections on.
    let try_socket = TcpListener::bind(&ws_addr).await;
    let listener = try_socket.expect("Failed to bind");

    let ws_connection_i: WsConnectionsMap = HashMap::new();
    let ws_connections = Arc::new(TokioMutex::new(ws_connection_i));

    let ws_conn_mutex = ws_connections.clone();

    let privileged_ws_connections_ = privileged_ws_connections.clone();

    // Handle incoming websocket connections
    tokio::spawn(async move {
        loop {
            let ws_conn_ = ws_conn_mutex.clone();
            let privileged_ws_connections_ = privileged_ws_connections_.clone();

            let (stream, _addr) = listener.accept().await.expect("accept failed");

            tokio::spawn(handle_connection(
                stream,
                ws_conn_,
                privileged_ws_connections_,
            ));
        }
    });

    let ws_conn_mutex = ws_connections.clone();
    // ? Start periodic updates
    start_periodic_updates(
        &order_books,
        &perp_order_books,
        &mpsc_tx,
        &session,
        &ws_conn_mutex,
        &privileged_ws_connections,
    )
    .await;

    let transaction_service = EngineService {
        mpsc_tx,
        session,
        state_tree,
        perp_state_tree,
        partial_fill_tracker,
        perpetual_partial_fill_tracker,
        rollback_safeguard,
        perp_rollback_safeguard,
        order_books,
        perp_order_books,
        ws_connections,
        privileged_ws_connections,
        tx_count: Arc::new(Mutex::new(0)),
        main_storage,
        backup_storage,
        swap_output_json,
    };

    // * =============================================================================================================================

    Server::builder()
        .concurrency_limit_per_connection(128)
        .add_service(EngineServer::new(transaction_service))
        .serve(addr)
        .await?;

    Ok(())
}

// =================================================================================================
