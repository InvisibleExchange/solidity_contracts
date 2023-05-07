use num_bigint::{BigInt, BigUint};
use num_traits::Zero;
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::thread::{self, spawn};
use std::time::Duration;
use std::{collections::HashMap, sync::Arc};

use crate::matching_engine::orderbook::OrderBook;
use crate::perpetual::IMPACT_NOTIONAL_PER_ASSET;
use crate::server::grpc::{FundingUpdateMessage, GrpcMessage, GrpcTxResponse, MessageType};
use crate::utils::crypto_utils::{EcPoint, Signature};
use crate::utils::errors::send_funding_error_reply;
use crate::utils::firestore::{create_session, start_add_note_thread};
use crate::utils::notes::Note;
use crate::utils::storage::BackupStorage;

use firestore_db_and_auth::{documents, ServiceSession};

use tokio::sync::{
    mpsc::Sender as MpscSender,
    oneshot::{self, Sender as OneshotSender},
    Mutex as TokioMutex,
};
use tokio::task::JoinHandle as TokioJoinHandle;
use tokio::time;

pub async fn start_periodic_updates(
    order_books: &HashMap<u16, Arc<TokioMutex<OrderBook>>>,
    perp_order_books: &HashMap<u16, Arc<TokioMutex<OrderBook>>>,
    mpsc_tx: &MpscSender<(GrpcMessage, OneshotSender<GrpcTxResponse>)>,
    session: &Arc<Mutex<ServiceSession>>,
) {
    let perp_order_books_ = perp_order_books.clone();
    let mpsc_tx = mpsc_tx.clone();

    // * UPDATE FUNDING RATES EVERY 60 SECONDS
    let mut interval = time::interval(time::Duration::from_secs(60));
    tokio::spawn(async move {
        loop {
            interval.tick().await;

            let mut impact_prices: HashMap<u64, (u64, u64)> = HashMap::new();
            for (_, b) in perp_order_books_.iter() {
                let book = b.lock().await;

                let impact_notional: u64 = *IMPACT_NOTIONAL_PER_ASSET
                    .get(book.order_asset.to_string().as_str())
                    .unwrap();

                let res = book.get_impact_prices(impact_notional);
                if let Err(e) = res {
                    return send_funding_error_reply(e);
                }

                let (impact_bid_price, impact_ask_price) = res.unwrap();

                impact_prices.insert(book.order_asset, (impact_ask_price, impact_bid_price));
            }

            let transaction_mpsc_tx = mpsc_tx.clone();

            let handle: TokioJoinHandle<GrpcTxResponse> = tokio::spawn(async move {
                let (resp_tx, resp_rx) = oneshot::channel();

                let mut grpc_message = GrpcMessage::new();
                grpc_message.msg_type = MessageType::FundingUpdate;
                grpc_message.funding_update_message = Some(FundingUpdateMessage { impact_prices });

                transaction_mpsc_tx
                    .send((grpc_message, resp_tx))
                    .await
                    .ok()
                    .unwrap();

                return resp_rx.await.unwrap();
            });

            if let Ok(grpc_res) = handle.await {
                if !grpc_res.successful {
                    println!("Failed applying funding update\n");
                }
            } else {
                println!("Failed applying funding update\n");
            }
        }
    });

    // //  *CHECK FOR FAILED DB UPDATES EVERY 5 MINUTES
    // let mut interval = time::interval(time::Duration::from_secs(300));
    // let session = self.session.clone();
    // let backup_storage = self.backup_storage.clone();
    // tokio::spawn(async move {
    //     loop {
    //         interval.tick().await;
    //         if let Err(_e) = retry_failed_updates(&session, backup_storage.clone()) {
    //             println!("Failed retrying failed database updates");
    //         };
    //     }
    // });

    // * CLEAR EXPIRED ORDERS EVERY 3 SECONDS
    let order_books = order_books.clone();
    let perp_order_books_ = perp_order_books.clone();
    let session_ = session.clone();

    let mut interval2 = time::interval(time::Duration::from_secs(3));

    tokio::spawn(async move {
        loop {
            interval2.tick().await;

            for book in order_books.values() {
                book.lock().await.clear_expired_orders();
            }

            for book in perp_order_books_.values() {
                book.lock().await.clear_expired_orders();
            }
        }
    });

    // * CREATE NEW FIREBASE SESSION EVERY 45 MINUTES
    std::thread::spawn(move || loop {
        thread::sleep(Duration::from_secs(1800));

        let new_session = create_session();
        let mut sess = session_.lock();
        *sess = new_session;

        drop(sess);
    });
}
