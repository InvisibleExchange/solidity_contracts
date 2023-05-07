%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.ec_point import EcPoint
from starkware.cairo.common.hash_state import (
    hash_init,
    hash_finalize,
    hash_update,
    hash_update_single,
)

from contracts.helpers.utils import Note, ExistenceProof, hash_note

func check_existence_proofs{pedersen_ptr: HashBuiltin*}(
    existence_proofs_len: felt, existence_proofs: ExistenceProof*, root: felt
) {
    if (existence_proofs_len == 0) {
        return ();
    }

    let existence_proof = existence_proofs[0];

    let (leaf: felt) = hash_note(existence_proof.note);
    assert leaf = existence_proof.note.hash;

    check_leaf_existence(
        leaf,
        root,
        existence_proof.auth_paths_pos_len,
        existence_proof.auth_paths_pos,
        existence_proof.auth_paths_len,
        existence_proof.auth_paths,
    );

    return check_existence_proofs(existence_proofs_len - 1, &existence_proofs[1], root);
}

// =====

func check_leaf_existence{pedersen_ptr: HashBuiltin*}(
    leaf: felt,
    root: felt,
    auth_paths_pos_len: felt,
    auth_paths_pos: felt*,
    auth_paths_len: felt,
    auth_paths: felt*,
) {
    let (computed_root: felt) = get_root(
        leaf, auth_paths_pos_len, auth_paths_pos, auth_paths_len, auth_paths
    );

    assert root = computed_root;
    return ();
}

func get_root{pedersen_ptr: HashBuiltin*}(
    leaf: felt,
    auth_paths_pos_len: felt,
    auth_paths_pos: felt*,
    auth_paths_len: felt,
    auth_paths: felt*,
) -> (res: felt) {
    tempvar diff = leaf - auth_paths[0];

    tempvar left = leaf - auth_paths_pos[0] * diff;
    tempvar right = auth_paths[0] + auth_paths_pos[0] * diff;

    let (h1: felt) = hash2{hash_ptr=pedersen_ptr}(left, right);

    return get_root_inner(
        h1, auth_paths_pos_len - 1, &auth_paths_pos[1], auth_paths_len - 1, &auth_paths[1]
    );
}

func get_root_inner{pedersen_ptr: HashBuiltin*}(
    hash: felt,
    auth_paths_pos_len: felt,
    auth_paths_pos: felt*,
    auth_paths_len: felt,
    auth_paths: felt*,
) -> (res: felt) {
    if (auth_paths_len == 0) {
        return (hash,);
    }

    tempvar diff = hash - auth_paths[0];

    tempvar left = hash - auth_paths_pos[0] * diff;
    tempvar right = auth_paths[0] + auth_paths_pos[0] * diff;

    let (h1: felt) = hash2{hash_ptr=pedersen_ptr}(left, right);

    return get_root_inner(
        h1, auth_paths_pos_len - 1, &auth_paths_pos[1], auth_paths_len - 1, &auth_paths[1]
    );
}

// ========================================================
