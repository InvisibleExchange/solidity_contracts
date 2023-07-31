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
from helpres.signatures.signatures import verify_close_order_tab_signature

from rollup.output_structs import ZeroOutput, NoteDiffOutput
from rollup.global_config import GlobalConfig

from order_tabs.order_tab import OrderTab, hash_tab_header, hash_order_tab
from order_tabs.update_dicts import close_tab_note_state_updates, remove_tab_from_state

func close_order_tab{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    note_dict: DictAccess*,
    fee_tracker_dict: DictAccess*,
    zero_tab_output_ptr: ZeroOutput*,
    global_config: GlobalConfig*,
}() {
    // ? Handle inputs
    local order_tab: OrderTab;
    handle_order_tab_input(&order_tab);

    local base_close_order_fields: CloseOrderFields;
    local quote_close_order_fields: CloseOrderFields;
    get_close_order_fields(&base_close_order_fields, &quote_close_order_fields);

    with_attr error_message("ORDER TAB HASH IS INVALID") {
        assert order_tab.tab_header.hash = hash_tab_header(&order_tab.tab_header);
        assert quote_amount = hash_order_tab(&order_tab);
    }

    // ? Verify the signature
    verify_close_order_tab_signature(
        order_tab.hash,
        &base_close_order_fields,
        &quote_close_order_fields,
        &order_tab.tab_header.pub_key,
    );

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

    // ? Update the state dicts
    close_tab_note_state_updates(base_return_note, quote_return_note);

    remove_tab_from_state(&order_tab);
}

func handle_order_tab_input{pedersen_ptr: HashBuiltin*}(order_tab: OrderTab*) {
    %{
        order_tab_addr = ids.order_tab.address_
        tab_header_addr = order_tab_addr + ORDER_TAB_TAB_HEADER_OFFSET

        order_tab_input = current_tab_interaction["order_tab"]
        memory[order_tab_addr + ORDER_TAB_TAB_IDX_OFFSET] = int(order_tab_input["tab_idx"])
        memory[order_tab_addr + ORDER_TAB_BASE_AMOUNT_OFFSET] = int(order_tab_input["base_amount"])
        memory[order_tab_addr + ORDER_TAB_QUOTE_AMOUNT_OFFSET] = int(order_tab_input["quote_amount"])
        memory[order_tab_addr + ORDER_TAB_HASH_OFFSET] = int(order_tab_input["hash"])

        tab_header = order_tab_input["tab_header"]
        memory[tab_header_addr + TAB_HEADER_EXPIRATION_TIMESTAMP_OFFSET] = int(tab_header["expiration_timestamp"])
        memory[tab_header_addr + TAB_HEADER_IS_PERP_OFFSET] = int(tab_header["is_perp"])
        memory[tab_header_addr + TAB_HEADER_IS_SMART_CONTRACT_OFFSET] = int(tab_header["is_smart_contract"])
        memory[tab_header_addr + TAB_HEADER_BASE_TOKEN_OFFSET] = int(tab_header["base_token"])
        memory[tab_header_addr + TAB_HEADER_QUOTE_TOKEN_OFFSET] = int(tab_header["quote_token"])
        memory[tab_header_addr + TAB_HEADER_BASE_BLINDING_OFFSET] = int(tab_header["base_blinding"])
        memory[tab_header_addr + TAB_HEADER_QUOTE_BLINDING_OFFSET] = int(tab_header["quote_blinding"])
        memory[tab_header_addr + TAB_HEADER_PUB_KEY_OFFSET] = int(tab_header["pub_key"])
        memory[tab_header_addr + TAB_HEADER_HASH_OFFSET] = int(tab_header["hash"])
    %}

    return ();
}

func get_close_order_fields{pedersen_ptr: HashBuiltin*}(
    base_close_order_fields: CloseOrderFields*, quote_close_order_fields: CloseOrderFields*
) {
    %{
        base_close_order_field_inputs = current_tab_interaction["base_close_order_fields"]
        quote_close_order_field_inputs = current_tab_interaction["quote_close_order_fields"]

        memory[ids.base_close_order_fields.address_ + RETURN_COLLATERAL_ADDRESS_OFFSET] = int(base_close_order_field_inputs["dest_received_address"]["x"])
        memory[ids.base_close_order_fields.address_ + RETURN_COLLATERAL_BLINDING_OFFSET] = int(base_close_order_field_inputs["dest_received_blinding"])

        memory[ids.quote_close_order_fields.address_ + RETURN_COLLATERAL_ADDRESS_OFFSET] = int(quote_close_order_field_inputs["dest_received_address"]["x"])
        memory[ids.quote_close_order_fields.address_ + RETURN_COLLATERAL_BLINDING_OFFSET] = int(quote_close_order_field_inputs["dest_received_blinding"])
    %}

    return ();
}
