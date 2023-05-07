from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.hash_state import (
    hash_init,
    hash_finalize,
    hash_update,
    hash_update_single,
)
from starkware.cairo.common.ec import EcPoint

struct ExistenceProof {
    note: Note,
    auth_paths_pos_len: felt,
    auth_paths_pos: felt,
    auth_paths_len: felt,
    auth_paths: felt,
}

struct Note {
    address: EcPoint,
    token: felt,
    amount: felt,
    blinding_factor: felt,
    index: felt,
    hash: felt,
}

func hash_note{pedersen_ptr: HashBuiltin*}(note: Note) -> (hash: felt) {
    alloc_locals;

    let (note_hash: felt) = _hash_note_inputs(
        note.address, note.token, note.amount, note.blinding_factor
    );

    assert note_hash = note.hash;

    return (note_hash,);
}

func hash_notes_array{pedersen_ptr: HashBuiltin*}(
    notes_len: felt, notes: Note*, arr_len: felt, arr: felt*
) -> (arr_len: felt, arr: felt*) {
    alloc_locals;
    if (notes_len == 0) {
        return (arr_len, arr);
    }

    let (note_hash: felt) = hash_note(notes[0]);

    assert arr[arr_len] = note_hash;

    return hash_notes_array(notes_len - 1, &notes[1], arr_len + 1, arr);
}

func hash_notes_array_from_existence_proofs{pedersen_ptr: HashBuiltin*}(
    existence_proofs_len: felt, existence_proofs: ExistenceProof*, arr_len: felt, arr: felt*
) -> (arr_len: felt, arr: felt*) {
    alloc_locals;
    if (existence_proofs_len == 0) {
        return (arr_len, arr);
    }

    let (note_hash: felt) = hash_note(existence_proofs[0].note);

    assert arr[arr_len] = note_hash;

    return hash_notes_array_from_existence_proofs(
        existence_proofs_len - 1, &existence_proofs[1], arr_len + 1, arr
    );
}

// & This function is used to generate a hash of a new note before actually creating the note
func _hash_note_inputs{pedersen_ptr: HashBuiltin*}(
    address: EcPoint, token: felt, amount: felt, blinding_factor: felt
) -> (hash: felt) {
    let (commitment: felt) = hash2{hash_ptr=pedersen_ptr}(amount, blinding_factor);

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state_ptr) = hash_init();
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, address.x);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, token);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, commitment);

        let (res) = hash_finalize(hash_state_ptr);
        let pedersen_ptr = hash_ptr;
        return (hash=res);
    }
}

func sum_notes(notes_len: felt, notes: Note*, token: felt, sum: felt) -> (sum: felt) {
    alloc_locals;

    if (notes_len == 0) {
        return (sum,);
    }

    let note: Note = notes[0];
    assert note.token = token;

    let sum = sum + note.amount;

    return sum_notes(notes_len - 1, &notes[1], token, sum);
}
