from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.dict import dict_new, dict_write, dict_update, dict_squash, dict_read
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.ec_point import EcPoint
from starkware.cairo.common.math import unsigned_div_rem, assert_le
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.hash_state import (
    hash_init,
    hash_finalize,
    hash_update,
    hash_update_single,
)

from helpers.utils import Note, construct_new_note, sum_notes, hash_note, take_fee
from helpers.signatures.signatures import verify_spot_tab_order_signature
from helpers.spot_helpers.dict_updates import update_state_dict

from helpers.spot_helpers.partial_fill_helpers import refund_partial_fill

from rollup.output_structs import ZeroOutput
from rollup.global_config import get_dust_amount, GlobalConfig

from order_tabs.update_dicts import update_tab_in_state
from order_tabs.order_tab import OrderTab, hash_order_tab_inner

from invisible_swaps.order.invisible_order import hash_transaction, Invisibl3Order

func execute_tab_orders{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    state_dict: DictAccess*,
    fee_tracker_dict: DictAccess*,
    global_config: GlobalConfig*,
    note_updates: Note*,
}(
    order_hash: felt,
    order_tab: OrderTab,
    invisibl3_order: Invisibl3Order,
    spent_amount: felt,
    received_amount: felt,
    fee_taken: felt,
) {
    alloc_locals;

    // ? Check that the order is not overspending
    assert_le(spent_amount, invisibl3_order.amount_spent);

    // ? Verify the signature
    verify_spot_tab_order_signature(order_hash, order_tab.tab_header.pub_key);

    // ? check the tokens and amounts are valid
    if (order_tab.tab_header.base_token == invisibl3_order.token_received) {
        // ? Is buy
        assert order_tab.tab_header.quote_token = invisibl3_order.token_spent;

        assert_le(spent_amount, order_tab.quote_amount);

        let updated_quote_amount = order_tab.quote_amount - spent_amount;
        let updated_base_amount = order_tab.base_amount + received_amount - fee_taken;

        let updated_tab_hash = hash_order_tab_inner(
            order_tab.tab_header, updated_base_amount, updated_quote_amount, order_tab.vlp_supply
        );

        // ? Update the state
        update_tab_in_state(order_tab, updated_base_amount, updated_quote_amount, updated_tab_hash);
    } else {
        // ? Is sell
        assert order_tab.tab_header.base_token = invisibl3_order.token_spent;
        assert order_tab.tab_header.quote_token = invisibl3_order.token_received;

        assert_le(spent_amount, order_tab.base_amount);

        let updated_quote_amount = order_tab.quote_amount + received_amount - fee_taken;
        let updated_base_amount = order_tab.base_amount - spent_amount;

        let updated_tab_hash = hash_order_tab_inner(
            order_tab.tab_header, updated_base_amount, updated_quote_amount, order_tab.vlp_supply
        );

        // ? Update the state
        update_tab_in_state(order_tab, updated_base_amount, updated_quote_amount, updated_tab_hash);
    }

    // ? take a fee
    take_fee(invisibl3_order.token_received, fee_taken);

    return ();
}
