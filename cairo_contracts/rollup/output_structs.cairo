from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import unsigned_div_rem
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.bitwise import bitwise_xor, bitwise_and
from starkware.cairo.common.registers import get_fp_and_pc

from helpers.utils import Note, hash_note
from deposits_withdrawals.deposits.deposit_utils import Deposit
from deposits_withdrawals.withdrawals.withdraw_utils import Withdrawal

from perpetuals.order.order_structs import PerpPosition
from perpetuals.order.order_hash import verify_position_hash
from order_tabs.order_tab import OrderTab, TabHeader, verify_order_tab_hash

from unshielded_swaps.constants import BIT_64_AMOUNT
from rollup.global_config import GlobalConfig

struct GlobalDexState {
    config_code: felt,  // why do we need this? (rename)
    init_state_root: felt,
    final_state_root: felt,
    state_tree_depth: felt,
    global_expiration_timestamp: felt,
    n_deposits: felt,
    n_withdrawals: felt,
    n_output_notes: felt,
    n_empty_notes: felt,
    n_output_positions: felt,
    n_empty_positions: felt,
    n_output_tabs: felt,
    n_empty_tabs: felt,
}

// Represents the struct of data written to the program output for each Note Modifictaion.
struct NoteDiffOutput {
    // & batched_note_info format: | token (32 bits) | hidden amount (64 bits) | idx (64 bits) |
    batched_note_info: felt,
    commitment: felt,
    address: felt,
}

// Represents the struct of data written to the program output for each Deposit.
struct DepositTransactionOutput {
    // & batched_note_info format: | deposit_id (64 bits) | token (32 bits) | amount (64 bits) |
    // & --------------------------  deposit_id => chain id (32 bits) | identifier (32 bits) |
    batched_deposit_info: felt,
    stark_key: felt,
}

// Represents the struct of data written to the program output for each Withdrawal.
struct WithdrawalTransactionOutput {
    // & batched_note_info format: | withdrawal_chain_id (32 bits) | token (32 bits) | amount (64 bits) |
    batched_withdraw_info: felt,
    withdraw_address: felt,  // This should be the eth address to withdraw from
}

struct AccumulatedHashesOutput {
    chain_id: felt,
    deposit_hash: felt,
    withdrawal_hash: felt,
}

// Represents the struct of data written to the program output for each perpetual position Modifictaion.
struct PerpPositionOutput {
    // & format: | index (32 bits) | synthetic_token (32 bits) | position_size (64 bits) | order_side (8 bits) | allow_partial_liquidations (8 bits) |
    // & format: | entry_price (64 bits) | liquidation_price (64 bits) | last_funding_idx (32 bits) |
    // & format: | public key <-> position_address (251 bits) |
    batched_position_info_slot1: felt,
    batched_position_info_slot2: felt,
    public_key: felt,
}

// Represents the struct of data written to the program output for every newly opened order tab
struct OrderTabOutput {
    // & format: | index (32 bits) | base_token (32 bits) | quote_token (32 bits) | base hidden amount (64 bits)
    // &          | quote hidden amount (64 bits) |  is_smart_contract (8 bits) | is_perp (8 bits) |
    batched_tab_info_slot1: felt,
    base_commitment: felt,
    quote_commitment: felt,
    public_key: felt,
}

// This is used to output the index of the note/position that has been spent/closed
// The class is only defined for clarity we could just use a felt instead
struct ZeroOutput {
    index: felt,
}

// * ================================================================================================================================================================0
// * STATE * //

