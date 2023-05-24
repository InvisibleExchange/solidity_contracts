use std::sync::Arc;

use invisible_backend::utils::{
    firestore::{create_session, start_delete_position_thread},
    storage::BackupStorage,
};
use parking_lot::Mutex;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    //

    // 1684502386098572560865500250041581148646578677955444760400258625865572888023

    let backup = BackupStorage::new();
    let session = create_session();

    let handle = start_delete_position_thread(
        &Arc::new(Mutex::new(session)),
        &Arc::new(Mutex::new(backup)),
        "1684502386098572560865500250041581148646578677955444760400258625865572888023".to_string(),
        "1".to_string(),
    );

    handle.join().unwrap();

    Ok(())
}
