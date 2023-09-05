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

// * ================================================================================================

func get_vlp_amount{pedersen_ptr: HashBuiltin*, range_check_ptr, global_config: GlobalConfig*}(
    order_tab: OrderTab*, base_amount: felt, quote_amount: felt, index_price: felt
) -> felt {
    alloc_locals;

    // ? calculate the right amount of vLP tokens to mint using the index price
    let (collateral_decimals) = token_decimals(global_config.collateral_token);

    let (base_decimals: felt) = token_decimals(order_tab.tab_header.base_token);
    let (base_price_decimals: felt) = price_decimals(order_tab.tab_header.base_token);

    tempvar decimal_conversion = base_decimals + base_price_decimals - collateral_decimals;
    let (multiplier: felt) = pow(10, decimal_conversion);

    let (base_nominal: felt, _) = unsigned_div_rem(base_amount * index_price, multiplier);
    let added_nominal = base_nominal + quote_amount;

    let (tab_base_nominal: felt, _) = unsigned_div_rem(
        order_tab.base_amount * index_price, multiplier
    );
    let tab_nominal = tab_base_nominal + order_tab.quote_amount;

    let vlp_supply = order_tab.vlp_supply;

    let (vlp_amount: felt, _) = unsigned_div_rem(vlp_supply * added_nominal, tab_nominal);

    return vlp_amount;
}

func get_updated_order_tab{
    pedersen_ptr: HashBuiltin*, range_check_ptr, global_config: GlobalConfig*
}(
    prev_order_tab: OrderTab,
    added_vlp_amount: felt,
    adde_base_amount: felt,
    added_quote_amount: felt,
) -> OrderTab {
    alloc_locals;

    let new_tab_hash = hash_order_tab_inner(
        prev_order_tab.tab_header,
        prev_order_tab.base_amount + adde_base_amount,
        prev_order_tab.quote_amount + added_quote_amount,
        prev_order_tab.vlp_supply + added_vlp_amount,
    );

    let new_order_tab = OrderTab(
        prev_order_tab.tab_idx,
        prev_order_tab.tab_header,
        prev_order_tab.base_amount + adde_base_amount,
        prev_order_tab.quote_amount + added_quote_amount,
        prev_order_tab.vlp_supply + added_vlp_amount,
        new_tab_hash,
    );

    return new_order_tab;
}

func update_state_after_tab_add_liq{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    global_config: GlobalConfig*,
    state_dict: DictAccess*,
    note_updates: Note*,
}(
    base_notes_in_len: felt,
    base_notes_in: Note*,
    base_refund_note: Note,
    quote_notes_in_len: felt,
    quote_notes_in: Note*,
    quote_refund_note: Note,
    vlp_note: Note,
    order_tab: OrderTab,
    new_order_tab: OrderTab,
) {
    alloc_locals;

    // ? Remove notes in and return refund notes
    open_tab_state_note_updates(
        base_notes_in_len,
        base_notes_in,
        quote_notes_in_len,
        quote_notes_in,
        base_refund_note,
        quote_refund_note,
    );

    // ? Update order tab and return vlp_note
    update_state_after_tab_register(vlp_note, order_tab, new_order_tab);

    return ();
}

// * ================================================================================================

func get_updated_position{
    pedersen_ptr: HashBuiltin*, range_check_ptr, global_config: GlobalConfig*
}(
    prev_position: PerpPosition, added_vlp_amount: felt, added_collateral_amount: felt
) -> PerpPosition {
    alloc_locals;

    let updated_margin = prev_position.margin + added_collateral_amount;
    let updated_vlp_supply = prev_position.vlp_supply + added_vlp_amount;

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

func update_state_after_position_add_liq{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    global_config: GlobalConfig*,
    state_dict: DictAccess*,
    note_updates: Note*,
}(
    collateral_notes_in_len: felt,
    collateral_notes_in: Note*,
    collateral_refund_note: Note,
    vlp_note: Note,
    position: PerpPosition,
    new_position: PerpPosition,
) {
    alloc_locals;

    // ? Update order tab and return vlp_note
    update_state_after_position_register(vlp_note, position, new_position);

    // ? Remove the collateral notes from the state
    _update_multi_inner(collateral_notes_in_len, collateral_notes_in);

    let pedersen_tmp = pedersen_ptr;

    // ? add the collateral refund note to the state
    if (collateral_refund_note.hash != 0) {
        // add_refund_note func is from order_tab.update_dicts
        add_refund_note(collateral_notes_in[0].index, collateral_refund_note);

        let pedersen_ptr = pedersen_tmp;
        return ();
    }

    return ();
}

// * ================================================================================================

func verify_tab_add_liq_sig{
    pedersen_ptr: HashBuiltin*, range_check_ptr, ecdsa_ptr: SignatureBuiltin*
}(
    tab_pub_key: felt,
    base_notes_in_len: felt,
    base_notes_in: Note*,
    base_refund_note: Note,
    quote_notes_in_len: felt,
    quote_notes_in: Note*,
    quote_refund_note: Note,
    close_order_fields: CloseOrderFields,
) {
    alloc_locals;

    let (close_order_fields_hash) = _hash_close_order_fields(close_order_fields);

    let msg_hash = _hash_tab_add_liq_message(
        tab_pub_key, base_refund_note.hash, quote_refund_note.hash, close_order_fields_hash
    );

    let (pub_key_sum: EcPoint) = sum_pub_keys(base_notes_in_len, base_notes_in, EcPoint(0, 0));
    let (pub_key_sum: EcPoint) = sum_pub_keys(quote_notes_in_len, quote_notes_in, pub_key_sum);

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

func _hash_tab_add_liq_message{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    tab_pub_key: felt,
    base_refund_hash: felt,
    quote_refund_hash: felt,
    close_order_fields_hash: felt,
) -> felt {
    alloc_locals;

    // & header_hash = H({tab_pub_key, base_refund_hash, quote_refund_hash, fields_hash})

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state_ptr) = hash_init();
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, tab_pub_key);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, base_refund_hash);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, quote_refund_hash);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, close_order_fields_hash);

        let (res) = hash_finalize(hash_state_ptr);
        let pedersen_ptr = hash_ptr;
        return res;
    }
}

// * ================================================================================================

func verify_position_add_liq_sig{
    pedersen_ptr: HashBuiltin*, range_check_ptr, ecdsa_ptr: SignatureBuiltin*
}(
    pos_address: felt,
    collateral_notes_in_len: felt,
    collateral_notes_in: Note*,
    collateral_refund_note: Note,
    close_order_fields: CloseOrderFields,
) {
    alloc_locals;

    let (close_order_fields_hash) = _hash_close_order_fields(close_order_fields);

    let msg_hash = _hash_position_add_liq_message(
        pos_address, collateral_refund_note.hash, close_order_fields_hash
    );

    let (pub_key_sum: EcPoint) = sum_pub_keys(
        collateral_notes_in_len, collateral_notes_in, EcPoint(0, 0)
    );

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

func _hash_position_add_liq_message{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    pos_address: felt, refund_hash: felt, close_order_fields_hash: felt
) -> felt {
    alloc_locals;

    // & header_hash = H({pos_address, refund_hash, close_fields_hash})

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state_ptr) = hash_init();
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, pos_address);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, refund_hash);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, close_order_fields_hash);

        let (res) = hash_finalize(hash_state_ptr);
        let pedersen_ptr = hash_ptr;
        return res;
    }
}