func write_state_updates_to_output{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    note_output_ptr: NoteDiffOutput*,
    empty_note_output_ptr: ZeroOutput*,
    position_output_ptr: PerpPositionOutput*,
    empty_position_output_ptr: ZeroOutput*,
    tab_output_ptr: OrderTabOutput*,
    empty_tab_output_ptr: ZeroOutput*,
}(state_dict_start: DictAccess*, n_state_outputs: felt, note_outputs: Note*) {
    alloc_locals;

    if (n_state_outputs == 0) {
        return ();
    }

    let idx: felt = state_dict_start.key;
    let leaf_hash: felt = state_dict_start.new_value;

    if (nondet %{ leaf_node_types[ids.idx] == "note" %} != 0) {
        write_note_update(note_outputs, idx, leaf_hash);

        let state_dict_start = state_dict_start + DictAccess.SIZE;
        return write_state_updates_to_output(state_dict_start, n_state_outputs - 1, note_outputs);
    }

    if (nondet %{ leaf_node_types[ids.idx] == "position" %} != 0) {
        write_position_update(idx, leaf_hash);

        let state_dict_start = state_dict_start + DictAccess.SIZE;
        return write_state_updates_to_output(state_dict_start, n_state_outputs - 1, note_outputs);
    }

    if (nondet %{ leaf_node_types[ids.idx] == "order_tab" %} != 0) {
        write_order_tab_update(idx, leaf_hash);

        let state_dict_start = state_dict_start + DictAccess.SIZE;
        return write_state_updates_to_output(state_dict_start, n_state_outputs - 1, note_outputs);
    }

    return ();
}

// ?: Loop backwards through the notes array and write the last update for each index to the program output
func write_note_update{
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    note_output_ptr: NoteDiffOutput*,
    empty_note_output_ptr: ZeroOutput*,
}(note_outputs: Note*, idx: felt, hash: felt) {
    alloc_locals;

    if (hash == 0) {
        _write_zero_note_to_output(idx);

        return ();
    }

    local array_position_idx: felt;
    %{ ids.array_position_idx = int(note_output_idxs[ids.idx]) %}  // TODO: implement note_output_idxs

    let note_ouput: Note = note_outputs[array_position_idx];
    assert note_ouput.index = idx;
    assert note_ouput.hash = hash;

    _write_new_note_to_output(note_ouput);

    return ();
}

func write_position_update{
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    position_output_ptr: PerpPositionOutput*,
    empty_position_output_ptr: ZeroOutput*,
}(idx: felt, hash: felt) {
    alloc_locals;

    let (__fp__, _) = get_fp_and_pc();

    if (hash == 0) {
        _write_empty_position_to_output(idx);

        return ();
    }

    local position: PerpPosition;
    %{ read_output_position(ids.position.address_, ids.idx) %}

    verify_position_hash(position);
    assert position.index = idx;
    assert position.hash = hash;

    _write_position_info_to_output(position);

    return ();
}

func write_order_tab_update{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    tab_output_ptr: OrderTabOutput*,
    empty_tab_output_ptr: ZeroOutput*,
}(idx: felt, hash: felt) {
    alloc_locals;

    let (__fp__, _) = get_fp_and_pc();

    if (hash == 0) {
        _write_empty_tab_to_output(idx);

        return ();
    }

    local order_tab: OrderTab;
    %{ read_output_order_tab(ids.order_tab.address_, ids.idx) %}

    verify_order_tab_hash(order_tab);
    assert order_tab.tab_idx = idx;
    assert order_tab.hash = hash;

    _write_order_tab_info_to_output(order_tab);

    return ();
}

// * ================================================================================================================================================================
// * DEPOSITS/WITHDRAWALS * //

func write_deposit_info_to_output{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    deposit_output_ptr: DepositTransactionOutput*,
    accumulated_deposit_hash: felt,
}(deposit: Deposit) {
    alloc_locals;

    let (chain_id: felt, _) = unsigned_div_rem(deposit.deposit_id, 32);

    // & Write the deposit to the output --------------------------------------------
    let output: DepositTransactionOutput* = deposit_output_ptr;
    assert output.batched_deposit_info = ((deposit.deposit_id * 2 ** 64) + deposit.token) * 2 **
        64 + deposit.amount;
    assert output.stark_key = deposit.deposit_address;

    let deposit_output_ptr = deposit_output_ptr + DepositTransactionOutput.SIZE;

    // & Update the accumulated deposit hashes --------------------------------------ž

    // ? The hash of the current deposit
    let (current_hash: felt) = hash2{hash_ptr=pedersen_ptr}(
        output.batched_deposit_info, output.stark_key
    );
    // ? hash the previous accumulated hash with the current deposit hash to get the new accumulated hash
    let (new_hash: felt) = hash2{hash_ptr=pedersen_ptr}(accumulated_deposit_hash, current_hash);

    let accumulated_deposit_hash = new_hash;

    return ();
}

