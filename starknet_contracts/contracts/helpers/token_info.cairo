%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import (
    assert_not_zero,
    assert_le,
    assert_lt,
    unsigned_div_rem,
    split_felt,
)
from starkware.cairo.common.pow import pow

from openzeppelin.token.erc20.IERC20 import IERC20

@event
func new_token_registered_event(address: felt, token_id: felt, scale_factor: felt) {
}

// & token info: | tokenId {64 bits} | scale_factor {8 bits} |
@storage_var
func s_address_to_token_id(address: felt) -> (res: felt) {
}
@storage_var
func s_token_id_to_address(token_id: felt) -> (res: felt) {
}
@storage_var
func s_token_id_to_scale_factor(token_id: felt) -> (res: felt) {
}

//
// sacle-factor = onchain_decimals - offchain_decimals
// If token has 18 decimals onchain and 6 decimals offchain then scale factor is 12
//

// & ===== Scaling functions ===================================
// ! possibly rename to scale and rescale
func scale_down{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    amount: felt, token_id: felt
) -> felt {
    alloc_locals;

    let (scale_factor_: felt) = s_token_id_to_scale_factor.read(token_id=token_id);

    // check that token_id exists
    assert_not_zero(scale_factor_);

    let (multiplier: felt) = pow(10, scale_factor_);
    let (scaled_amount: felt, _) = unsigned_div_rem(amount, multiplier);

    return scaled_amount;
}

func scale_up{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    amount: felt, token_id: felt
) -> felt {
    alloc_locals;

    let (scale_factor_: felt) = s_token_id_to_scale_factor.read(token_id=token_id);

    // check that token_id exists
    assert_not_zero(scale_factor_);

    let (multiplier: felt) = pow(10, scale_factor_);
    let scaled_amount = amount * multiplier;

    return scaled_amount;
}

// & ===== Register a new token ===================================
@external
func register_token{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_address: felt, offchain_decimals: felt
) -> (token_id: felt) {
    // todo: only_admin

    assert_not_zero(token_address);

    let (token_decimals: felt) = IERC20.decimals(contract_address=token_address);
    let scaling_factor = token_decimals - offchain_decimals;

    assert_lt(0, scaling_factor);

    let (prev_token_info: felt) = s_address_to_token_id.read(token_address);
    assert prev_token_info = 0;  // "Token already registered"

    let (hash: felt) = hash2{hash_ptr=pedersen_ptr}(token_address, 0);
    let (high, low) = split_felt(hash);
    let (_, token_id: felt) = unsigned_div_rem(low, 2 ** 64);

    s_address_to_token_id.write(token_address, token_id);
    s_token_id_to_address.write(token_id, token_address);
    s_token_id_to_scale_factor.write(token_id, scaling_factor);

    new_token_registered_event.emit(token_address, token_id, scaling_factor);

    return (token_id,);
}

// & ===== Getters ===================================

func get_token_id{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_address: felt
) -> felt {
    let (token_id: felt) = s_address_to_token_id.read(token_address);
    return (token_id);
}

func get_token_address{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_id: felt
) -> felt {
    let (address: felt) = s_token_id_to_address.read(token_id);
    return (address);
}

func get_token_scale_factor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_id: felt
) -> felt {
    let (scale_factor: felt) = s_token_id_to_scale_factor.read(token_id);
    return (scale_factor);
}
