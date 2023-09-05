from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.pow import pow
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.hash_state import (
    hash_init,
    hash_finalize,
    hash_update,
    hash_update_single,
)
from starkware.cairo.common.math import unsigned_div_rem

from order_tabs.order_tab import OrderTab, TabHeader, hash_tab_header_inner, hash_order_tab_inner
from perpetuals.order.order_structs import PerpPosition, PositionHeader, CloseOrderFields
from perpetuals.order.order_hash import (
    _hash_position_header,
    _hash_position_internal,
    _hash_close_order_fields,
)
from perpetuals.order.order_helpers import update_position_info

from starkware.cairo.common.ec import EcPoint
from helpers.utils import Note, hash_note, hash_notes_array
from helpers.signatures.signatures import sum_pub_keys
from helpers.spot_helpers.dict_updates import _update_multi_inner

from rollup.global_config import (
    token_decimals,
    price_decimals,
    GlobalConfig,
    get_min_partial_liquidation_size,
)

from order_tabs.update_dicts import add_refund_note, open_tab_state_note_updates

from smart_contract_mms.register_mm_helpers import (
    update_state_after_tab_register,
    update_state_after_position_register,
)

// * =============================================================================================

func get_base_close_amounts{
    pedersen_ptr: HashBuiltin*, range_check_ptr, global_config: GlobalConfig*
}(
    order_tab: OrderTab*,
    base_return_amount: felt,
    index_price: felt,
    slippage: felt,
    vlp_amount: felt,
    is_full_close: felt,
) -> (felt, felt) {
    alloc_locals;

    if (is_full_close == 1) {
        let base_amount = order_tab.base_amount;
        let quote_amount = order_tab.quote_amount;

        return (base_amount, quote_amount);
    } else {
        // ? calculate the right amount of vLP tokens to mint using the index price
        let (collateral_decimals) = token_decimals(global_config.collateral_token);

        let (base_decimals: felt) = token_decimals(order_tab.tab_header.base_token);
        let (base_price_decimals: felt) = price_decimals(order_tab.tab_header.base_token);

        tempvar decimal_conversion = base_decimals + base_price_decimals - collateral_decimals;
        let (multiplier: felt) = pow(10, decimal_conversion);

        let (base_nominal: felt, _) = unsigned_div_rem(
            base_return_amount * index_price, multiplier
        );

        let (tab_base_nominal: felt, _) = unsigned_div_rem(
            order_tab.base_amount * index_price, multiplier
        );
        let tab_nominal: felt = tab_base_nominal + order_tab.quote_amount;

        let (return_nominal, _) = unsigned_div_rem(vlp_amount * tab_nominal, order_tab.vlp_supply);
        let quote_return_amount = return_nominal - base_nominal;

        return (base_return_amount, quote_return_amount);
    }
}

func get_updated_order_tab{
    pedersen_ptr: HashBuiltin*, range_check_ptr, global_config: GlobalConfig*
}(
    prev_order_tab: OrderTab,
    removed_vlp_amount: felt,
    removed_base_amount: felt,
    removed_quote_amount: felt,
) -> OrderTab {
    alloc_locals;

    let new_tab_hash = hash_order_tab_inner(
        prev_order_tab.tab_header,
        prev_order_tab.base_amount - removed_base_amount,
        prev_order_tab.quote_amount - removed_quote_amount,
        prev_order_tab.vlp_supply - removed_vlp_amount,
    );

    let new_order_tab = OrderTab(
        prev_order_tab.tab_idx,
        prev_order_tab.tab_header,
        prev_order_tab.base_amount - removed_base_amount,
        prev_order_tab.quote_amount - removed_quote_amount,
        prev_order_tab.vlp_supply - removed_vlp_amount,
        new_tab_hash,
    );

    return new_order_tab;
}

func update_note_state_after_tab_remove_liq{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    global_config: GlobalConfig*,
    state_dict: DictAccess*,
    note_updates: Note*,
}(vlp_notes_in_len: felt, vlp_notes_in: Note*, base_return_note: Note, quote_return_note: Note) {
    alloc_locals;

    // ? Remove notes in and return refund notes
    _update_multi_inner(vlp_notes_in_len, vlp_notes_in);

    // ? Return the base and quote return note
    add_refund_note(base_return_note.index, base_return_note);
    add_refund_note(quote_return_note.index, quote_return_note);

    return ();
}

