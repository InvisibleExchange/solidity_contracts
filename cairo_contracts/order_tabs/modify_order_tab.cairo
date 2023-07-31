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

from helpers.utils import Note, construct_new_note
from helpres.signatures.signatures import verify_open_order_tab_signature

from rollup.output_structs import ZeroOutput, NoteDiffOutput
from rollup.global_config import GlobalConfig

from order_tabs.order_tab import OrderTab, hash_tab_header, hash_order_tab
from order_tabs.update_dicts import open_tab_state_note_updates, update_tab_from_state
from order_tabs.close_order_tab import (
    handle_order_tab_input,
    get_close_order_fields,
    close_tab_note_state_updates,
)

func modify_order_tab{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    note_dict: DictAccess*,
    fee_tracker_dict: DictAccess*,
    zero_note_output_ptr: ZeroOutput*,
    global_config: GlobalConfig*,
}() {
    with_attr error_message("ORDER TAB HASH IS INVALID") {
        assert order_tab.tab_header.hash = hash_tab_header(&order_tab.tab_header);
        assert quote_amount = hash_order_tab(&order_tab);
    }

    // ? Handle inputs
    local order_tab: OrderTab;
    handle_order_tab_input(&order_tab);

    local is_add: felt;
    local base_amount_change: felt;
    local quote_amount_change: felt;
    %{
        ids.is_add = 1 if current_tab_interaction["is_add"] else 0
        ids.base_amount_change = current_tab_interaction["base_amount_change"]
        ids.quote_amount_change = current_tab_interaction["quote_amount_change"]
    %}

    if (is_add == 1) {
        // ? Handle inputs
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
            assert base_amount = base_amount_change;
            assert quote_amount = quote_amount_change;
        }

        // TODO: Update the order tab

        // ? Update the dictionaries
        open_tab_state_note_updates(
            base_notes_in_len,
            base_notes_in,
            quote_notes_in_len,
            quote_notes_in,
            base_refund_note,
            quote_refund_note,
        );

        // TODO update_tab_from_state();
    } else {
        // ? Handle inputs
        local base_close_order_fields: CloseOrderFields;
        local quote_close_order_fields: CloseOrderFields;
        get_close_order_fields(&base_close_order_fields, &quote_close_order_fields);

        let base_token = order_tab.tab_header.base_token;
        let quote_token = order_tab.tab_header.quote_token;
        let base_amount = order_tab.base_amount;
        let quote_amount = order_tab.quote_amount;

        local base_idx: felt;
        local quote_idx: felt;
        %{
            ids.base_idx = current_tab_interaction["base_return_note_idx"]
            ids.quote_idx = current_tab_interaction["quote_return_note_idx"]
        %}

        let base_return_note = construct_new_note(
            base_close_order_fields.return_collateral_address,
            base_token,
            base_amount,
            base_close_order_fields.return_collateral_blinding,
            base_idx,
        );

        let quote_return_note = construct_new_note(
            quote_close_order_fields.return_collateral_address,
            quote_token,
            quote_amount,
            quote_close_order_fields.return_collateral_blinding,
            quote_idx,
        );

        // TODO: Update the order tab

        // ? Update the state dicts
        close_tab_note_state_updates(base_return_note, quote_return_note);

        // TODO update_tab_from_state();
    }
}
