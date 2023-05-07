from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.hash_state import (
    hash_init,
    hash_finalize,
    hash_update,
    hash_update_single,
)
from starkware.cairo.common.ec import EcPoint
from helpers.utils import Note, hash_note, hash_notes_array

struct Invisibl3Order {
    order_id: felt,
    expiration_timestamp: felt,
    token_spent: felt,
    token_received: felt,
    amount_spent: felt,
    amount_received: felt,
    fee_limit: felt,
    dest_received_address: felt,  // x coordinate of address
    dest_spent_blinding: felt,
    dest_received_blinding: felt,
}

// ? Transaction hash is basicaly just order_hash
func hash_transaction{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    invisibl3_order: Invisibl3Order, notes_in_len: felt, notes_in: Note*, refund_note: Note
) -> (hash: felt) {
    alloc_locals;

    let (local empty_arr) = alloc();
    let (hashed_notes_in_len: felt, hashed_notes_in: felt*) = hash_notes_array(
        notes_in_len, notes_in, 0, empty_arr
    );

    let (refund_note_hash: felt) = hash_note(refund_note);

    let (tx_hash: felt) = _hash_transaction_internal(
        hashed_notes_in_len, hashed_notes_in, refund_note_hash, invisibl3_order
    );

    return (tx_hash,);
}

func _hash_transaction_internal{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    hashes_in_len: felt, hashes_in: felt*, refund_note_hash: felt, invisibl3_order: Invisibl3Order
) -> (res: felt) {
    alloc_locals;

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state_ptr) = hash_init();
        let (hash_state_ptr) = hash_update(hash_state_ptr, hashes_in, hashes_in_len);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, refund_note_hash);

        let (hash_state_ptr) = hash_update_single(
            hash_state_ptr, invisibl3_order.expiration_timestamp
        );
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, invisibl3_order.token_spent);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, invisibl3_order.token_received);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, invisibl3_order.amount_spent);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, invisibl3_order.amount_received);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, invisibl3_order.fee_limit);
        let (hash_state_ptr) = hash_update_single(
            hash_state_ptr, invisibl3_order.dest_received_address
        );
        let (hash_state_ptr) = hash_update_single(
            hash_state_ptr, invisibl3_order.dest_spent_blinding
        );
        let (hash_state_ptr) = hash_update_single(
            hash_state_ptr, invisibl3_order.dest_received_blinding
        );
        let (res) = hash_finalize(hash_state_ptr);
        let pedersen_ptr = hash_ptr;
        return (res=res);
    }
}