func write_withdrawal_info_to_output{
    range_check_ptr,
    pedersen_ptr: HashBuiltin*,
    withdraw_output_ptr: WithdrawalTransactionOutput*,
    accumulated_withdrawal_hashes: DictAccess*,
}(withdrawal: Withdrawal) {
    alloc_locals;

    // & Write the withdrawal to the output --------------------------------------------
    let output: WithdrawalTransactionOutput* = withdraw_output_ptr;

    assert output.batched_withdraw_info = (
        (withdrawal.withdrawal_chain * 2 ** 32) + withdrawal.token
    ) * 2 ** 64 + withdrawal.amount;
    assert output.withdraw_address = withdrawal.withdrawal_address;

    let withdraw_output_ptr = withdraw_output_ptr + WithdrawalTransactionOutput.SIZE;

    // & Update the accumulated withdrawal hashes ----------------------------------------
    // ? Get the previous accumulated hash
    local prev_hash: felt;
    %{ ids.prev_hash = accumulated_withdrawal_hashes[ids.withdrawal.withdrawal_chain] %}
    // ? The hash of the current withdrawal
    let (current_hash: felt) = hash2{hash_ptr=pedersen_ptr}(
        output.batched_withdraw_info, output.withdraw_address
    );
    // ? hash the previous accumulated hash with the current withdrawal hash to get the new accumulated hash
    let (new_hash: felt) = hash2{hash_ptr=pedersen_ptr}(prev_hash, current_hash);

    let accumulated_withdrawal_hashes_ptr = accumulated_withdrawal_hashes;
    assert accumulated_withdrawal_hashes_ptr.key = withdrawal.withdrawal_chain;
    assert accumulated_withdrawal_hashes_ptr.prev_value = prev_hash;
    assert accumulated_withdrawal_hashes_ptr.new_value = new_hash;

    let accumulated_withdrawal_hashes = accumulated_withdrawal_hashes + DictAccess.SIZE;

    return ();
}

func write_accumulated_deposit_hashes_to_output{accumulated_hashes_ptr: AccumulatedHashesOutput*}(
    squashed_deposit_hashes_dict: DictAccess*, squashed_deposit_withdrawal_dict: DictAccess*
) {
    local chain_ids_len: felt;
    local chain_ids: felt*;
    %{
        chain_ids = program_input["global_dex_state"]["chain_ids"]

        ids.arr_len = len(chain_ids)

        memory[ids.arr] = chain_ids_addr = segments.add()
        for i, cid in enumerate(chain_ids):
            memory[chain_ids_addr + i] = int(cid)
    %}

    return write_accumulated_deposit_hashes_to_output_inner(
        squashed_deposit_hashes_dict, squashed_deposit_withdrawal_dict, chain_ids_len, chain_ids
    );
}

