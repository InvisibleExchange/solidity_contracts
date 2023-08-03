use std::{
    fs::File,
    io::Read,
    sync::Arc,
    thread::{spawn, JoinHandle},
    time::SystemTime,
};

use firestore_db_and_auth::{documents, errors::FirebaseError, Credentials, ServiceSession};
use num_bigint::BigUint;
use num_traits::FromPrimitive;
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};

use crate::{
    order_tab::OrderTab,
    perpetual::perp_position::PerpPosition,
    transactions::transaction_helpers::transaction_output::{FillInfo, PerpFillInfo},
    utils::notes::Note,
};

use crate::utils::crypto_utils::pedersen;

use super::storage::BackupStorage;

#[derive(Serialize, Deserialize, Debug)]
pub struct FirebaseNoteObject {
    pub address: [String; 2],
    pub commitment: String,
    pub hidden_amount: String,
    pub index: String,
    pub token: String,
}

impl FirebaseNoteObject {
    pub fn from_note(note: &Note) -> FirebaseNoteObject {
        // let hash8 = trimHash(yt, 64);
        // let hiddentAmount = bigInt(amount).xor(hash8).value;

        let yt_digits = note.blinding.to_u64_digits();
        let yt_trimmed = if yt_digits.len() == 0 {
            0
        } else {
            yt_digits[0]
        };

        let hidden_amount = note.amount ^ yt_trimmed;

        return FirebaseNoteObject {
            address: [note.address.x.to_string(), note.address.y.to_string()],
            commitment: pedersen(&BigUint::from_u64(note.amount).unwrap(), &note.blinding)
                .to_string(),
            hidden_amount: hidden_amount.to_string(),
            index: note.index.to_string(),
            token: note.token.to_string(),
        };
    }
}

// ? Order Tab
#[derive(Serialize, Deserialize, Debug)]
pub struct OrderTabObject {
    pub index: u32,
    // header
    pub is_perp: bool,
    pub is_smart_contract: bool,
    pub base_token: u32,
    pub quote_token: u32,
    pub pub_key: String,
    //
    pub base_commitment: String,
    pub base_hidden_amount: String,
    pub quote_commitment: String,
    pub quote_hidden_amount: String,
    pub hash: String,
}

impl OrderTabObject {
    pub fn from_order_tab(order_tab: &OrderTab) -> Self {
        // let hash8 = trimHash(yt, 64);
        // let hiddentAmount = bigInt(amount).xor(hash8).value;

        // ? Hide base amount
        let base_yt_digits = order_tab.tab_header.base_blinding.to_u64_digits();
        let base_yt_trimmed = if base_yt_digits.len() == 0 {
            0
        } else {
            base_yt_digits[0]
        };
        let base_hidden_amount = order_tab.base_amount ^ base_yt_trimmed;

        // ? Hide quote amount
        let quote_yt_digits = order_tab.tab_header.quote_blinding.to_u64_digits();
        let quote_yt_trimmed = if quote_yt_digits.len() == 0 {
            0
        } else {
            quote_yt_digits[0]
        };
        let quote_hidden_amount = order_tab.quote_amount ^ quote_yt_trimmed;

        return OrderTabObject {
            index: order_tab.tab_idx,
            is_perp: order_tab.tab_header.is_perp,
            is_smart_contract: order_tab.tab_header.is_smart_contract,
            base_token: order_tab.tab_header.base_token,
            quote_token: order_tab.tab_header.quote_token,
            pub_key: order_tab.tab_header.pub_key.to_string(),
            base_commitment: pedersen(
                &BigUint::from_u64(order_tab.base_amount).unwrap(),
                &order_tab.tab_header.base_blinding,
            )
            .to_string(),
            base_hidden_amount: base_hidden_amount.to_string(),
            quote_commitment: pedersen(
                &BigUint::from_u64(order_tab.quote_amount).unwrap(),
                &order_tab.tab_header.quote_blinding,
            )
            .to_string(),
            quote_hidden_amount: quote_hidden_amount.to_string(),
            hash: order_tab.hash.to_string(),
        };
    }
}

// * ==================================================================================

