from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin, BitwiseBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.math import assert_le, unsigned_div_rem
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.squash_dict import squash_dict

from helpers.utils import Note, construct_new_note, sum_notes
from helpers.signatures.signatures import verify_close_order_tab_signature

from perpetuals.order.order_structs import CloseOrderFields
from perpetuals.transaction.perp_transaction import get_perp_position

from rollup.global_config import GlobalConfig, get_dust_amount

from order_tabs.order_tab import OrderTab, verify_order_tab_hash
from order_tabs.update_dicts import (
    close_tab_note_state_updates,
    remove_tab_from_state,
    update_tab_in_state,
)

from order_tabs.close_order_tab import handle_order_tab_input
from order_tabs.open_order_tab import handle_inputs

from smart_contract_mms.add_liquidity_helpers import (
    get_vlp_amount,
    get_updated_order_tab,
    update_state_after_tab_add_liq,
    get_updated_position,
    update_state_after_position_add_liq,
    verify_tab_add_liq_sig,
    verify_position_add_liq_sig,
)

func add_liquidity_to_mm{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    state_dict: DictAccess*,
    note_updates: Note*,
    fee_tracker_dict: DictAccess*,
    global_config: GlobalConfig*,
}() {
    alloc_locals;

    let (__fp__, _) = get_fp_and_pc();

    if (nondet %{ current_order["is_order_tab"] == True %} != 0) {
        // * Order tab

        // ? get order tab, close order fields
        %{ order_tab_input = current_order["prev_order_tab"] %}
        local order_tab: OrderTab;
        handle_order_tab_input(&order_tab);

        local vlp_close_order_fields: CloseOrderFields;
        local index_price: felt;
        %{
            vlp_close_order_field_inputs = current_order["vlp_close_order_fields"]

            memory[ids.vlp_close_order_fields.address_ + ids.CloseOrderFields.dest_received_address] = int(vlp_close_order_field_inputs["dest_received_address"]["x"])
            memory[ids.vlp_close_order_fields.address_ + ids.CloseOrderFields.dest_received_blinding] = int(vlp_close_order_field_inputs["dest_received_blinding"])

            ids.index_price = current_order["index_price"]
        %}

        // ? verify order_tab validity
        assert order_tab.tab_header.is_smart_contract = 1;
        verify_order_tab_hash(order_tab);

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

        // ? hash the inputs and verify signature
        verify_tab_add_liq_sig(
            order_tab.tab_header.pub_key,
            base_notes_in_len,
            base_notes_in,
            base_refund_note,
            quote_notes_in_len,
            quote_notes_in,
            quote_refund_note,
            vlp_close_order_fields,
        );

        let (base_amount_in) = sum_notes(
            base_notes_in_len, base_notes_in, order_tab.tab_header.base_token, 0
        );
        let (quote_amount_in) = sum_notes(
            quote_notes_in_len, quote_notes_in, order_tab.tab_header.quote_token, 0
        );
        let base_amount = base_amount_in - base_refund_note.amount;
        let quote_amount = quote_amount_in - quote_refund_note.amount;

        // ? calculate vlp amount
        let vlp_amount = get_vlp_amount(&order_tab, base_amount, quote_amount, index_price);

        // ? update the order tab
        let updated_order_tab = get_updated_order_tab(
            order_tab, vlp_amount, base_amount, quote_amount
        );

        // ? construct the new vlp_note
        local vlp_index: felt;
        %{ ids.vlp_index = current_order["vlp_note_idx"] %}

        let (vlp_note) = construct_new_note(
            vlp_close_order_fields.dest_received_address,
            order_tab.tab_header.vlp_token,
            vlp_amount,
            vlp_close_order_fields.dest_received_blinding,
            vlp_index,
        );

        // ? update the state_dict
        update_state_after_tab_add_liq(
            base_notes_in_len,
            base_notes_in,
            base_refund_note,
            quote_notes_in_len,
            quote_notes_in,
            quote_refund_note,
            vlp_note,
            order_tab,
            updated_order_tab,
        );

        return ();
    } else {
        // * Position

        // ? get position, close order fields
        %{ prev_position = current_order["prev_position"] %}
        let position = get_perp_position();

        local vlp_close_order_fields: CloseOrderFields;
        %{
            vlp_close_order_field_inputs = current_order["vlp_close_order_fields"]

            memory[ids.vlp_close_order_fields.address_ + ids.CloseOrderFields.dest_received_address] = int(vlp_close_order_field_inputs["dest_received_address"]["x"])
            memory[ids.vlp_close_order_fields.address_ + ids.CloseOrderFields.dest_received_blinding] = int(vlp_close_order_field_inputs["dest_received_blinding"])
        %}

        // ? get collateral notes
        local collateral_notes_in_len: felt;
        local collateral_notes_in: Note*;
        local collateral_refund_note: Note;
        get_collateral_notes(
            &collateral_notes_in_len, &collateral_notes_in, &collateral_refund_note
        );

        // ? hash the inputs and verify signature
        verify_position_add_liq_sig(
            position.position_header.position_address,
            collateral_notes_in_len,
            collateral_notes_in,
            collateral_refund_note,
            vlp_close_order_fields,
        );

        let (amount_in) = sum_notes(
            collateral_notes_in_len, collateral_notes_in, global_config.collateral_token, 0
        );
        let collateral_amount = amount_in - collateral_refund_note.amount;

        // ? get vlp amount
        let (vlp_amount, _) = unsigned_div_rem(
            collateral_amount * position.vlp_supply, position.margin
        );

        // ? update the position
        let new_position = get_updated_position(position, vlp_amount, collateral_amount);

        // ? construct the new vlp_note
        local vlp_index: felt;
        %{ ids.vlp_index = current_order["vlp_note_idx"] %}

        let (vlp_note) = construct_new_note(
            vlp_close_order_fields.dest_received_address,
            position.position_header.vlp_token,
            vlp_amount,
            vlp_close_order_fields.dest_received_blinding,
            vlp_index,
        );

        // ? update the state_dict
        update_state_after_position_add_liq(
            collateral_notes_in_len,
            collateral_notes_in,
            collateral_refund_note,
            vlp_note,
            position,
            new_position,
        );

        return ();
    }
}

