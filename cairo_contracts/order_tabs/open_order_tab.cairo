// %builtins output pedersen range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin, BitwiseBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.dict import dict_new, dict_write, dict_update, dict_squash, dict_read
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.cairo_secp.bigint import BigInt3, bigint_to_uint256, uint256_to_bigint
from starkware.cairo.common.cairo_secp.ec import EcPoint
from starkware.cairo.common.merkle_multi_update import merkle_multi_update
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.math import unsigned_div_rem, assert_le
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.squash_dict import squash_dict
from starkware.cairo.common.hash_state import (
    hash_init,
    hash_finalize,
    hash_update,
    hash_update_single,
)

from helpers.utils import Note
from helpres.signatures.signatures import verify_open_order_tab_signature

from rollup.output_structs import ZeroOutput, NoteDiffOutput
from rollup.global_config import GlobalConfig

from order_tabs.order_tab import OrderTab, hash_tab_header, hash_order_tab
from order_tabs.update_dicts import open_tab_state_note_updates, add_new_tab_to_state
from order_tabs.close_order_tab import handle_order_tab_input

func open_order_tab{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    note_dict: DictAccess*,
    fee_tracker_dict: DictAccess*,
    zero_note_output_ptr: ZeroOutput*,
    global_config: GlobalConfig*,
}(
    order_tab: OrderTab,
    base_notes_in_len: felt,
    base_notes_in: Note*,
    base_refund_note: Note,
    quote_notes_in_len: felt,
    quote_notes_in: Note*,
    quote_refund_note: Note,
) {
    // ? Handle inputs
    local order_tab: OrderTab;
    handle_order_tab_input(&order_tab);

    local base_notes_in_len: felt;
    local base_notes_in: Note*;
    local base_refund_note: Note;
    local quote_notes_in_len: felt;
    local quote_notes_in: Note*;
    local quote_refund_note: Note;
    handle_inputs(
        &base_notes_in_len,
        &base_notes_in,
        &base_refund_note,
        &quote_notes_in_len,
        &quote_notes_in,
        &quote_refund_note,
    );

    // ?
    let (base_amounts_sum: felt) = sum_notes(
        base_notes_in_len, base_notes_in, order_tab.base_token, 0
    );
    let base_refund_note_amount = base_refund_note.amount;

    let (quote_amounts_sum: felt) = sum_notes(
        quote_notes_in_len, quote_notes_in, order_tab.quote_token, 0
    );
    let quote_refund_note_amount = quote_refund_note.amount;

    let base_amount = base_amounts_sum - base_refund_note_amount;
    let quote_amount = quote_amounts_sum - quote_refund_note_amount;

    with_attr error_message("INVALID AMOUNTS IN OPEN ORDER TAB") {
        assert base_amount = order_tab.base_amount;
        assert quote_amount = order_tab.quote_amount;
    }

    with_attr error_message("ORDER TAB HASH IS INVALID") {
        assert order_tab.tab_header.hash = hash_tab_header(&order_tab.tab_header);
        assert quote_amount = hash_order_tab(&order_tab);
    }

    // ? Verify the signature
    verify_open_order_tab_signature(
        order_tab.hash,
        base_notes_in_len,
        base_notes_in,
        base_refund_note.hash,
        quote_notes_in_len,
        quote_notes_in,
        quote_refund_note.hash,
    );

    // ? Update the dictionaries
    open_tab_state_note_updates(
        base_notes_in_len,
        base_notes_in,
        quote_notes_in_len,
        quote_notes_in,
        base_refund_note,
        quote_refund_note,
    );

    &add_new_tab_to_state(order_tab);

}

