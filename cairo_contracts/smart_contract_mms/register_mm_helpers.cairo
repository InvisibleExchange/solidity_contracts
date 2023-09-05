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

from starkware.cairo.common.ec import EcPoint
from helpers.utils import Note, hash_note, hash_notes_array

from rollup.global_config import (
    token_decimals,
    price_decimals,
    GlobalConfig,
    get_min_partial_liquidation_size,
)

func get_vlp_amount{pedersen_ptr: HashBuiltin*, range_check_ptr, global_config: GlobalConfig*}(
    base_token: felt, base_amount: felt, quote_amount: felt, index_price: felt
) -> felt {
    alloc_locals;

    // ? calculate the right amount of vLP tokens to mint using the index price
    let (collateral_decimals) = token_decimals(global_config.collateral_token);

    let (base_decimals: felt) = token_decimals(base_token);
    let (base_price_decimals: felt) = price_decimals(base_token);

    tempvar decimal_conversion = base_decimals + base_price_decimals - collateral_decimals;
    let (multiplier: felt) = pow(10, decimal_conversion);

    let (base_nominal: felt, _) = unsigned_div_rem(base_amount * index_price, multiplier);
    let vlp_amount = base_nominal + quote_amount;

    return vlp_amount;
}

func get_updated_order_tab{
    pedersen_ptr: HashBuiltin*, range_check_ptr, global_config: GlobalConfig*
}(prev_order_tab: OrderTab, vlp_amount: felt, vlp_token: felt, max_vlp_supply: felt) -> OrderTab {
    alloc_locals;

    let prev_header = prev_order_tab.tab_header;

    let new_header_hash = hash_tab_header_inner(
        1,
        prev_header.base_token,
        prev_header.quote_token,
        vlp_token,
        max_vlp_supply,
        prev_header.pub_key,
    );

    let new_tab_header = TabHeader(
        1,
        prev_header.base_token,
        prev_header.quote_token,
        prev_header.base_blinding,
        prev_header.quote_blinding,
        vlp_token,
        max_vlp_supply,
        prev_header.pub_key,
        new_header_hash,
    );

    let new_tab_hash = hash_order_tab_inner(
        new_tab_header, prev_order_tab.base_amount, prev_order_tab.quote_amount, vlp_amount
    );

    let new_order_tab = OrderTab(
        prev_order_tab.tab_idx,
        new_tab_header,
        prev_order_tab.base_amount,
        prev_order_tab.quote_amount,
        vlp_amount,
        new_tab_hash,
    );

    return new_order_tab;
}

func update_state_after_tab_register{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    global_config: GlobalConfig*,
    state_dict: DictAccess*,
    note_updates: Note*,
}(vlp_note: Note, order_tab: OrderTab, new_order_tab: OrderTab) {
    alloc_locals;

    // * Update the vlp note hash in the state
    let state_dict_ptr = state_dict;
    assert state_dict_ptr.key = vlp_note.index;
    assert state_dict_ptr.prev_value = 0;
    assert state_dict_ptr.new_value = vlp_note.hash;

    let state_dict = state_dict + DictAccess.SIZE;

    // ? store to an array used for program outputs
    assert note_updates[0] = vlp_note;
    let note_updates = &note_updates[1];

    %{ leaf_node_types[ids.vlp_note.index] = "note" %}
    %{
        note_output_idxs[ids.vlp_note.index] = note_outputs_len 
        note_outputs_len += 1
    %}

    // * Update the order tab hash in the state
    let state_dict_ptr = state_dict;
    assert state_dict_ptr.key = order_tab.tab_idx;
    assert state_dict_ptr.prev_value = order_tab.hash;
    assert state_dict_ptr.new_value = new_order_tab.hash;

    let state_dict = state_dict + DictAccess.SIZE;

    %{ leaf_node_types[ids.order_tab.tab_idx] = "order_tab" %}
    %{ store_output_order_tab(ids.new_order_tab.tab_header.address_, ids.new_order_tab.tab_idx, ids.new_order_tab.base_amount, ids.new_order_tab.quote_amount,ids.new_order_tab.vlp_supply, ids.new_order_tab.hash ) %}

    return ();
}

