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
    // spot_note_info: SpotNotesInfo,
    // order_tab: OrderTab,
}

struct SpotNotesInfo {
    notes_in_len: felt,
    notes_in: Note*,
    refund_note: Note,
    dest_received_address: felt,  // x coordinate of address
    dest_received_blinding: felt,
}

func hash_transaction{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    invisibl3_order: Invisibl3Order, extra_hash_input: felt
) -> (res: felt) {
    alloc_locals;

    // & extra_hash_input is either a hash of SpotNotesInfo or a public key of OrderTab

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state_ptr) = hash_init();

        let (hash_state_ptr) = hash_update_single(
            hash_state_ptr, invisibl3_order.expiration_timestamp
        );
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, invisibl3_order.token_spent);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, invisibl3_order.token_received);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, invisibl3_order.amount_spent);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, invisibl3_order.amount_received);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, invisibl3_order.fee_limit);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, extra_hash_input);
        let (res) = hash_finalize(hash_state_ptr);
        let pedersen_ptr = hash_ptr;
        return (res=res);
    }
}

func hash_spot_note_info{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    spot_note_info: SpotNotesInfo*
) -> felt {
    alloc_locals;

    let (local empty_arr) = alloc();
    let (hashed_notes_in_len: felt, hashed_notes_in: felt*) = hash_notes_array(
        spot_note_info.notes_in_len, spot_note_info.notes_in, 0, empty_arr
    );

    let (refund_note_hash: felt) = hash_note(spot_note_info.refund_note);

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state_ptr) = hash_init();
        let (hash_state_ptr) = hash_update(hash_state_ptr, hashed_notes_in, hashed_notes_in_len);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, refund_note_hash);
        let (hash_state_ptr) = hash_update_single(
            hash_state_ptr, spot_note_info.dest_received_address
        );
        let (hash_state_ptr) = hash_update_single(
            hash_state_ptr, spot_note_info.dest_received_blinding
        );
        let (res) = hash_finalize(hash_state_ptr);
        let pedersen_ptr = hash_ptr;
        return res;
    }
}