func handle_inputs{pedersen_ptr: HashBuiltin*}(
    base_notes_in_len: felt*,
    base_notes_in: Note**,
    base_refund_note: Note*,
    quote_notes_in_len: felt*,
    quote_notes_in: Note**,
    quote_refund_note: Note*,
) {
    %{
        ##* BASE INPUT NOTES =============================================================
        input_notes = current_tab_interaction["base_notes_in"]

        memory[ids.base_notes_in_len] = len(input_notes)
        memory[ids.base_notes_in] = notes_ = segments.add()
        for i in range(len(input_notes)):
            memory[notes_ + i* NOTE_SIZE + ADDRESS_OFFSET+0] = int(input_notes[i]["address"]["x"])
            memory[notes_ + i* NOTE_SIZE + ADDRESS_OFFSET+1] = int(input_notes[i]["address"]["y"])
            memory[notes_ + i* NOTE_SIZE + TOKEN_OFFSET] = int(input_notes[i]["token"])
            memory[notes_ + i* NOTE_SIZE + AMOUNT_OFFSET] = int(input_notes[i]["amount"])
            memory[notes_ + i* NOTE_SIZE + BLINDING_FACTOR_OFFSET] = int(input_notes[i]["blinding"])
            memory[notes_ + i* NOTE_SIZE + INDEX_OFFSET] = int(input_notes[i]["index"])
            memory[notes_ + i* NOTE_SIZE + HASH_OFFSET] = int(input_notes[i]["hash"])

        refund_note__  = current_tab_interaction["base_refund_note"]
        if refund_note__ is not None:
            memory[ids.base_refund_note.address_ + ADDRESS_OFFSET+0] = int(refund_note__["address"]["x"])
            memory[ids.base_refund_note.address_ + ADDRESS_OFFSET+1] = int(refund_note__["address"]["y"])
            memory[ids.base_refund_note.address_ + TOKEN_OFFSET] = int(refund_note__["token"])
            memory[ids.base_refund_note.address_ + AMOUNT_OFFSET] = int(refund_note__["amount"])
            memory[ids.base_refund_note.address_ + BLINDING_FACTOR_OFFSET] = int(refund_note__["blinding"])
            memory[ids.base_refund_note.address_ + INDEX_OFFSET] = int(refund_note__["index"])
            memory[ids.base_refund_note.address_ + HASH_OFFSET] = int(refund_note__["hash"])
        else:
            memory[ids.base_refund_note.address_ + ADDRESS_OFFSET+0] = 0
            memory[ids.base_refund_note.address_ + ADDRESS_OFFSET+1] = 0
            memory[ids.base_refund_note.address_ + TOKEN_OFFSET] = 0
            memory[ids.base_refund_note.address_ + AMOUNT_OFFSET] = 0
            memory[ids.base_refund_note.address_ + BLINDING_FACTOR_OFFSET] = 0
            memory[ids.base_refund_note.address_ + INDEX_OFFSET] = 0
            memory[ids.base_refund_note.address_ + HASH_OFFSET] = 0


        ##* QUOTE INPUT NOTES =============================================================
        input_notes = current_tab_interaction["quote_notes_in"]

          memory[ids.quote_notes_in_len] = len(input_notes)
        memory[ids.quote_notes_in] = notes_ = segments.add()
        for i in range(len(input_notes)):
            memory[notes_ + i* NOTE_SIZE + ADDRESS_OFFSET+0] = int(input_notes[i]["address"]["x"])
            memory[notes_ + i* NOTE_SIZE + ADDRESS_OFFSET+1] = int(input_notes[i]["address"]["y"])
            memory[notes_ + i* NOTE_SIZE + TOKEN_OFFSET] = int(input_notes[i]["token"])
            memory[notes_ + i* NOTE_SIZE + AMOUNT_OFFSET] = int(input_notes[i]["amount"])
            memory[notes_ + i* NOTE_SIZE + BLINDING_FACTOR_OFFSET] = int(input_notes[i]["blinding"])
            memory[notes_ + i* NOTE_SIZE + INDEX_OFFSET] = int(input_notes[i]["index"])
            memory[notes_ + i* NOTE_SIZE + HASH_OFFSET] = int(input_notes[i]["hash"])

        refund_note__  = current_tab_interaction["quote_refund_note"]
        if refund_note__ is not None:
            memory[ids.quote_refund_note.address_ + ADDRESS_OFFSET+0] = int(refund_note__["address"]["x"])
            memory[ids.quote_refund_note.address_ + ADDRESS_OFFSET+1] = int(refund_note__["address"]["y"])
            memory[ids.quote_refund_note.address_ + TOKEN_OFFSET] = int(refund_note__["token"])
            memory[ids.quote_refund_note.address_ + AMOUNT_OFFSET] = int(refund_note__["amount"])
            memory[ids.quote_refund_note.address_ + BLINDING_FACTOR_OFFSET] = int(refund_note__["blinding"])
            memory[ids.quote_refund_note.address_ + INDEX_OFFSET] = int(refund_note__["index"])
            memory[ids.quote_refund_note.address_ + HASH_OFFSET] = int(refund_note__["hash"])
        else:
            memory[ids.quote_refund_note.address_ + ADDRESS_OFFSET+0] = 0
            memory[ids.quote_refund_note.address_ + ADDRESS_OFFSET+1] = 0
            memory[ids.quote_refund_note.address_ + TOKEN_OFFSET] = 0
            memory[ids.quote_refund_note.address_ + AMOUNT_OFFSET] = 0
            memory[ids.quote_refund_note.address_ + BLINDING_FACTOR_OFFSET] = 0
            memory[ids.quote_refund_note.address_ + INDEX_OFFSET] = 0
            memory[ids.quote_refund_note.address_ + HASH_OFFSET] = 0
    %}

    return ();
}