pub fn create_session() -> ServiceSession {
    let mut cred =
        Credentials::from_file("firebase-service-account.json").expect("Read credentials file");
    cred.download_google_jwks().expect("Download Google JWKS");

    let session = ServiceSession::new(cred).expect("Create a service account session");

    session
}

// TODO: FIX THIS
// pub fn retry_failed_updates(
//     state_tree: &Arc<Mutex<SuperficialTree>>,
//     session: &Arc<Mutex<ServiceSession>>,
//     backup_storage: &Arc<Mutex<BackupStorage>>,
// ) -> Result<(), Box<dyn std::error::Error>> {
//     let s: parking_lot::lock_api::MutexGuard<parking_lot::RawMutex, BackupStorage> =
//         backup_storage.lock();
//     let notes_info = s.read_notes();
//     let positions_info = s.read_positions();
//     let spot_fills = s.read_spot_fills();
//     let perp_fills = s.read_perp_fills();

//     s.clear_db().unwrap();
//     drop(s);

//     let sess = session.lock();

//     let state_tree_m = state_tree.lock();
//     let notes = notes_info.0;
//     for note in notes {
//         if note.hash == state_tree_m.get_leaf_by_index(note.index) {
//             store_new_note(&sess, backup_storage, &note);
//         }
//     }
//     // TODO: What to do with this if it happens?
//     // let removable_info = notes_info.1;
//     // for (idx, address) in removable_info {
//     //     delete_note_at_address(&sess, backup_storage, &address, &idx.to_string());
//     // }
//     drop(state_tree_m);

//     // ? ADD AND REMOVED POSITIONS TO/FROM THE DATABASE
//     let positions = positions_info.0;
//     for position in positions {
//         if position.hash == perp_state_tree_m.get_leaf_by_index(position.index as u64) {
//             if position.hash == position.hash_position() {
//                 store_new_position(&sess, backup_storage, &position);
//             }
//         }
//     }
//     drop(perp_state_tree_m);
//     // TODO: What to do with this if it happens?
//     // let removable_info = positions_info.1;
//     // for info in removable_info {
//     // delete_position_at_address(
//     //     &sess,
//     //     backup_storage,
//     //     &info.1.to_string(),
//     //     &info.0.to_string(),
//     // );
//     // }

//     for fill in spot_fills {
//         store_new_spot_fill(&sess, backup_storage, &fill);
//     }

//     for fill in perp_fills {
//         store_new_perp_fill(&sess, backup_storage, &fill);
//     }

//     Ok(())
// }

// NOTES ------------- -------------- ---------------- ----------------- ----------------

fn delete_note_at_address(
    session: &ServiceSession,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    address: &str,
    idx: &str,
) {
    // & address is the x coordinate in string format and idx is the index in string format

    let delete_path = format!("notes/{}/indexes/{}", address, idx);
    let r = documents::delete(session, delete_path.as_str(), true);
    if let Err(e) = r {
        if let FirebaseError::APIError(numeric_code, string_code, _context) = e {
            if string_code.starts_with("No document to update") && numeric_code == 404 {
                return;
            }
        } else {
            println!("Error deleting note from backup storage. ERROR: {:?}", e);
        }

        let s = backup_storage.lock();
        if let Err(_e) = s.store_note_removal(u64::from_str_radix(idx, 10).unwrap(), address) {}
    }
}

fn store_new_note(
    session: &ServiceSession,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    note: &Note,
) {
    let obj = FirebaseNoteObject::from_note(note);

    let write_path = format!("notes/{}/indexes", note.address.x.to_string().as_str());
    let res = documents::write(
        session,
        write_path.as_str(),
        Some(note.index.to_string()),
        &obj,
        documents::WriteOptions::default(),
    );

    if let Err(e) = res {
        println!("Error storing note in backup storage. ERROR: {:?}", e);
        let s = backup_storage.lock();
        if let Err(_e) = s.store_note(note) {};
        drop(s);
    }
}

// POSITIONS ------------- -------------- ---------------- ----------------- ----------------

