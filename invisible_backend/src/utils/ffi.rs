use std::{
    ffi::{CStr, CString},
    fmt::Debug,
    os::raw::c_char,
    slice,
    str::FromStr,
};

use num_bigint::{BigInt, BigUint, ToBigUint};

use crate::{
    transactions::limit_order::LimitOrder,
    utils::crypto_utils::{pedersen, pedersen_on_vec, EcPoint, Signature},
};

use super::notes::Note;

// ? LIMIT ORDERS =============================================================================

#[repr(C)]
#[derive(Debug, Clone)]
pub struct FfiLimitOrder {
    pub order_id: u64,
    pub expiration_timestamp: u64,
    pub token_spent: u64,
    pub token_received: u64,
    pub amount_spent: u64,
    pub amount_received: u64,
    pub fee_limit: u64,
    pub dest_received_address_x: *const c_char,
    pub dest_received_address_y: *const c_char,
    pub dest_spent_blinding: *const c_char,
    pub dest_received_blinding: *const c_char,
    pub notes_in: *mut FfiNote,
    pub notes_in_len: usize,
    pub refund_note: Option<FfiNote>,
}

#[no_mangle]
pub extern "C" fn new_limit_order(
    order_id: u64,
    expiration_timestamp: u64,
    token_spent: u64,
    token_received: u64,
    amount_spent: u64,
    amount_received: u64,
    fee_limit: u64,
    // Addresses
    dest_received_address_x: *const c_char,
    dest_received_address_y: *const c_char,
    // blindings
    dest_spent_blinding: *const c_char,
    dest_received_blinding: *const c_char,
    // notes
    notes_in: *mut FfiNote,
    notes_in_len: usize,
    refund_note: Option<FfiNote>,
) -> *mut LimitOrder {
    unsafe {
        let dest_received_address_x = CStr::from_ptr(dest_received_address_x);
        let dest_received_address_x =
            BigInt::from_str(dest_received_address_x.to_str().unwrap()).unwrap();
        let dest_received_address_y = CStr::from_ptr(dest_received_address_y);
        let dest_received_address_y =
            BigInt::from_str(dest_received_address_y.to_str().unwrap()).unwrap();
        let dest_received_address = EcPoint {
            x: dest_received_address_x,
            y: dest_received_address_y,
        };

        let dest_spent_blinding = CStr::from_ptr(dest_spent_blinding);
        let dest_spent_blinding = BigUint::from_str(dest_spent_blinding.to_str().unwrap()).unwrap();

        let dest_received_blinding = CStr::from_ptr(dest_received_blinding);
        let dest_received_blinding =
            BigUint::from_str(dest_received_blinding.to_str().unwrap()).unwrap();

        let notes_in = get_notes(notes_in, notes_in_len);

        let refund_note_ = if refund_note.is_some() {
            Some(ffi_note_to_note(&refund_note.unwrap()))
        } else {
            None
        };

        let order = LimitOrder::new(
            order_id,
            expiration_timestamp,
            token_spent,
            token_received,
            amount_spent,
            amount_received,
            fee_limit,
            dest_received_address,
            dest_spent_blinding,
            dest_received_blinding,
            notes_in,
            refund_note_,
        );

        return Box::into_raw(Box::new(order));
    }
}

#[repr(C)]
pub struct SigType {
    pub sig_r: *const c_char,
    pub sig_s: *const c_char,
}

#[no_mangle]
pub extern "C" fn verify_limit_order_sig(
    order: *mut LimitOrder,
    sig_r: *const c_char,
    sig_s: *const c_char,
) {
    unsafe {
        let order = &mut *order;

        let sig_r = CStr::from_ptr(sig_r);
        let sig_r = String::from(sig_r.to_str().unwrap());

        let sig_s = CStr::from_ptr(sig_s);
        let sig_s = String::from(sig_s.to_str().unwrap());

        let sig = Signature { r: sig_r, s: sig_s };
        order.verify_order_signature(&sig).unwrap();

        println!("signature verified successfully");
    }
}

#[no_mangle]
pub extern "C" fn convert_limit_order(order: *mut LimitOrder) -> FfiLimitOrder {
    unsafe {
        let order = &mut *order;

        //? dest_recived_address
        let dra_x = big_uint_to_str_ptr(&order.dest_received_address.x.to_biguint().unwrap());
        let dra_y = big_uint_to_str_ptr(&order.dest_received_address.y.to_biguint().unwrap());

        // ? blindings
        let dest_spent_blinding =
            big_uint_to_str_ptr(&order.dest_spent_blinding.to_biguint().unwrap());
        let dest_received_blinding =
            big_uint_to_str_ptr(&order.dest_received_blinding.to_biguint().unwrap());

        let mut notes_in = order
            .notes_in
            .iter()
            .map(|note| {
                let note = note_to_ffi_note(&note);
                return note;
            })
            .collect::<Vec<FfiNote>>();

        let refund_note = if order.refund_note.is_some() {
            Some(note_to_ffi_note(&order.refund_note.as_ref().unwrap()))
        } else {
            None
        };

        let ffi_limit_order = FfiLimitOrder {
            order_id: order.order_id,
            expiration_timestamp: order.expiration_timestamp,
            token_spent: order.token_spent,
            token_received: order.token_received,
            amount_spent: order.amount_spent,
            amount_received: order.amount_received,
            fee_limit: order.fee_limit,
            dest_received_address_x: dra_x,
            dest_received_address_y: dra_y,
            dest_spent_blinding,
            dest_received_blinding,
            notes_in: notes_in.as_mut_ptr(),
            notes_in_len: notes_in.len(),
            refund_note,
        };

        return ffi_limit_order;
    }
}
// ? NOTES ====================================================================================

