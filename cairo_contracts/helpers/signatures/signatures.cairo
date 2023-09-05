from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.ec import ec_add
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.ec_point import EcPoint

from starkware.cairo.common.hash_state import (
    hash_init,
    hash_finalize,
    hash_update,
    hash_update_single,
)

from helpers.utils import Note
from perpetuals.order.order_structs import (
    PerpOrder,
    OpenOrderFields,
    CloseOrderFields,
    PerpPosition,
)

from perpetuals.order.order_hash import _hash_close_order_fields

// * SPOT SIGNATURES * //
func verify_spot_signature{ecdsa_ptr: SignatureBuiltin*}(
    tx_hash: felt, notes_len: felt, notes: Note*
) -> (pub_key_sum: EcPoint) {
    alloc_locals;

    let (pub_key_sum: EcPoint) = sum_pub_keys(notes_len, notes, EcPoint(0, 0));

    local sig_r: felt;
    local sig_s: felt;
    %{
        ids.sig_r = int(signature[0]) 
        ids.sig_s = int(signature[1])
    %}

    verify_ecdsa_signature(
        message=tx_hash, public_key=pub_key_sum.x, signature_r=sig_r, signature_s=sig_s
    );

    return (pub_key_sum,);
}

func verify_spot_tab_order_signature{ecdsa_ptr: SignatureBuiltin*}(
    tx_hash: felt, tab_pub_key: felt
) {
    alloc_locals;

    local sig_r: felt;
    local sig_s: felt;
    %{
        ids.sig_r = int(signature[0])
        ids.sig_s = int(signature[1])
    %}

    verify_ecdsa_signature(
        message=tx_hash, public_key=tab_pub_key, signature_r=sig_r, signature_s=sig_s
    );

    return ();
}

func verify_sig{ecdsa_ptr: SignatureBuiltin*}(tx_hash: felt, pub_key: EcPoint) {
    alloc_locals;

    local sig_r: felt;
    local sig_s: felt;
    %{
        ids.sig_r = int(signature[0]) 
        ids.sig_s = int(signature[1])
    %}

    return verify_ecdsa_signature(
        message=tx_hash, public_key=pub_key.x, signature_r=sig_r, signature_s=sig_s
    );

    return ();
}

// * PERPETUAL SIGNATURES * //

func verify_open_order_signature{ecdsa_ptr: SignatureBuiltin*}(
    order_hash: felt, notes_len: felt, notes: Note*
) -> (pub_key_sum: EcPoint) {
    alloc_locals;

    let (pub_key_sum: EcPoint) = sum_pub_keys(notes_len, notes, EcPoint(0, 0));

    local sig_r: felt;
    local sig_s: felt;
    %{
        ids.sig_r = int(signature[0]) 
        ids.sig_s = int(signature[1])
    %}

    verify_ecdsa_signature(
        message=order_hash, public_key=pub_key_sum.x, signature_r=sig_r, signature_s=sig_s
    );

    return (pub_key_sum,);
}

func verify_order_signature{pedersen_ptr: HashBuiltin*, ecdsa_ptr: SignatureBuiltin*}(
    order_hash: felt, position: PerpPosition
) {
    alloc_locals;

    local sig_r: felt;
    local sig_s: felt;
    %{
        ids.sig_r = int(signature[0]) 
        ids.sig_s = int(signature[1])
    %}

    verify_ecdsa_signature(
        message=order_hash,
        public_key=position.position_header.position_address,
        signature_r=sig_r,
        signature_s=sig_s,
    );

    return ();
}

func verify_margin_change_signature{pedersen_ptr: HashBuiltin*, ecdsa_ptr: SignatureBuiltin*}(
    msg_hash: felt, notes_in_len: felt, notes_in: Note*, position_address: felt, is_increase: felt
) {
    alloc_locals;

    local sig_r: felt;
    local sig_s: felt;
    %{
        ids.sig_r = int(signature[0]) 
        ids.sig_s = int(signature[1])
    %}

    if (is_increase == 1) {
        let (pub_key_sum: EcPoint) = sum_pub_keys(notes_in_len, notes_in, EcPoint(0, 0));

        // %{ print(ids.msg_hash,ids.pub_key_sum.x, signature ) %}

        verify_ecdsa_signature(
            message=msg_hash, public_key=pub_key_sum.x, signature_r=sig_r, signature_s=sig_s
        );
    } else {
        // %{ print(ids.msg_hash,ids.position_address, signature) %}

        verify_ecdsa_signature(
            message=msg_hash, public_key=position_address, signature_r=sig_r, signature_s=sig_s
        );
    }

    return ();
}