func get_collateral_notes{pedersen_ptr: HashBuiltin*}(
    collateral_notes_in_len: felt*, collateral_notes_in: Note**, collateral_refund_note: Note*
) {
    %{
        ##* collateral INPUT NOTES =============================================================
        input_notes = current_order["collateral_notes_in"]

        memory[ids.collateral_notes_in_len] = len(input_notes)
        memory[ids.collateral_notes_in] = notes_ = segments.add()
        for i in range(len(input_notes)):
            memory[notes_ + i* NOTE_SIZE + ADDRESS_OFFSET+0] = int(input_notes[i]["address"]["x"])
            memory[notes_ + i* NOTE_SIZE + ADDRESS_OFFSET+1] = int(input_notes[i]["address"]["y"])
            memory[notes_ + i* NOTE_SIZE + TOKEN_OFFSET] = int(input_notes[i]["token"])
            memory[notes_ + i* NOTE_SIZE + AMOUNT_OFFSET] = int(input_notes[i]["amount"])
            memory[notes_ + i* NOTE_SIZE + BLINDING_FACTOR_OFFSET] = int(input_notes[i]["blinding"])
            memory[notes_ + i* NOTE_SIZE + INDEX_OFFSET] = int(input_notes[i]["index"])
            memory[notes_ + i* NOTE_SIZE + HASH_OFFSET] = int(input_notes[i]["hash"])

        refund_note__  = current_order["collateral_refund_note"]
        if refund_note__ is not None:
            memory[ids.collateral_refund_note.address_ + ADDRESS_OFFSET+0] = int(refund_note__["address"]["x"])
            memory[ids.collateral_refund_note.address_ + ADDRESS_OFFSET+1] = int(refund_note__["address"]["y"])
            memory[ids.collateral_refund_note.address_ + TOKEN_OFFSET] = int(refund_note__["token"])
            memory[ids.collateral_refund_note.address_ + AMOUNT_OFFSET] = int(refund_note__["amount"])
            memory[ids.collateral_refund_note.address_ + BLINDING_FACTOR_OFFSET] = int(refund_note__["blinding"])
            memory[ids.collateral_refund_note.address_ + INDEX_OFFSET] = int(refund_note__["index"])
            memory[ids.collateral_refund_note.address_ + HASH_OFFSET] = int(refund_note__["hash"])
        else:
            memory[ids.collateral_refund_note.address_ + ADDRESS_OFFSET+0] = 0
            memory[ids.collateral_refund_note.address_ + ADDRESS_OFFSET+1] = 0
            memory[ids.collateral_refund_note.address_ + TOKEN_OFFSET] = 0
            memory[ids.collateral_refund_note.address_ + AMOUNT_OFFSET] = 0
            memory[ids.collateral_refund_note.address_ + BLINDING_FACTOR_OFFSET] = 0
            memory[ids.collateral_refund_note.address_ + INDEX_OFFSET] = 0
            memory[ids.collateral_refund_note.address_ + HASH_OFFSET] = 0
    %}

    return ();
}
