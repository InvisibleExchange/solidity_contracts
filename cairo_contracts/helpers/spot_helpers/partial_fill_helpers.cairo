from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.dict import dict_new, dict_write, dict_update, dict_squash, dict_read
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.merkle_multi_update import merkle_multi_update
from starkware.cairo.common.ec_point import EcPoint
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.math import unsigned_div_rem, assert_le
from starkware.cairo.common.math_cmp import is_le

from invisible_swaps.order.invisible_order import Invisibl3Order

from helpers.utils import Note, construct_new_note, sum_notes, hash_note, validate_fee_taken

func refund_partial_fill{pedersen_ptr: HashBuiltin*, note_dict: DictAccess*}(
    order: Invisibl3Order, address: felt, blinding: felt, unspent_amount: felt, prev_hash: felt
) {
    //

    let (pfr_note: Note) = partial_fill_updates(order, address, blinding, unspent_amount);

    // * Update the note dict with the new notes

    let note_dict_ptr = note_dict;
    assert note_dict_ptr.key = pfr_note.index;
    assert note_dict_ptr.prev_value = prev_hash;
    assert note_dict_ptr.new_value = pfr_note.hash;

    let note_dict = note_dict + DictAccess.SIZE;

    // write_new_note_to_output(pfr_note);
    %{
        output_notes[ids.pfr_note.index] = {
               "address": {"x": ids.pfr_note.address.x, "y": ids.pfr_note.address.y},
               "hash": ids.pfr_note.hash,
               "index": ids.pfr_note.index,
               "blinding": ids.pfr_note.blinding_factor,
               "token": ids.pfr_note.token,
               "amount": ids.pfr_note.amount,
           }
    %}

    return ();
}

func partial_fill_updates{pedersen_ptr: HashBuiltin*}(
    invisible_order: Invisibl3Order, address: felt, blinding: felt, unspent_amount: felt
) -> (pf_note: Note) {
    alloc_locals;

    local new_fill_refund_note_idx: felt;
    %{ ids.new_fill_refund_note_idx = order_indexes["partial_fill_idx"] %}

    // ? This is the refund note of the leftover amount that wasn't spent in the swap
    let (partial_fill_note: Note) = construct_new_note(
        address, invisible_order.token_spent, unspent_amount, blinding, new_fill_refund_note_idx
    );

    return (partial_fill_note,);
}

// ========================================================================================