// * ================================================================================================

func get_updated_position{
    pedersen_ptr: HashBuiltin*, range_check_ptr, global_config: GlobalConfig*
}(
    prev_position: PerpPosition, vlp_amount: felt, vlp_token: felt, max_vlp_supply: felt
) -> PerpPosition {
    alloc_locals;

    let prev_header = prev_position.position_header;

    let (new_header_hash) = _hash_position_header(
        prev_header.synthetic_token,
        prev_header.allow_partial_liquidations,
        prev_header.position_address,
        vlp_token,
        max_vlp_supply,
    );

    let position_header = PositionHeader(
        prev_header.synthetic_token,
        prev_header.allow_partial_liquidations,
        prev_header.position_address,
        vlp_token,
        max_vlp_supply,
        new_header_hash,
    );

    let (new_position_hash: felt) = _hash_position_internal(
        new_header_hash,
        prev_position.order_side,
        prev_position.position_size,
        prev_position.entry_price,
        prev_position.liquidation_price,
        prev_position.last_funding_idx,
        vlp_amount,
    );

    let new_position = PerpPosition(
        position_header,
        prev_position.order_side,
        prev_position.position_size,
        prev_position.margin,
        prev_position.entry_price,
        prev_position.liquidation_price,
        prev_position.bankruptcy_price,
        prev_position.last_funding_idx,
        vlp_amount,
        prev_position.index,
        new_position_hash,
    );

    return new_position;
}

func update_state_after_position_register{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    global_config: GlobalConfig*,
    state_dict: DictAccess*,
    note_updates: Note*,
}(vlp_note: Note, position: PerpPosition, new_position: PerpPosition) {
    alloc_locals;

    // * Update the vlp note hash in the state
    let state_dict_ptr = state_dict;
    assert state_dict_ptr.key = vlp_note.index;
    assert state_dict_ptr.prev_value = 0;
    assert state_dict_ptr.new_value = vlp_note.hash;

    let state_dict = state_dict + DictAccess.SIZE;

    // ? store to an array used for program outputs
    assert note_updates[0] = vlp_note;
    let note_updates = &note_updates[1];

    %{ leaf_node_types[ids.vlp_note.index] = "note" %}
    %{
        note_output_idxs[ids.vlp_note.index] = note_outputs_len 
        note_outputs_len += 1
    %}

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

// * ================================================================================================

func verify_register_mm_sig{
    pedersen_ptr: HashBuiltin*, range_check_ptr, ecdsa_ptr: SignatureBuiltin*
}(
    address: felt,
    hash: felt,
    vlp_token: felt,
    max_vlp_supply: felt,
    close_order_fields: CloseOrderFields,
) {
    alloc_locals;

    let (close_order_fields_hash) = _hash_close_order_fields(close_order_fields);

    let msg_hash = _hash_register_message(
        address, hash, vlp_token, max_vlp_supply, close_order_fields_hash
    );

    local sig_r: felt;
    local sig_s: felt;
    %{
        signature = current_order["signature"]
        ids.sig_r = int(signature[0])
        ids.sig_s = int(signature[1])
    %}

    verify_ecdsa_signature(
        message=msg_hash, public_key=address, signature_r=sig_r, signature_s=sig_s
    );

    return ();
}

func _hash_register_message{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    address: felt, hash: felt, vlp_token: felt, max_vlp_supply: felt, close_order_fields_hash: felt
) -> felt {
    alloc_locals;

    // & header_hash = H({address, hash, vlp_token, max_vlp_supply, close_order_fields_hash})

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state_ptr) = hash_init();
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, address);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, hash);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, vlp_token);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, max_vlp_supply);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, close_order_fields_hash);

        let (res) = hash_finalize(hash_state_ptr);
        let pedersen_ptr = hash_ptr;
        return res;
    }
}