func update_tab_after_remove_liq{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    global_config: GlobalConfig*,
    state_dict: DictAccess*,
}(order_tab: OrderTab, new_order_tab: OrderTab) {
    // * Update the order tab hash in the state
    let state_dict_ptr = state_dict;
    assert state_dict_ptr.key = order_tab.tab_idx;
    assert state_dict_ptr.prev_value = order_tab.hash;
    assert state_dict_ptr.new_value = new_order_tab.hash;

    let state_dict = state_dict + DictAccess.SIZE;

    %{ leaf_node_types[ids.order_tab.tab_idx] = "order_tab" %}
    %{ store_output_order_tab(ids.new_order_tab.tab_header.address_, ids.new_order_tab.tab_idx, ids.new_order_tab.base_amount, ids.new_order_tab.quote_amount, ids.new_order_tab.vlp_supply, ids.new_order_tab.hash ) %}

    return ();
}

func remove_tab_after_remove_liq{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    global_config: GlobalConfig*,
    state_dict: DictAccess*,
}(order_tab: OrderTab) {
    // * Update the order tab hash in the state
    let state_dict_ptr = state_dict;
    assert state_dict_ptr.key = order_tab.tab_idx;
    assert state_dict_ptr.prev_value = order_tab.hash;
    assert state_dict_ptr.new_value = 0;

    let state_dict = state_dict + DictAccess.SIZE;

    %{ leaf_node_types[ids.order_tab.tab_idx] = "order_tab" %}

    return ();
}
// * =============================================================================================

func get_return_collateral_amount{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    vlp_amount: felt, margin: felt, vlp_supply: felt
) -> felt {
    alloc_locals;

    let (return_collateral, _) = unsigned_div_rem(vlp_amount * margin, vlp_supply);

    return return_collateral;
}

func get_updated_position{
    pedersen_ptr: HashBuiltin*, range_check_ptr, global_config: GlobalConfig*
}(
    prev_position: PerpPosition, removed_vlp_amount: felt, removed_collateral_amount: felt
) -> PerpPosition {
    alloc_locals;

    let updated_margin = prev_position.margin - removed_collateral_amount;
    let updated_vlp_supply = prev_position.vlp_supply - removed_vlp_amount;

    let (bankruptcy_price, liquidation_price, new_position_hash) = update_position_info(
        prev_position.position_header.hash,
        prev_position.order_side,
        prev_position.position_header.synthetic_token,
        prev_position.position_size,
        updated_margin,
        prev_position.entry_price,
        prev_position.last_funding_idx,
        prev_position.position_header.allow_partial_liquidations,
        updated_vlp_supply,
    );

    let new_position = PerpPosition(
        prev_position.position_header,
        prev_position.order_side,
        prev_position.position_size,
        updated_margin,
        prev_position.entry_price,
        liquidation_price,
        bankruptcy_price,
        prev_position.last_funding_idx,
        updated_vlp_supply,
        prev_position.index,
        new_position_hash,
    );

    return new_position;
}

func update_note_state_after_position_remove_liq{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    global_config: GlobalConfig*,
    state_dict: DictAccess*,
    note_updates: Note*,
}(vlp_notes_in_len: felt, vlp_notes_in: Note*, collateral_return_note: Note) {
    alloc_locals;

    // ? Remove notes in and return refund notes
    _update_multi_inner(vlp_notes_in_len, vlp_notes_in);

    // ? Return the base and quote return note
    add_refund_note(collateral_return_note.index, collateral_return_note);

    return ();
}

func update_position_after_remove_liq{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    global_config: GlobalConfig*,
    state_dict: DictAccess*,
}(position: PerpPosition, new_position: PerpPosition) {
    // * Update the order tab hash in the state
    let state_dict_ptr = state_dict;
    assert state_dict_ptr.key = position.index;
    assert state_dict_ptr.prev_value = position.hash;
    assert state_dict_ptr.new_value = new_position.hash;

    let state_dict = state_dict + DictAccess.SIZE;

    %{ leaf_node_types[ids.position.index] = "position" %}

    %{ store_output_position(ids.new_position.address_, ids.new_position.index) %}

    return ();
}

