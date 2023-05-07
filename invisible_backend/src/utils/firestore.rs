use std::{
    sync::Arc,
    thread::{spawn, JoinHandle},
};

use firestore_db_and_auth::{
    documents::{self},
    Credentials, ServiceSession,
};
use num_bigint::BigUint;
use num_traits::FromPrimitive;
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};

use crate::{
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

pub fn create_session() -> ServiceSession {
    let mut cred =
        Credentials::from_file("firebase-service-account.json").expect("Read credentials file");
    cred.download_google_jwks().expect("Download Google JWKS");

    let session = ServiceSession::new(cred).expect("Create a service account session");

    session
}

pub fn retry_failed_updates(
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: Arc<Mutex<BackupStorage>>,
) -> Result<(), Box<dyn std::error::Error>> {
    let s = backup_storage.lock();
    let notes_info = s.read_notes();
    let positions_info = s.read_positions();
    let spot_fills = s.read_spot_fills();
    let perp_fills = s.read_perp_fills();

    s.clear_db().unwrap();

    let sess = session.lock();

    let notes = notes_info.0;
    for note in notes {
        store_new_note(&sess, backup_storage.clone(), &note);
    }
    let removable_info = notes_info.1;
    for info in removable_info {
        delete_note_at_address(&sess, &info.1.to_string(), &info.0.to_string());
    }

    let positions = positions_info.0;
    for position in positions {
        store_new_position(&sess, backup_storage.clone(), &position);
    }
    let removable_info = positions_info.1;
    for info in removable_info {
        delete_position_at_address(&sess, &info.1.to_string(), &info.0.to_string());
    }

    for fill in spot_fills {
        store_new_spot_fill(&sess, backup_storage.clone(), &fill);
    }

    for fill in perp_fills {
        store_new_perp_fill(&sess, backup_storage.clone(), &fill);
    }

    Ok(())
}

// NOTES ------------- -------------- ---------------- ----------------- ----------------

// TODO: If we get this error: ERROR: APIError(404, "No document to update: then we don't store it to backup storage
// TODO: Store failed deletes as well

fn delete_note_at_address(session: &ServiceSession, address: &str, idx: &str) {
    // & address is the x coordinate in string format and idx is the index in string format

    let delete_path = format!("notes/{}/indexes/{}", address, idx);
    let r = documents::delete(session, delete_path.as_str(), true);
    if let Err(e) = r {
        println!("Error deleting note document. ERROR: {:?}", e);
    }
}

fn store_new_note(
    session: &ServiceSession,
    backup_storage: Arc<Mutex<BackupStorage>>,
    note: &Note,
) {
    let obj = FirebaseNoteObject::from_note(note);

    let write_path = format!("notes/{}/indexes", note.address.x.to_string().as_str());
    let _res = documents::write(
        session,
        write_path.as_str(),
        Some(note.index.to_string()),
        &obj,
        documents::WriteOptions::default(),
    );

    if let Err(_e) = _res {
        let s = backup_storage.lock();
        if let Err(e) = s.store_note(note) {
            println!("Error storing note in backup storage. ERROR: {:?}", e);
        };
        drop(s);
    }
}

// POSITIONS ------------- -------------- ---------------- ----------------- ----------------

fn delete_position_at_address(session: &ServiceSession, address: &str, idx: &str) {
    // & address is the x coordinate in string format and idx is the index in string format

    let delete_path = format!("positions/{}/indexes/{}", address, idx);
    let r = documents::delete(session, delete_path.as_str(), true);
    if let Err(e) = r {
        println!("Error deleting position document. ERROR: {:?}", e);
    }
}

fn store_new_position(
    session: &ServiceSession,
    backup_storage: Arc<Mutex<BackupStorage>>,
    position: &PerpPosition,
) {
    let write_path = format!(
        "positions/{}/indexes",
        position.position_address.to_string(),
    );

    let _res = documents::write(
        session,
        write_path.as_str(),
        Some(position.index.to_string()),
        position,
        documents::WriteOptions::default(),
    );

    if let Err(_e) = _res {
        let s = backup_storage.lock();
        if let Err(e) = s.store_position(position) {
            println!("Error storing position in backup storage. ERROR: {:?}", e);
        };
        drop(s);
    }
}

// FILLS   -------------- ---------------- ----------------- ----------------

fn store_new_spot_fill(
    session: &ServiceSession,
    backup_storage: Arc<Mutex<BackupStorage>>,
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
    backup_storage: Arc<Mutex<BackupStorage>>,
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
    backup_storage: Arc<Mutex<BackupStorage>>,
) -> JoinHandle<()> {
    let s = Arc::clone(&session);

    let handle = spawn(move || {
        let session_ = s.lock();
        // let backup_storage = backup_storage.lock();

        store_new_note(&session_, backup_storage, &note);
        drop(session_);
    });
    return handle;
}

pub fn start_delete_note_thread(
    session: &Arc<Mutex<ServiceSession>>,
    address: String,
    idx: String,
) -> JoinHandle<()> {
    // TODO: BACKUP

    let s = Arc::clone(&session);
    let handle = spawn(move || {
        let session_ = s.lock();
        delete_note_at_address(&session_, address.as_str(), idx.as_str());
        drop(session_);
    });
    return handle;
}

// POSITIONS

pub fn start_add_position_thread(
    position: PerpPosition,
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: Arc<Mutex<BackupStorage>>,
) -> JoinHandle<()> {
    let s = Arc::clone(&session);

    let handle = spawn(move || {
        let session_ = s.lock();

        store_new_position(&session_, backup_storage, &position);
        drop(session_);
    });
    return handle;
}

pub fn start_delete_position_thread(
    session: &Arc<Mutex<ServiceSession>>,
    address: String,
    idx: String,
) -> JoinHandle<()> {
    let s = Arc::clone(&session);
    let handle = spawn(move || {
        let session_ = s.lock();
        delete_position_at_address(&session_, address.as_str(), idx.as_str());
        drop(session_);
    });
    return handle;
}

// FILLS

pub fn start_add_fill_thread(
    fill_info: FillInfo,
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: Arc<Mutex<BackupStorage>>,
) -> JoinHandle<()> {
    let s = Arc::clone(&session);

    let handle = spawn(move || {
        let session_ = s.lock();

        store_new_spot_fill(&session_, backup_storage, &fill_info);
        drop(session_);
    });
    return handle;
}

pub fn start_add_perp_fill_thread(
    fill_info: PerpFillInfo,
    session: &Arc<Mutex<ServiceSession>>,
    backup_storage: Arc<Mutex<BackupStorage>>,
) -> JoinHandle<()> {
    let s = Arc::clone(&session);

    let handle = spawn(move || {
        let session_ = s.lock();

        store_new_perp_fill(&session_, backup_storage, &fill_info);
        drop(session_);
    });

    return handle;
}