#[repr(C)]
#[derive(Debug, Clone)]
pub struct FfiNote {
    pub index: u64,
    pub address_x: *const c_char,
    pub address_y: *const c_char,
    pub token: u64,
    pub amount: u64,
    pub blinding: *const c_char,
}

#[no_mangle]
pub extern "C" fn new_note(
    index: u64,
    address_x: *const c_char,
    address_y: *const c_char,
    token: u64,
    amount: u64,
    blinding: *const c_char,
) -> *mut Note {
    unsafe {
        let addr_x = CStr::from_ptr(address_x).to_string_lossy().into_owned();
        let addr_y = CStr::from_ptr(address_y).to_string_lossy().into_owned();

        let addr_x = BigInt::from_str(&addr_x).unwrap();
        let addr_y = BigInt::from_str(&addr_y).unwrap();

        let blinding = CStr::from_ptr(blinding).to_string_lossy().into_owned();
        let blinding = BigUint::from_str(&blinding).unwrap();

        let address = EcPoint {
            x: addr_x,
            y: addr_y,
        };

        return Box::into_raw(Box::new(Note::new(index, address, token, amount, blinding)));
    }
}

#[no_mangle]
pub extern "C" fn free_note_ptr(ptr: *mut Note) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        let _ = Box::from_raw(ptr);
    }
}

// ? PEDERSEN HASH =============================================================================
#[no_mangle]
pub extern "C" fn pedersen_hash_binding(x: *const c_char, y: *const c_char) -> *const c_char {
    unsafe {
        let x = CStr::from_ptr(x).to_string_lossy().into_owned();
        let y = CStr::from_ptr(y).to_string_lossy().into_owned();

        let x = BigUint::from_str(&x).unwrap();
        let y = BigUint::from_str(&y).unwrap();

        let hash = pedersen(&x, &y);
        let hash_str = CString::new(hash.to_string()).unwrap();

        let hash = hash_str.into_raw();

        return hash;
    }
}

#[no_mangle]
pub extern "C" fn pedersen_hash_on_vec_binding(
    arr: *const *const c_char,
    arr_len: u32,
) -> *const c_char {
    unsafe {
        let arr: &[*const c_char] = slice::from_raw_parts(arr, arr_len as usize)
            .try_into()
            .unwrap();

        let arr: Vec<BigUint> = arr
            .iter()
            .map(|key| {
                let key = CStr::from_ptr(*key);
                let key = BigUint::from_str(key.to_str().unwrap()).unwrap();
                key
            })
            .collect::<Vec<BigUint>>();
        let arr = arr.iter().map(|key| key).collect();

        let hash = pedersen_on_vec(&arr);
        let hash = CString::new(hash.to_string()).unwrap();

        let hash = hash.into_raw();

        return hash;
    }
}

// HELPERS ====================================================================================

fn get_notes(data: *mut FfiNote, len: usize) -> Vec<Note> {
    let ffi_notes = unsafe { slice::from_raw_parts(data, len as usize) };

    let mut notes: Vec<Note> = Vec::new();

    for ffi_note in ffi_notes.iter() {
        let note = ffi_note_to_note(ffi_note);

        notes.push(note);
    }

    return notes;
}

fn ffi_note_to_note(ffi_note: &FfiNote) -> Note {
    unsafe {
        let addr_x = CStr::from_ptr(ffi_note.address_x);
        let addr_x = BigInt::from_str(addr_x.to_str().unwrap()).unwrap();

        let addr_y = CStr::from_ptr(ffi_note.address_y);
        let addr_y = BigInt::from_str(addr_y.to_str().unwrap()).unwrap();

        let addr = EcPoint {
            x: addr_x,
            y: addr_y,
        };

        let blinding = CStr::from_ptr(ffi_note.blinding);
        let blinding = BigUint::from_str(blinding.to_str().unwrap()).unwrap();

        let note = Note::new(
            ffi_note.index,
            addr,
            ffi_note.token,
            ffi_note.amount,
            blinding,
        );

        return note;
    }
}

fn note_to_ffi_note(note: &Note) -> FfiNote {
    let addr_x = big_uint_to_str_ptr(&note.address.x.to_biguint().unwrap());
    let addr_y = big_uint_to_str_ptr(&note.address.y.to_biguint().unwrap());

    let blinding = big_uint_to_str_ptr(&note.blinding);

    let ffi_note = FfiNote {
        index: note.index,
        address_x: addr_x,
        address_y: addr_y,
        token: note.token,
        amount: note.amount,
        blinding,
    };

    return ffi_note;
}

fn big_uint_to_str_ptr(big_uint: &BigUint) -> *const c_char {
    let big_uint_str = CString::new(big_uint.to_string()).unwrap();
    let big_uint_ptr = big_uint_str.as_ptr();
    std::mem::forget(big_uint_str);

    return big_uint_ptr;
}