fn delete_position_at_address(
    session: &ServiceSession,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    address: &str,
    idx: &str,
) {
    // & address is the x coordinate in string format and idx is the index in string format
    let delete_path = format!("positions/{}/indexes/{}", address, idx);
    let r = documents::delete(session, delete_path.as_str(), true);
    if let Err(e) = r {
        if let FirebaseError::APIError(numeric_code, string_code, _context) = e {
            if string_code.starts_with("No document to update") && numeric_code == 404 {
                return;
            }
        } else {
            println!("Error deleting note from database: ERROR: {:?}", e);
        }

        let s = backup_storage.lock();
        if let Err(_e) = s.store_position_removal(u64::from_str_radix(idx, 10).unwrap(), address) {}
    }

    // ? ===================================================================
    // ? Store the position's liquidation price in the database
    let delete_path = format!("liquidations/{}", address.to_string() + "-" + idx);

    let r = documents::delete(session, delete_path.as_str(), true);

    if let Err(e) = r {
        if let FirebaseError::APIError(numeric_code, string_code, _context) = e {
            if string_code.starts_with("No document to update") && numeric_code == 404 {
                return;
            }
        } else {
            println!("Error deleting liquidation from database: ERROR: {:?}", e);
        }
    }
}

fn store_new_position(
    session: &ServiceSession,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    position: &PerpPosition,
) {
    // ? Store the position in the database
    let write_path = format!(
        "positions/{}/indexes",
        position.position_header.position_address.to_string(),
    );

    let _res = documents::write(
        session,
        write_path.as_str(),
        Some(position.index.to_string()),
        position,
        documents::WriteOptions::default(),
    );

    if let Err(e) = _res {
        println!("Error storing position to database. ERROR: {:?}", e);
        let s = backup_storage.lock();
        if let Err(_e) = s.store_position(position) {};
        drop(s);
    }

    // ? ===================================================================
    // ? Store the position's liquidation price in the database
    let write_path = format!(
        "{}",
        position.position_header.position_address.to_string()
            + "-"
            + position.index.to_string().as_str()
    );

    let _res = documents::write(
        session,
        "liquidations",
        Some(write_path),
        &json!({
            "liquidation_price": &position.liquidation_price,
            "synthetic_token": &position.position_header. synthetic_token,
            "order_side": &position.order_side,
        }),
        documents::WriteOptions::default(),
    );

    if let Err(e) = _res {
        println!(
            "Error storing liquidation price to database. ERROR: {:?}",
            e
        );
    }
}

// ORDER TAB ------------- -------------- ---------------- ----------------- ----------------

fn store_order_tab(
    session: &ServiceSession,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    order_tab: &OrderTab,
) {
    let obj = OrderTabObject::from_order_tab(order_tab);

    let write_path = format!(
        "order_tabs/{}/indexes",
        order_tab.tab_header.pub_key.to_string().as_str()
    );
    let res = documents::write(
        session,
        write_path.as_str(),
        Some(order_tab.tab_idx.to_string()),
        &obj,
        documents::WriteOptions::default(),
    );

    if let Err(e) = res {
        println!("Error storing note in backup storage. ERROR: {:?}", e);
        let s = backup_storage.lock();
        if let Err(_e) = s.store_order_tab(order_tab) {};
        drop(s);
    }
}

fn delete_order_tab(
    session: &ServiceSession,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    pub_key: &str,
    idx: &str,
) {
    // & address is the x coordinate in string format and idx is the index in string format

    let delete_path = format!("order_tabs/{}/indexes/{}", pub_key, idx);
    let r = documents::delete(session, delete_path.as_str(), true);
    if let Err(e) = r {
        if let FirebaseError::APIError(numeric_code, string_code, _context) = e {
            if string_code.starts_with("No document to update") && numeric_code == 404 {
                return;
            }
        } else {
            println!("Error deleting note from backup storage. ERROR: {:?}", e);
        }

        let s = backup_storage.lock();
        if let Err(_e) = s.store_order_tab_removal(u64::from_str_radix(idx, 10).unwrap(), pub_key) {
        }
    }
}

// FILLS   -------------- ---------------- ----------------- ----------------

fn store_new_spot_fill(
    session: &ServiceSession,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    fill_info: &FillInfo,
) {
    let write_path = format!("fills");

    let doc_id: Option<String> = None;
    let _res = documents::write(
        session,
        write_path.as_str(),
        doc_id,
        &fill_info,
        documents::WriteOptions::default(),
    );

    if let Err(_e) = _res {
        let s = backup_storage.lock();
        if let Err(e) = s.store_spot_fill(fill_info) {
            println!("Error storing spot fill in backup storage. ERROR: {:?}", e);
        };
        drop(s);
    }
}