func remove_position_after_remove_liq{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    global_config: GlobalConfig*,
    state_dict: DictAccess*,
}(position: PerpPosition) {
    // * Update the order tab hash in the state
    let state_dict_ptr = state_dict;
    assert state_dict_ptr.key = position.index;
    assert state_dict_ptr.prev_value = position.hash;
    assert state_dict_ptr.new_value = 0;

    let state_dict = state_dict + DictAccess.SIZE;

    %{ leaf_node_types[ids.position.index] = "position" %}

    return ();
}

// * =============================================================================================

func verify_tab_remove_liq_sig{
    pedersen_ptr: HashBuiltin*, range_check_ptr, ecdsa_ptr: SignatureBuiltin*
}(
    tab_pub_key: felt,
    index_price: felt,
    slippage: felt,
    vlp_notes_in_len: felt,
    vlp_notes_in: Note*,
    base_close_order_fields: CloseOrderFields,
    quote_close_order_fields: CloseOrderFields,
) {
    alloc_locals;

    let (base_close_order_fields_hash) = _hash_close_order_fields(base_close_order_fields);
    let (quote_close_order_fields_hash) = _hash_close_order_fields(quote_close_order_fields);

    let msg_hash = _hash_tab_remove_liq_message(
        index_price,
        slippage,
        base_close_order_fields_hash,
        quote_close_order_fields_hash,
        tab_pub_key,
    );

    let (pub_key_sum: EcPoint) = sum_pub_keys(vlp_notes_in_len, vlp_notes_in, EcPoint(0, 0));

    local sig_r: felt;
    local sig_s: felt;
    %{
        signature = current_order["signature"]
        ids.sig_r = int(signature[0])
        ids.sig_s = int(signature[1])
    %}

    verify_ecdsa_signature(
        message=msg_hash, public_key=pub_key_sum.x, signature_r=sig_r, signature_s=sig_s
    );

    return ();
}

func _hash_tab_remove_liq_message{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    index_price: felt,
    slippage: felt,
    base_close_order_fields_hash: felt,
    quote_close_order_fields_hash: felt,
    tab_pub_key: felt,
) -> felt {
    alloc_locals;

    // & hash = H({index_price, slippage, base_close_order_fields_hash, quote_close_order_fields_hash, pub_key})

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state_ptr) = hash_init();
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, index_price);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, slippage);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, base_close_order_fields_hash);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, quote_close_order_fields_hash);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, tab_pub_key);

        let (res) = hash_finalize(hash_state_ptr);
        let pedersen_ptr = hash_ptr;
        return res;
    }
}

// * =============================================================================================

// & hash = H({close_order_fields_hash, position_address})

func verify_position_remove_liq_sig{
    pedersen_ptr: HashBuiltin*, range_check_ptr, ecdsa_ptr: SignatureBuiltin*
}(
    vlp_notes_in_len: felt,
    vlp_notes_in: Note*,
    close_order_fields: CloseOrderFields,
    position_address: felt,
) {
    alloc_locals;

    let (close_order_fields_hash) = _hash_close_order_fields(close_order_fields);

    let msg_hash = _hash_position_remove_liq_message(close_order_fields_hash, position_address);

    let (pub_key_sum: EcPoint) = sum_pub_keys(vlp_notes_in_len, vlp_notes_in, EcPoint(0, 0));

    local sig_r: felt;
    local sig_s: felt;
    %{
        signature = current_order["signature"]
        ids.sig_r = int(signature[0])
        ids.sig_s = int(signature[1])
    %}

    verify_ecdsa_signature(
        message=msg_hash, public_key=pub_key_sum.x, signature_r=sig_r, signature_s=sig_s
    );

    return ();
}

func _hash_position_remove_liq_message{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    close_order_fields_hash: felt, position_address: felt
) -> felt {
    alloc_locals;

    // & hash = H({close_order_fields_hash, position_address})

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state_ptr) = hash_init();
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, close_order_fields_hash);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, position_address);

        let (res) = hash_finalize(hash_state_ptr);
        let pedersen_ptr = hash_ptr;
        return res;
    }
}
