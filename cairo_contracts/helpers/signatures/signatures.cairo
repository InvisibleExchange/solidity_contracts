from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.ec import ec_add
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.ec_point import EcPoint

from helpers.utils import Note
from perpetuals.order.order_structs import PerpOrder, OpenOrderFields, PerpPosition

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

func verify_sig{ecdsa_ptr: SignatureBuiltin*}(tx_hash: felt, pub_key: EcPoint) {
    alloc_locals;

    local sig_r: felt;
    local sig_s: felt;
    %{
        ids.sig_r = int(signature[0]) 
        ids.sig_s = int(signature[1])
    %}

    verify_ecdsa_signature(
        message=tx_hash, public_key=pub_key.x, signature_r=sig_r, signature_s=sig_s
    );

    return ();
}

// * PERPETUAL SIGNATURES BELOW * #

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
        public_key=position.position_address,
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
