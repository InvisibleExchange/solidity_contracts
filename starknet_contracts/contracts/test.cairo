%lang starknet
%builtins pedersen range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_block_number, get_block_timestamp
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import assert_not_zero, assert_le, assert_lt, unsigned_div_rem
from starkware.cairo.common.pow import pow
from starkware.cairo.common.hash import hash2
from contracts.interfaces.IAccount import IAccount

// ================================================================
// CONSTRUCTOR

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;

    return ();
}

@event
func pub_key(pub_key: felt) {
}

@external
func get_public_key{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    res: felt
) {
    let (msg_sender: felt) = get_caller_address();
    with_attr error_message("Msg sender is zero") {
        assert_not_zero(msg_sender);
    }

    // ? Get the sender's public key and update the pending deposit amount
    let (public_key) = IAccount.getPublicKey(contract_address=msg_sender);

    pub_key.emit(public_key);

    return (public_key,);
}