// * ORDER TAB SIGNATURES * //
func verify_open_order_tab_signature{ecdsa_ptr: SignatureBuiltin*, pedersen_ptr: HashBuiltin*}(
    prev_tab_hash: felt,
    new_tab_hash: felt,
    base_notes_len: felt,
    base_notes: Note*,
    base_refund_hash: felt,
    quote_notes_len: felt,
    quote_notes: Note*,
    quote_refund_hash: felt,
) {
    alloc_locals;

    // & header_hash = H({prev_tab_hash, new_tab_hash, base_refund_note_hash, quote_refund_note_hash})

    let (pub_key_sum: EcPoint) = sum_pub_keys(base_notes_len, base_notes, EcPoint(0, 0));
    let (pub_key_sum: EcPoint) = sum_pub_keys(quote_notes_len, quote_notes, pub_key_sum);

    let hash = _get_open_tab_hash_internal(
        prev_tab_hash, new_tab_hash, base_refund_hash, quote_refund_hash
    );

    local sig_r: felt;
    local sig_s: felt;
    %{
        signature = current_order["signature"]
        ids.sig_r = int(signature[0]) 
        ids.sig_s = int(signature[1])
    %}

    verify_ecdsa_signature(
        message=hash, public_key=pub_key_sum.x, signature_r=sig_r, signature_s=sig_s
    );

    return ();
}

func verify_close_order_tab_signature{ecdsa_ptr: SignatureBuiltin*, pedersen_ptr: HashBuiltin*}(
    tab_hash: felt,
    base_amount_change: felt,
    quote_amount_change: felt,
    base_close_order_fields: CloseOrderFields,
    quote_close_order_fields: CloseOrderFields,
    pub_key: felt,
) {
    alloc_locals;

    let (base_fields_hash: felt) = _hash_close_order_fields(base_close_order_fields);
    let (quote_fields_hash: felt) = _hash_close_order_fields(quote_close_order_fields);

    let hash = _get_close_tab_hash_internal(
        tab_hash, base_amount_change, quote_amount_change, base_fields_hash, quote_fields_hash
    );

    local sig_r: felt;
    local sig_s: felt;
    %{
        signature = current_order["signature"]
        ids.sig_r = int(signature[0]) 
        ids.sig_s = int(signature[1])
    %}

    verify_ecdsa_signature(message=hash, public_key=pub_key, signature_r=sig_r, signature_s=sig_s);

    return ();
}

// helpers
func _get_open_tab_hash_internal{pedersen_ptr: HashBuiltin*}(
    prev_tab_hash: felt, new_tab_hash: felt, base_refund_hash: felt, quote_refund_hash: felt
) -> felt {
    alloc_locals;

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state_ptr) = hash_init();
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, prev_tab_hash);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, new_tab_hash);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, base_refund_hash);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, quote_refund_hash);

        let (res) = hash_finalize(hash_state_ptr);
        let pedersen_ptr = hash_ptr;
        return res;
    }
}

func _get_close_tab_hash_internal{pedersen_ptr: HashBuiltin*}(
    tab_hash: felt,
    base_amount_change: felt,
    quote_amount_change: felt,
    base_fields_hash: felt,
    quote_fields_hash: felt,
) -> felt {
    alloc_locals;
    // & header_hash = H({order_tab_hash, base_amount_change, quote_amount_change, base_close_order_fields.hash, quote_close_order_fields.hash})

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state_ptr) = hash_init();
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, tab_hash);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, base_amount_change);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, quote_amount_change);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, base_fields_hash);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, quote_fields_hash);

        let (res) = hash_finalize(hash_state_ptr);
        let pedersen_ptr = hash_ptr;
        return res;
    }
}

// HELPERS ================================================= #

func sum_pub_keys{ecdsa_ptr: SignatureBuiltin*}(
    notes_len: felt, notes: Note*, pub_key_sum: EcPoint
) -> (pk_sum: EcPoint) {
    if (notes_len == 0) {
        return (pub_key_sum,);
    }

    let note: Note = notes[0];

    let (pub_key_sum: EcPoint) = ec_add(note.address, pub_key_sum);

    return sum_pub_keys(notes_len - 1, &notes[1], pub_key_sum);
}
