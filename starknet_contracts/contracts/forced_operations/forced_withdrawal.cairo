%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.starknet.common.syscalls import get_block_number, get_block_timestamp
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import assert_not_zero, assert_le, assert_lt, unsigned_div_rem
from starkware.cairo.common.ec_point import EcPoint
from starkware.cairo.common.ec import ec_add
from starkware.starknet.common.syscalls import get_tx_info

from contracts.helpers.token_info import (
    scale_up,
    scale_down,
    get_token_id,
    register_token,
    get_token_address,
    get_token_decimals,
)
from contracts.helpers.utils import (
    Note,
    ExistenceProof,
    hash_note,
    hash_notes_array_from_existence_proofs,
)

from existence_checks import check_existence_proofs

// ------------------------------

@event
func forced_withdrawal_started(
    address: felt, note_hashes_len: felt, note_hashes: felt*, timestamp: felt
) {
}

// ------------------------------

@storage_var
func s_root() -> (root: felt) {
}

// maps a hash to whether it has been verified in start_forced_withdrawal()
@storage_var
func s_fw_hash_to_bool(hash: felt) -> (res: felt) {
}

// maps a hash to the note that hash belongs to (if it has been verified in start_forced_withdrawal())
@storage_var
func s_fw_hash_to_note(hash: felt) -> (note: Note) {
}

struct HashesArray {
    hashes_len: felt,
    hashes: felt*,
}
// maps an address to an array of hashes that map to notes in s_fw_hash_to_note
@storage_var
func s_fw_address_to_hash(address: felt) -> (HashesArray,) {
}

@storage_var
func s_fw_idx_to_address(ids: felt) -> (address: felt) {
}

@storage_var
func s_num_forced_withdrawals() -> (res: felt) {
}

// ------------------------------

// & Forced withdrawals work as follows:
// 1. User calls `forced_withdraw` with an array of ExistenceProofs
//    an ExistenceProof contains the note information and the Merkle proof
// 2. The contract verifies the proofs and checks that the notes exist in the state (the state at previous batch update)
// 3. The contract verifies the signature for all the notes (pub_key_sum - to save gas) proving the user owns the funds
// 4. If everything is verified successfuly the contract stores the note hashes and notes in storage
// 5. After the new batch_update proof is posted and verified,
//    the system checks that the notes are still in the state and were not yet spent.
// 6. If the notes havent been spent, they are added to the users pending withdrawal balance
// 7. The system must then keep track of these forced_withdrawals and update the off-chain state accordingly

@external
func start_forced_withdrawal{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    existence_proofs_len: felt,
    existence_proofs: ExistenceProof*,
    token: felt,
    signature: (felt, felt),
) {
    let pub_key_sum: EcPoint = sum_pub_keys(existence_proofs_len, existence_proofs, EcPoint(0, 0));

    let (
        note_hashes_len: felt, note_hashes: felt*, withdrawal_hash: felt
    ) = _forced_withdrawal_hash(existence_proofs_len, existence_proofs, 0, token);

    // Todo: verify the signature with the pub_key_sum

    let (root: felt) = s_root.read();
    check_existence_proofs(existence_proofs_len, existence_proofs, root);

    let (n_forced_withdrawals: felt) = s_num_forced_withdrawals.read();
    s_num_forced_withdrawals.write(n_forced_withdrawals + 1);

    let (msg_sender) = get_caller_address();
    s_fw_idx_to_address.write(n_forced_withdrawals, msg_sender);

    // ? store the notes and hashes to storage
    let hashes_array = HashesArray(note_hashes_len, note_hashes);
    s_fw_address_to_hash.write(hashes_array);

    store_fw_notes(existence_proofs_len, existence_proofs);

    // ? Emit event
    let (timestamp: felt) = get_block_timestamp();
    forced_withdrawal_started.emit(msg_sender, note_hashes_len, note_hashes, timestamp);

    return ();
}

// ------------------------------

func sum_pub_keys{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    existence_proofs_len: felt, existence_proofs: ExistenceProof*, sum: EcPoint
) -> EcPoint {
    if (existence_proofs_len == 0) {
        return (sum);
    }

    let existence_proof = existence_proofs[0];

    let (pub_key_sum: EcPoint) = ec_add(sum, existence_proof.note.address);

    return sum_pub_keys(existence_proofs_len - 1, &existence_proofs[1], pub_key_sum);
}

func sum_amounts{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    existence_proofs_len: felt, existence_proofs: ExistenceProof*, sum: felt
) -> felt {
    if (existence_proofs_len == 0) {
        return (sum);
    }

    let existence_proof = existence_proofs[0];

    let amount_sum = sum + existence_proof.note.amount;

    return sum_amounts(existence_proofs_len - 1, &existence_proofs[1], amount_sum);
}

func _forced_withdrawal_hash{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    existence_proofs_len: felt, existence_proofs: ExistenceProof*, hash: felt, token: felt
) -> (note_hashes_len: felt, note_hashes: felt*, hash: felt) {
    // & Recursively hashes the inputs and checks the token matches the withdrawal token
    alloc_locals;

    let (local empty_arr: felt*) = alloc();
    let (note_hashes_len: felt, note_hashes: felt*) = note_hashes_array_from_existence_proofs(
        existence_proofs_len, existence_proofs, 0, empty_arr
    );

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state_ptr) = hash_init();
        let (hash_state_ptr) = hash_update(hash_state_ptr, note_hashes, note_hashes_len);
        let (hash) = hash_finalize(hash_state_ptr);
        let pedersen_ptr = hash_ptr;
        return (note_hashes_len, note_hashes, hash);
    }
}

func store_fw_notes{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    existence_proofs_len: felt, existence_proofs: ExistenceProof*
) {
    if (existence_proofs_len == 0) {
        return ();
    }

    let note = existence_proofs[0].note;
    s_fw_hash_to_bool.write(hash=note.hash, value=1);

    s_fw_hash_to_note.write(hash=note.hash, value=note);

    return store_fw_notes(existence_proofs_len - 1, &existence_proofs[1]);
}
