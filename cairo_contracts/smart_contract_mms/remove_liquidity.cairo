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

from order_tabs.close_order_tab import handle_order_tab_input, get_close_order_fields
from order_tabs.open_order_tab import handle_inputs

from smart_contract_mms.remove_liquidity_helpers import (
    get_base_close_amounts,
    get_updated_order_tab,
    update_note_state_after_tab_remove_liq,
    update_tab_after_remove_liq,
    remove_tab_after_remove_liq,
    get_return_collateral_amount,
    get_updated_position,
    update_note_state_after_position_remove_liq,
    update_position_after_remove_liq,
    remove_position_after_remove_liq,
    verify_tab_remove_liq_sig,
    verify_position_remove_liq_sig,
)

func remove_liquidity_from_mm{
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

    local vlp_notes_in_len: felt;
    local vlp_notes_in: Note*;
    get_vlp_notes_in(&vlp_notes_in_len, &vlp_notes_in);

    if (nondet %{ current_order["is_order_tab"] == True %} != 0) {
        // * Order tab

        // ? get order tab, close order fields
        %{ order_tab_input = current_order["prev_order_tab"] %}
        local order_tab: OrderTab;
        handle_order_tab_input(&order_tab);

        local base_close_order_fields: CloseOrderFields;
        local quote_close_order_fields: CloseOrderFields;
        get_close_order_fields(&base_close_order_fields, &quote_close_order_fields);

        local index_price: felt;
        local user_index_price: felt;
        local slippage: felt;
        local base_return_amount: felt;
        %{
            ids.index_price = current_order["index_price"]
            ids.user_index_price = current_order["user_index_price"]
            ids.slippage = current_order["slippage"]
            ids.base_return_amount = current_order["base_return_amount"]
        %}

        let (vlp_amount) = sum_notes(
            vlp_notes_in_len, vlp_notes_in, order_tab.tab_header.vlp_token, 0
        );

        // ? Verify the signature
        verify_tab_remove_liq_sig(
            order_tab.tab_header.pub_key,
            user_index_price,
            slippage,
            vlp_notes_in_len,
            vlp_notes_in,
            base_close_order_fields,
            quote_close_order_fields,
        );

        // ? Verify the execution index price is within slippage range of users price
        // ? slippage: 10_000 = 100% ; 100 = 1%; 1 = 0.01%
        let (max_slippage_price, _) = unsigned_div_rem(
            user_index_price * (10000 - slippage), 10000
        );
        assert_le(max_slippage_price, index_price);

        let is_full_close = is_le(order_tab.vlp_supply, vlp_amount);

        let (base_return_amount, quote_return_amount) = get_base_close_amounts(
            &order_tab, base_return_amount, index_price, slippage, vlp_amount, is_full_close
        );

        // ? construct the new return notes
        local base_return_note_index: felt;
        local quote_return_note_index: felt;
        %{
            ids.base_return_note_index = current_order["base_return_note_index"] 
            ids.quote_return_note_index = current_order["quote_return_note_index"]
        %}

        let (base_return_note: Note) = construct_new_note(
            base_close_order_fields.dest_received_address,
            order_tab.tab_header.base_token,
            base_return_amount,
            base_close_order_fields.dest_received_blinding,
            base_return_note_index,
        );
        let (quote_return_note: Note) = construct_new_note(
            quote_close_order_fields.dest_received_address,
            order_tab.tab_header.quote_token,
            quote_return_amount,
            quote_close_order_fields.dest_received_blinding,
            quote_return_note_index,
        );

        // ? Update the state
        update_note_state_after_tab_remove_liq(
            vlp_notes_in_len, vlp_notes_in, base_return_note, quote_return_note
        );

        if (is_full_close == 1) {
            remove_tab_after_remove_liq(order_tab);
        } else {
            let updated_order_tab = get_updated_order_tab(
                order_tab, vlp_amount, base_return_amount, quote_return_amount
            );

            update_tab_after_remove_liq(order_tab, updated_order_tab);
        }

        return ();
    } else {
        // * Position

        // ? get position, close order fields
        %{ prev_position = current_order["prev_position"] %}
        let position = get_perp_position();

        local collateral_close_order_fields: CloseOrderFields;
        %{
            collateral_close_order_fields = current_order["collateral_close_order_fields"]

            memory[ids.collateral_close_order_fields.address_ + ids.CloseOrderFields.dest_received_address] = int(collateral_close_order_fields["dest_received_address"]["x"])
            memory[ids.collateral_close_order_fields.address_ + ids.CloseOrderFields.dest_received_blinding] = int(collateral_close_order_fields["dest_received_blinding"])
        %}

        let (vlp_amount) = sum_notes(
            vlp_notes_in_len, vlp_notes_in, position.position_header.vlp_token, 0
        );

        // ? Verify the signature
        verify_position_remove_liq_sig(
            vlp_notes_in_len,
            vlp_notes_in,
            collateral_close_order_fields,
            position.position_header.position_address,
        );

        let is_full_close = is_le(position.vlp_supply, vlp_amount);

        let return_collateral_amount = get_return_collateral_amount(
            vlp_amount, position.margin, position.vlp_supply
        );

        // ? construct the new return collateral note
        local collateral_return_note_index: felt;
        %{ ids.collateral_return_note_index = current_order["collateral_return_note_index"] %}

        let (collateral_return_note: Note) = construct_new_note(
            collateral_close_order_fields.dest_received_address,
            global_config.collateral_token,
            return_collateral_amount,
            collateral_close_order_fields.dest_received_blinding,
            collateral_return_note_index,
        );

        // ? Update the state
        update_note_state_after_position_remove_liq(
            vlp_notes_in_len, vlp_notes_in, collateral_return_note
        );

        if (is_full_close == 1) {
            remove_position_after_remove_liq(position);
        } else {
            let updated_position = get_updated_position(
                position, vlp_amount, return_collateral_amount
            );

            update_position_after_remove_liq(position, updated_position);
        }

        return ();
    }
}

//

//

//

//
func get_vlp_notes_in{pedersen_ptr: HashBuiltin*}(vlp_notes_in_len: felt*, vlp_notes_in: Note**) {
    %{
        ##* collateral INPUT NOTES =============================================================
        input_notes = current_order["vlp_notes_in"]

        memory[ids.vlp_notes_in_len] = len(input_notes)
        memory[ids.vlp_notes_in] = notes_ = segments.add()
        for i in range(len(input_notes)):
            memory[notes_ + i* NOTE_SIZE + ADDRESS_OFFSET+0] = int(input_notes[i]["address"]["x"])
            memory[notes_ + i* NOTE_SIZE + ADDRESS_OFFSET+1] = int(input_notes[i]["address"]["y"])
            memory[notes_ + i* NOTE_SIZE + TOKEN_OFFSET] = int(input_notes[i]["token"])
            memory[notes_ + i* NOTE_SIZE + AMOUNT_OFFSET] = int(input_notes[i]["amount"])
            memory[notes_ + i* NOTE_SIZE + BLINDING_FACTOR_OFFSET] = int(input_notes[i]["blinding"])
            memory[notes_ + i* NOTE_SIZE + INDEX_OFFSET] = int(input_notes[i]["index"])
            memory[notes_ + i* NOTE_SIZE + HASH_OFFSET] = int(input_notes[i]["hash"])
    %}

    return ();
}