func write_accumulated_deposit_hashes_to_output_inner{
    accumulated_hashes_ptr: AccumulatedHashesOutput*
}(
    squashed_deposit_hashes_dict: DictAccess*,
    squashed_deposit_withdrawal_dict: DictAccess*,
    chain_ids_len: felt,
    chain_ids: felt*,
) {
    if (chain_ids_len == 0) {
        return ();
    }

    let chain_id: felt = chain_ids[0];

    let deposit_chain_id = squashed_deposit_hashes_dict.key;
    let withdrawal_chain_id = squashed_deposit_withdrawal_dict.key;

    // let deposit_match = deposit_chain_id == chain_id;
    // let withdrawal_match = withdrawal_chain_id == chain_id;

    if (deposit_chain_id == chain_id) {
        // both deposit and withdrawal hashes match chain_id
        if (withdrawal_chain_id == chain_id) {
            let output: AccumulatedHashesOutput* = accumulated_hashes_ptr;

            let deposit_hash: felt = squashed_deposit_hashes_dict.new_value;
            let withdrawal_hash: felt = squashed_deposit_withdrawal_dict.new_value;

            assert output.chain_id = chain_id;
            assert output.deposit_hash = deposit_hash;
            assert output.withdrawal_hash = withdrawal_hash;

            let accumulated_hashes_ptr = accumulated_hashes_ptr + AccumulatedHashesOutput.SIZE;

            return write_accumulated_deposit_hashes_to_output_inner(
                squashed_deposit_hashes_dict + DictAccess.SIZE,
                squashed_deposit_withdrawal_dict + DictAccess.SIZE,
                chain_ids_len - 1,
                &chain_ids[1],
            );
        } else {
            // only deposit hash matches chain_id

            let output: AccumulatedHashesOutput* = accumulated_hashes_ptr;

            let deposit_hash: felt = squashed_deposit_hashes_dict.new_value;
            let withdrawal_hash: felt = 0;

            assert output.chain_id = chain_id;
            assert output.deposit_hash = deposit_hash;
            assert output.withdrawal_hash = withdrawal_hash;

            let accumulated_hashes_ptr = accumulated_hashes_ptr + AccumulatedHashesOutput.SIZE;

            return write_accumulated_deposit_hashes_to_output_inner(
                squashed_deposit_hashes_dict + DictAccess.SIZE,
                squashed_deposit_withdrawal_dict,
                chain_ids_len - 1,
                &chain_ids[1],
            );
        }
    }

    if (withdrawal_chain_id == chain_id) {
        // both deposit and withdrawal hashes match chain_id
        if (deposit_chain_id == chain_id) {
            let output: AccumulatedHashesOutput* = accumulated_hashes_ptr;

            let deposit_hash: felt = squashed_deposit_hashes_dict.new_value;
            let withdrawal_hash: felt = squashed_deposit_withdrawal_dict.new_value;

            assert output.chain_id = chain_id;
            assert output.deposit_hash = deposit_hash;
            assert output.withdrawal_hash = withdrawal_hash;

            let accumulated_hashes_ptr = accumulated_hashes_ptr + AccumulatedHashesOutput.SIZE;

            return write_accumulated_deposit_hashes_to_output_inner(
                squashed_deposit_hashes_dict + DictAccess.SIZE,
                squashed_deposit_withdrawal_dict + DictAccess.SIZE,
                chain_ids_len - 1,
                &chain_ids[1],
            );
        } else {
            // only withdrawal hash matches chain_id

            let output: AccumulatedHashesOutput* = accumulated_hashes_ptr;

            let deposit_hash: felt = 0;
            let withdrawal_hash: felt = squashed_deposit_withdrawal_dict.new_value;

            assert output.chain_id = chain_id;
            assert output.deposit_hash = deposit_hash;
            assert output.withdrawal_hash = withdrawal_hash;

            let accumulated_hashes_ptr = accumulated_hashes_ptr + AccumulatedHashesOutput.SIZE;

            return write_accumulated_deposit_hashes_to_output_inner(
                squashed_deposit_hashes_dict,
                squashed_deposit_withdrawal_dict + DictAccess.SIZE,
                chain_ids_len - 1,
                &chain_ids[1],
            );
        }
    }
}

// * ================================================================================================================================================================0
// * INIT OUTPUT STRUCTS * //

