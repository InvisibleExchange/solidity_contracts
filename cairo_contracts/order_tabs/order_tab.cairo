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

struct OrderTab {
    tab_idx: felt,
    tab_header: TabHeader,
    base_amount: felt,
    quote_amount: felt,
    hash: felt,
}

struct TabHeader {
    expiration_timestamp: felt,
    is_perp: felt,
    is_smart_contract: felt,
    base_token: felt,
    quote_token: felt,
    base_blinding: felt,
    quote_blinding: felt,
    pub_key: felt,
    hash: felt,
}

func hash_order_tab{pedersen_ptr: HashBuiltin*, range_check_ptr}(order_tab: OrderTab*) -> felt {
    alloc_locals;

    let (base_commitment: felt) = hash2{hash_ptr=pedersen_ptr}(
        order_tab.base_amount, order_tab.tab_header.base_blinding
    );

    let (quote_commitment: felt) = hash2{hash_ptr=pedersen_ptr}(
        order_tab.quote_amount, order_tab.tab_header.quote_blinding
    );

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state_ptr) = hash_init();
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, order_tab.tab_header.hash);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, base_commitment);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, quote_commitment);

        let (res) = hash_finalize(hash_state_ptr);
        let pedersen_ptr = hash_ptr;
        return res;
    }
}

func hash_tab_header{pedersen_ptr: HashBuiltin*, range_check_ptr}(tab_header: TabHeader*) -> felt {
    alloc_locals;

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state_ptr) = hash_init();
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, tab_header.expiration_timestamp);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, tab_header.is_perp);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, tab_header.is_smart_contract);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, tab_header.base_token);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, tab_header.quote_token);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, tab_header.base_blinding);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, tab_header.quote_blinding);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, tab_header.pub_key);

        let (res) = hash_finalize(hash_state_ptr);
        let pedersen_ptr = hash_ptr;
        return res;
    }
}