fn store_new_perp_fill(
    session: &ServiceSession,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    fill_info: &PerpFillInfo,
) {
    let write_path = format!("perp_fills");

    let doc_id: Option<String> = None;
    let _res = documents::write(
        session,
        write_path.as_str(),
        doc_id,
        &fill_info,
        documents::WriteOptions::default(),
    );

    if let Err(_e) = _res {
        let s = backup_storage.lock();
        if let Err(e) = s.store_perp_fill(fill_info) {
            println!("Error storing perp fill in backup storage. ERROR: {:?}", e);
        };
        drop(s);
    }
}

// * PUBLIC FUNCTIONS ===============================================================

// NOTES

pub fn start_add_note_thread(
    note: Note,
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
) -> JoinHandle<()> {
    let s = Arc::clone(&session);
    let backup = Arc::clone(&backup_storage);

    let handle = spawn(move || {
        let session_ = s.lock();
        // let backup_storage = backup_storage.lock();

        store_new_note(&session_, &backup, &note);
        drop(session_);
    });
    return handle;
}

pub fn start_delete_note_thread(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    address: String,
    idx: String,
) -> JoinHandle<()> {
    let s = Arc::clone(&session);
    let backup = Arc::clone(&backup_storage);

    let handle = spawn(move || {
        let session_ = s.lock();
        delete_note_at_address(&session_, &backup, address.as_str(), idx.as_str());
        drop(session_);
    });
    return handle;
}

// POSITIONS

pub fn start_add_position_thread(
    position: PerpPosition,
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
) -> JoinHandle<()> {
    let s = Arc::clone(&session);
    let backup = Arc::clone(&backup_storage);

    let handle = spawn(move || {
        let session_ = s.lock();

        store_new_position(&session_, &backup, &position);
        drop(session_);
    });
    return handle;
}

pub fn start_delete_position_thread(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    address: String,
    idx: String,
) -> JoinHandle<()> {
    let s = Arc::clone(&session);
    let backup = Arc::clone(&backup_storage);

    let handle = spawn(move || {
        let session_ = s.lock();
        delete_position_at_address(&session_, &backup, address.as_str(), idx.as_str());
        drop(session_);
    });
    return handle;
}

// ORDER TABS

pub fn start_add_order_tab_thread(
    order_tab: OrderTab,
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
) -> JoinHandle<()> {
    let s = Arc::clone(&session);
    let backup = Arc::clone(&backup_storage);

    let handle = spawn(move || {
        let session_ = s.lock();
        // let backup_storage = backup_storage.lock();

        store_order_tab(&session_, &backup, &order_tab);
        drop(session_);
    });
    return handle;
}

pub fn start_delete_order_tab_thread(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
    pub_key: String,
    idx: String,
) -> JoinHandle<()> {
    let s = Arc::clone(&session);
    let backup = Arc::clone(&backup_storage);

    let handle = spawn(move || {
        let session_ = s.lock();
        delete_order_tab(&session_, &backup, pub_key.as_str(), idx.as_str());
        drop(session_);
    });
    return handle;
}

// FILLS

pub fn start_add_fill_thread(
    fill_info: FillInfo,
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
) -> JoinHandle<()> {
    let s = Arc::clone(&session);
    let backup = Arc::clone(&backup_storage);

    let handle = spawn(move || {
        let session_ = s.lock();

        store_new_spot_fill(&session_, &backup, &fill_info);
        drop(session_);
    });
    return handle;
}

pub fn start_add_perp_fill_thread(
    fill_info: PerpFillInfo,
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: &Arc<Mutex<BackupStorage>>,
) -> JoinHandle<()> {
    let s = Arc::clone(&session);
    let backup = Arc::clone(&backup_storage);

    let handle = spawn(move || {
        let session_ = s.lock();

        store_new_perp_fill(&session_, &backup, &fill_info);
        drop(session_);
    });

    return handle;
}