func init_output_structs{pedersen_ptr: HashBuiltin*}(dex_state_ptr: GlobalDexState*) {
    %{
        global_dex_state = program_input["global_dex_state"]
        program_input_counts = global_dex_state["program_input_counts"]
        ids.dex_state_ptr.config_code = int(global_dex_state["config_code"])
        ids.dex_state_ptr.init_state_root = int(global_dex_state["init_state_root"])
        ids.dex_state_ptr.final_state_root = int(global_dex_state["final_state_root"])
        ids.dex_state_ptr.state_tree_depth = int(global_dex_state["state_tree_depth"])
        ids.dex_state_ptr.global_expiration_timestamp = int(global_dex_state["global_expiration_timestamp"])
        ids.dex_state_ptr.n_deposits = int(program_input_counts["n_deposits"])
        ids.dex_state_ptr.n_withdrawals = int(program_input_counts["n_withdrawals"])
        ids.dex_state_ptr.n_output_positions = int(program_input_counts["n_output_positions"])
        ids.dex_state_ptr.n_empty_positions = int(program_input_counts["n_empty_positions"])
        ids.dex_state_ptr.n_output_notes = int(program_input_counts["n_output_notes"]) 
        ids.dex_state_ptr.n_empty_notes = int(program_input_counts["n_empty_notes"])
        ids.dex_state_ptr.n_output_tabs = int(program_input_counts["n_output_tabs"]) 
        ids.dex_state_ptr.n_empty_tabs = int(program_input_counts["n_empty_tabs"])

        global_config = program_input["global_config"]

        global_config_output_ptr = ids.dex_state_ptr.address_ + ids.GlobalDexState.SIZE
        assets = global_config["assets"]
        decimals_per_asset = global_config["decimals_per_asset"]
        price_decimals_per_asset = global_config["price_decimals_per_asset"]
        leverage_bounds_per_asset = global_config["leverage_bounds_per_asset"]
        dust_amount_per_asset = global_config["dust_amount_per_asset"]
        observers = global_config["observers"]


        counter = 0
        memory[global_config_output_ptr + counter] = len(assets)
        counter += 1
        for i in range(len(assets)):
            memory[global_config_output_ptr + counter + i] = assets[i]
        counter += len(assets)
        memory[global_config_output_ptr + counter] = global_config["collateral_token"]
        counter += 1
        for i in range(len(decimals_per_asset)):
            memory[global_config_output_ptr + counter + i] = decimals_per_asset[i]
        counter += len(decimals_per_asset)
        for i in range(len(price_decimals_per_asset)):
            memory[global_config_output_ptr + counter + i] = price_decimals_per_asset[i]
        counter += len(price_decimals_per_asset)
        memory[global_config_output_ptr + counter] = global_config["leverage_decimals"]
        counter += 1
        for i in range(0, len(leverage_bounds_per_asset), 3):
            memory[global_config_output_ptr + counter + i] = int(leverage_bounds_per_asset[i])
            memory[global_config_output_ptr + counter + i+1] = int(leverage_bounds_per_asset[i+1]*100)
            memory[global_config_output_ptr + counter + i+2] = int(leverage_bounds_per_asset[i+2]*100)
        counter += len(leverage_bounds_per_asset)
        for i in range(len(dust_amount_per_asset)):
            memory[global_config_output_ptr + counter + i] = dust_amount_per_asset[i]
        counter += len(dust_amount_per_asset)
        memory[global_config_output_ptr + counter] = len(global_config["observers"])
        counter += 1
        for i in range(len(observers)):
            memory[global_config_output_ptr + counter + i] = int(observers[i])
    %}

    return ();
}

// * ================================================================================================================================================================0
// * HELPERS * //

// * Notes * //
func _write_new_note_to_output{
    pedersen_ptr: HashBuiltin*, bitwise_ptr: BitwiseBuiltin*, note_output_ptr: NoteDiffOutput*
}(note: Note) {
    alloc_locals;

    let output: NoteDiffOutput* = note_output_ptr;

    let (trimed_blinding: felt) = bitwise_and(note.blinding_factor, BIT_64_AMOUNT);
    let (hidden_amount: felt) = bitwise_xor(note.amount, trimed_blinding);

    // & batched_note_info format: | token (32 bits) | hidden amount (64 bits) | idx (64 bits) |
    assert output.batched_note_info = ((note.token * 2 ** 32) + hidden_amount) * 2 ** 64 +
        note.index;
    let (comm: felt) = hash2{hash_ptr=pedersen_ptr}(note.amount, note.blinding_factor);
    assert output.commitment = comm;
    assert output.address = note.address.x;

    let note_output_ptr = note_output_ptr + NoteDiffOutput.SIZE;

    return ();
}

func _write_zero_note_to_output{pedersen_ptr: HashBuiltin*, empty_note_output_ptr: ZeroOutput*}(
    index: felt
) {
    alloc_locals;

    let output: ZeroOutput* = empty_note_output_ptr;

    assert output.index = index;

    let empty_note_output_ptr = empty_note_output_ptr + ZeroOutput.SIZE;

    return ();
}

// * Positions * //
func _write_position_info_to_output{
    position_output_ptr: PerpPositionOutput*, pedersen_ptr: HashBuiltin*
}(position: PerpPosition) {
    alloc_locals;

    let output: PerpPositionOutput* = position_output_ptr;

    // & | index (32 bits) | synthetic_token (32 bits) | position_size (64 bits) | order_side (8 bits) | allow_partial_liquidations (8 bit)
    assert output.batched_position_info_slot1 = (
        ((position.index * 2 ** 32) + position.position_header.synthetic_token) * 2 ** 32 +
        position.position_size
    ) * 2 ** 16 + position.order_side * 2 ** 8 +
        position.position_header.allow_partial_liquidations;

    // & | entry_price (64 bits) | liquidation_price (64 bits) | last_funding_idx (32 bits)
    assert output.batched_position_info_slot2 = (
        ((position.entry_price * 2 ** 64) + position.liquidation_price) * 2 ** 32 +
        position.last_funding_idx
    );
    assert output.public_key = position.position_header.position_address;

    let position_output_ptr = position_output_ptr + PerpPositionOutput.SIZE;

    return ();
}

func _write_empty_position_to_output{empty_position_output_ptr: ZeroOutput*}(position_idx: felt) {
    alloc_locals;

    let output: ZeroOutput* = empty_position_output_ptr;

    assert output.index = position_idx;

    let empty_position_output_ptr = empty_position_output_ptr + ZeroOutput.SIZE;

    return ();
}

// * Order Tabs * //
func _write_order_tab_info_to_output{
    bitwise_ptr: BitwiseBuiltin*, tab_output_ptr: OrderTabOutput*, pedersen_ptr: HashBuiltin*
}(order_tab: OrderTab) {
    alloc_locals;

    let output: OrderTabOutput* = tab_output_ptr;

    let tab_header: TabHeader* = &order_tab.tab_header;

    let (base_trimed_blinding: felt) = bitwise_and(tab_header.base_blinding, BIT_64_AMOUNT);
    let (base_hidden_amount: felt) = bitwise_xor(order_tab.base_amount, base_trimed_blinding);
    let (quote_trimed_blinding: felt) = bitwise_and(tab_header.quote_blinding, BIT_64_AMOUNT);
    let (quote_hidden_amount: felt) = bitwise_xor(order_tab.quote_amount, quote_trimed_blinding);

    // & format: | index (32 bits) | base_token (32 bits) | quote_token (32 bits) | base hidden amount (64 bits)
    // &          | quote hidden amount (64 bits) |  is_smart_contract (8 bits) | is_perp (8 bits) |
    let o1 = ((order_tab.tab_idx * 2 ** 32) + tab_header.base_token * 2 ** 32) +
        tab_header.quote_token;
    let o2 = ((o1 * 2 ** 32) + base_hidden_amount * 2 ** 64) + quote_hidden_amount;
    assert output.batched_tab_info_slot1 = (o2 * 2 ** 64) + tab_header.is_smart_contract * 2 ** 8 +
        tab_header.is_perp;

    let (base_commitment: felt) = hash2{hash_ptr=pedersen_ptr}(
        order_tab.base_amount, tab_header.base_blinding
    );
    let (quote_commitment: felt) = hash2{hash_ptr=pedersen_ptr}(
        order_tab.quote_amount, tab_header.quote_blinding
    );

    assert output.base_commitment = base_commitment;
    assert output.quote_commitment = quote_commitment;
    assert output.public_key = tab_header.pub_key;

    let tab_output_ptr = tab_output_ptr + OrderTabOutput.SIZE;

    return ();
}

func _write_empty_tab_to_output{empty_tab_output_ptr: ZeroOutput*}(tab_idx: felt) {
    alloc_locals;

    let output: ZeroOutput* = empty_tab_output_ptr;

    assert output.index = tab_idx;

    let empty_tab_output_ptr = empty_tab_output_ptr + ZeroOutput.SIZE;

    return ();
}