// * FIREBASE STORAGE ===============================================================

use reqwest::Client;
use serde_json::{from_slice, json, to_vec, Map, Value};

// Define a struct to deserialize the response from the Firebase Storage API
#[derive(Deserialize)]
struct UploadResponse {
    name: String,
}

#[derive(Serialize, Deserialize)]
struct JsonSerdeMapWrapper(Map<String, Value>);

pub async fn upload_file_to_storage(
    file_name: String,
    value: Map<String, Value>,
) -> Result<(), Box<dyn std::error::Error>> {
    //

    let (access_token, storage_bucket_url) = get_access_token()?;

    // Create a reqwest client
    let client = Client::new();

    let serialized_data = to_vec(&value).expect("Serialization failed");

    // Make a POST request to upload the file
    let url = format!(
        "https://firebasestorage.googleapis.com/v0/b/{}/o?name={}",
        storage_bucket_url, file_name
    );
    let response = client
        .post(url)
        .header("Content-Type", "application/octet-stream")
        .header("Authorization", "Bearer ".to_owned() + &access_token)
        .body(serialized_data)
        .send()
        .await?;

    // Deserialize the response
    let upload_response: UploadResponse = response.json().await?;

    println!(
        "File uploaded successfully. File name: {}",
        upload_response.name
    );

    Ok(())
}

pub async fn read_file_from_storage(
    file_name: String,
) -> Result<Map<String, Value>, Box<dyn std::error::Error>> {
    // Create a reqwest client
    let client = Client::new();

    let (access_token, storage_bucket_url) = get_access_token()?;

    // Make a GET request to download the file

    let url = format!(
        "https://firebasestorage.googleapis.com/v0/b/{}/o/{}?alt=media",
        storage_bucket_url, file_name
    );
    let response = client
        .get(url)
        .header("Authorization", "Bearer ".to_string() + &access_token)
        .send()
        .await?;

    // Read the response content as bytes
    let file_content = response.bytes().await?.to_vec();

    let deserialized_data: Map<String, Value> =
        from_slice(&file_content).expect("Deserialization failed");

    Ok(deserialized_data)
}

use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};

#[derive(Debug, Serialize, Deserialize)]
struct ServiceAccount {
    #[serde(rename = "project_id")]
    project_id: String,
    #[serde(rename = "private_key_id")]
    private_key_id: String,
    #[serde(rename = "private_key")]
    private_key: String,
    #[serde(rename = "client_email")]
    client_email: String,
    #[serde(rename = "client_id")]
    client_id: String,
    #[serde(rename = "storage_url")]
    storage_url: String,
}

fn get_access_token() -> Result<(String, String), Box<dyn std::error::Error>> {
    // Read the service account file
    let mut file = File::open("firebase-service-account.json").expect("Unable to open the file");
    let mut contents = String::new();
    file.read_to_string(&mut contents)
        .expect("Unable to read the file");

    // Parse the service account JSON
    let service_account: ServiceAccount =
        from_slice(contents.as_bytes()).expect("Unable to parse service account JSON");

    // Create the JWT payload
    let claims = Claims {
        iss: service_account.client_email.clone(),
        sub: service_account.client_email.clone(),
        aud: format!("https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit"),
        iat: SystemTime::now()
            .duration_since(SystemTime:: UNIX_EPOCH)
            .expect("Unable to get UNIX EPOCH")
            .as_secs() as i64,
        exp: SystemTime::now()
        .duration_since(SystemTime:: UNIX_EPOCH)
        .expect("Unable to get UNIX EPOCH")
        .as_secs() as i64 + 180, // Token expires in 3 minutes
        uid: None,
    };

    // Encode the JWT using the private key
    let header = Header::new(Algorithm::RS256);
    let private_key = EncodingKey::from_rsa_pem(service_account.private_key.as_bytes())
        .expect("Unable to create private key from PEM");
    let token = encode(&header, &claims, &private_key).expect("Unable to encode JWT");

    // Return the access token
    Ok((token, service_account.storage_url))
}

#[derive(Debug, Serialize, Deserialize)]
struct Claims {
    iss: String,
    sub: String,
    aud: String,
    iat: i64,
    exp: i64,
    uid: Option<String>,
}
