from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import unsigned_div_rem, split_felt
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.bitwise import bitwise_xor, bitwise_and
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.pow import pow

from helpers.utils import Note, hash_note
from deposits_withdrawals.deposits.deposit_utils import Deposit
from deposits_withdrawals.withdrawals.withdraw_utils import Withdrawal

from perpetuals.order.order_structs import PerpPosition
from perpetuals.order.order_hash import verify_position_hash
from order_tabs.order_tab import OrderTab, TabHeader, verify_order_tab_hash

from unshielded_swaps.constants import BIT_64_AMOUNT
from rollup.global_config import GlobalConfig

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
    // & format: | index (59 bits) | position_size (64 bits) | max_vlp_supply (64 bits) | vlp_token (32 bits) | synthetic_token (32 bits) |
    // & format: | entry_price (64 bits) | liquidation_price (64 bits) | vlp_supply (64 bits) | last_funding_idx (32 bits) | order_side (1 bits) | allow_partial_liquidations (1 bits) |
    // & format: | public key <-> position_address (251 bits) |
    batched_position_info_slot1: felt,
    batched_position_info_slot2: felt,
    public_key: felt,
}

// Represents the struct of data written to the program output for every newly opened order tab
struct OrderTabOutput {
    // & format: | index (64 bits) | base_token (32 bits) | quote_token (32 bits) | max_vlp_supply (64 bits) | is_smart_contract (1 bits)
    // & format: | quote_hidden_amount (64 bits) | quote_hidden_amount (64 bits) | vlp_supply_hidden_amount (64 bits) | vlp_token (32 bits) |
    batched_tab_info_slot1: felt,
    batched_tab_info_slot2: felt,
    base_commitment: felt,
    quote_commitment: felt,
    vlp_supply_commitment: felt,
    public_key: felt,
}

// This is used to output the index of the note/position that has been spent/closed
// The class is only defined for clarity we could just use a felt instead
struct ZeroOutput {
    batched_idxs: felt,  // & | idx1 (64bit) | idx2 (64bit) | idx3 (64bit) |
}

// * ================================================================================================================================================================0
// * STATE * //

func write_state_updates_to_output{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    note_output_ptr: NoteDiffOutput*,
    position_output_ptr: PerpPositionOutput*,
    tab_output_ptr: OrderTabOutput*,
    empty_output_ptr: ZeroOutput*,
}(state_dict_start: DictAccess*, n_state_outputs: felt, note_outputs: Note*) {
    alloc_locals;

    let (zero_idxs: felt*) = alloc();

    // ? Write note/position/order_tab updates to the program_output
    let (zero_idxs_len: felt, zero_idxs: felt*) = _write_state_updates_to_output_inner(
        state_dict_start, n_state_outputs, note_outputs, 0, zero_idxs
    );

    // ? Write batched zero indexes to the output
    _write_zero_indexes_to_output(zero_idxs_len, zero_idxs);

    return ();
}

func _write_state_updates_to_output_inner{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    note_output_ptr: NoteDiffOutput*,
    position_output_ptr: PerpPositionOutput*,
    tab_output_ptr: OrderTabOutput*,
    empty_output_ptr: ZeroOutput*,
}(
    state_dict_start: DictAccess*,
    n_state_outputs: felt,
    note_outputs: Note*,
    zero_idxs_len: felt,
    zero_idxs: felt*,
) -> (zero_idxs_len: felt, zero_idxs: felt*) {
    alloc_locals;

    if (n_state_outputs == 0) {
        // ? Write zero outputs

        return (zero_idxs_len, zero_idxs);
    }

    let idx: felt = state_dict_start.key;
    let leaf_hash: felt = state_dict_start.new_value;

    if (nondet %{ leaf_node_types[ids.idx] == "note" %} != 0) {
        if (leaf_hash != 0) {
            write_note_update(note_outputs, idx, leaf_hash);

            let state_dict_start = state_dict_start + DictAccess.SIZE;
            return _write_state_updates_to_output_inner(
                state_dict_start, n_state_outputs - 1, note_outputs, zero_idxs_len, zero_idxs
            );
        } else {
            assert zero_idxs[zero_idxs_len] = idx;
            let zero_idxs_len = zero_idxs_len + 1;

            let state_dict_start = state_dict_start + DictAccess.SIZE;
            return _write_state_updates_to_output_inner(
                state_dict_start, n_state_outputs - 1, note_outputs, zero_idxs_len, zero_idxs
            );
        }
    }

    if (nondet %{ leaf_node_types[ids.idx] == "position" %} != 0) {
        if (leaf_hash != 0) {
            write_position_update(idx, leaf_hash);

            let state_dict_start = state_dict_start + DictAccess.SIZE;
            return _write_state_updates_to_output_inner(
                state_dict_start, n_state_outputs - 1, note_outputs, zero_idxs_len, zero_idxs
            );
        } else {
            assert zero_idxs[zero_idxs_len] = idx;
            let zero_idxs_len = zero_idxs_len + 1;

            let state_dict_start = state_dict_start + DictAccess.SIZE;
            return _write_state_updates_to_output_inner(
                state_dict_start, n_state_outputs - 1, note_outputs, zero_idxs_len, zero_idxs
            );
        }
    }

    if (nondet %{ leaf_node_types[ids.idx] == "order_tab" %} != 0) {
        if (leaf_hash != 0) {
            write_order_tab_update(idx, leaf_hash);

            let state_dict_start = state_dict_start + DictAccess.SIZE;
            return _write_state_updates_to_output_inner(
                state_dict_start, n_state_outputs - 1, note_outputs, zero_idxs_len, zero_idxs
            );
        } else {
            assert zero_idxs[zero_idxs_len] = idx;
            let zero_idxs_len = zero_idxs_len + 1;

            let state_dict_start = state_dict_start + DictAccess.SIZE;
            return _write_state_updates_to_output_inner(
                state_dict_start, n_state_outputs - 1, note_outputs, zero_idxs_len, zero_idxs
            );
        }
    }

    return (zero_idxs_len, zero_idxs);
}

// ?: Loop backwards through the notes array and write the last update for each index to the program output
func write_note_update{
    pedersen_ptr: HashBuiltin*, bitwise_ptr: BitwiseBuiltin*, note_output_ptr: NoteDiffOutput*
}(note_outputs: Note*, idx: felt, hash: felt) {
    alloc_locals;

    local array_position_idx: felt;
    %{ ids.array_position_idx = int(note_output_idxs[ids.idx]) %}

    let note_ouput: Note = note_outputs[array_position_idx];
    assert note_ouput.hash = hash;

    _write_new_note_to_output(note_ouput, idx);

    return ();
}

func write_position_update{
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    position_output_ptr: PerpPositionOutput*,
}(idx: felt, hash: felt) {
    alloc_locals;

    local position: PerpPosition;
    %{ read_output_position(ids.position.address_, ids.idx) %}

    verify_position_hash(position);
    assert position.hash = hash;

    _write_position_info_to_output(position, idx);

    return ();
}

func write_order_tab_update{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    tab_output_ptr: OrderTabOutput*,
}(idx: felt, hash: felt) {
    alloc_locals;

    // let (__fp__, _) = get_fp_and_pc();

    local order_tab: OrderTab;
    %{ read_output_order_tab(ids.order_tab.address_, ids.idx) %}

    verify_order_tab_hash(order_tab);
    assert order_tab.hash = hash;

    _write_order_tab_info_to_output(order_tab, idx);

    return ();
}

// * ================================================================================================================================================================
// * DEPOSITS/WITHDRAWALS * //

func write_deposit_info_to_output{
    pedersen_ptr: HashBuiltin*, range_check_ptr, deposit_output_ptr: DepositTransactionOutput*
}(deposit: Deposit) {
    alloc_locals;

    // & batched_note_info format: | deposit_id (64 bits) | token (32 bits) | amount (64 bits) |
    // & --------------------------  deposit_id => chain id (32 bits) | identifier (32 bits) |
    let output: DepositTransactionOutput* = deposit_output_ptr;
    assert output.batched_deposit_info = ((deposit.deposit_id * 2 ** 32) + deposit.token) * 2 **
        64 + deposit.amount;
    assert output.stark_key = deposit.deposit_address;

    let deposit_output_ptr = deposit_output_ptr + DepositTransactionOutput.SIZE;

    return ();
}

func write_withdrawal_info_to_output{
    range_check_ptr, pedersen_ptr: HashBuiltin*, withdraw_output_ptr: WithdrawalTransactionOutput*
}(withdrawal: Withdrawal) {
    alloc_locals;

    // & batched_note_info format: | withdrawal_chain_id (32 bits) | token (32 bits) | amount (64 bits) |
    let output: WithdrawalTransactionOutput* = withdraw_output_ptr;

    assert output.batched_withdraw_info = (
        (withdrawal.withdrawal_chain * 2 ** 32) + withdrawal.token
    ) * 2 ** 64 + withdrawal.amount;
    assert output.withdraw_address = withdrawal.withdrawal_address;

    let withdraw_output_ptr = withdraw_output_ptr + WithdrawalTransactionOutput.SIZE;

    return ();
}

func write_accumulated_hashes_to_output{
    range_check_ptr,
    pedersen_ptr: HashBuiltin*,
    accumulated_hashes: AccumulatedHashesOutput*,
    global_config: GlobalConfig*,
}(
    deposit_outputs_len: felt,
    deposit_outputs: DepositTransactionOutput*,
    withdraw_outputs_len: felt,
    withdraw_outputs: WithdrawalTransactionOutput*,
) {
    return output_accumulated_hashes(
        global_config.chain_ids_len,
        global_config.chain_ids,
        deposit_outputs_len,
        deposit_outputs,
        withdraw_outputs_len,
        withdraw_outputs,
    );
}

func output_accumulated_hashes{
    range_check_ptr,
    pedersen_ptr: HashBuiltin*,
    accumulated_hashes: AccumulatedHashesOutput*,
    global_config: GlobalConfig*,
}(
    chain_ids_len: felt,
    chain_ids: felt*,
    deposit_outputs_len: felt,
    deposit_outputs: DepositTransactionOutput*,
    withdraw_outputs_len: felt,
    withdraw_outputs: WithdrawalTransactionOutput*,
) {
    alloc_locals;

    if (chain_ids_len == 0) {
        return ();
    }

    // ? Get the accumulated hashes for the current chain
    let accumulated_deposit_hash = get_accumulated_deposit_hash(
        chain_ids[0], deposit_outputs_len, deposit_outputs, 0
    );
    let accumulated_withdraw_hash = get_accumulated_withdraw_hash(
        chain_ids[0], withdraw_outputs_len, withdraw_outputs, 0
    );

    // ? Write the accumulated hashes to the output
    let output: AccumulatedHashesOutput* = accumulated_hashes;

    assert output.chain_id = chain_ids[0];
    assert output.deposit_hash = accumulated_deposit_hash;
    assert output.withdrawal_hash = accumulated_withdraw_hash;

    let accumulated_hashes = accumulated_hashes + AccumulatedHashesOutput.SIZE;

    return output_accumulated_hashes(
        chain_ids_len - 1,
        &chain_ids[1],
        deposit_outputs_len,
        deposit_outputs,
        withdraw_outputs_len,
        withdraw_outputs,
    );
}

func get_accumulated_deposit_hash{range_check_ptr, pedersen_ptr: HashBuiltin*}(
    chain_id: felt,
    deposit_outputs_len: felt,
    deposit_outputs: DepositTransactionOutput*,
    accumulated_deposit_hash: felt,
) -> felt {
    if (deposit_outputs_len == 0) {
        return accumulated_deposit_hash;
    }

    let deposit_output: DepositTransactionOutput = deposit_outputs[0];

    // & batched_note_info format: | deposit_id (64 bits) | token (32 bits) | amount (64 bits) |
    // & --------------------------  deposit_id => chain id (32 bits) | identifier (32 bits) |
    let (deposit_chain_id, _) = split_felt(deposit_output.batched_deposit_info);

    if (deposit_chain_id != chain_id) {
        return get_accumulated_deposit_hash(
            chain_id,
            deposit_outputs_len - 1,
            deposit_outputs + DepositTransactionOutput.SIZE,
            accumulated_deposit_hash,
        );
    }

    let deposit_hash: felt = hash2{hash_ptr=pedersen_ptr}(
        deposit_output.batched_deposit_info, deposit_output.stark_key
    );

    let accumulated_deposit_hash: felt = hash2{hash_ptr=pedersen_ptr}(
        accumulated_deposit_hash, deposit_hash
    );

    return get_accumulated_deposit_hash(
        chain_id,
        deposit_outputs_len - 1,
        deposit_outputs + DepositTransactionOutput.SIZE,
        accumulated_deposit_hash,
    );
}

func get_accumulated_withdraw_hash{range_check_ptr, pedersen_ptr: HashBuiltin*}(
    chain_id: felt,
    withdraw_outputs_len: felt,
    withdraw_outputs: WithdrawalTransactionOutput*,
    accumulated_withdraw_hash: felt,
) -> felt {
    if (withdraw_outputs_len == 0) {
        return accumulated_withdraw_hash;
    }

    let withdraw_output: WithdrawalTransactionOutput = withdraw_outputs[0];

    // & batched_note_info format: | withdrawal_chain_id (32 bits) | token (32 bits) | amount (64 bits) |
    let devisor: felt = 2 ** 96;
    let (withdraw_chain_id, _) = unsigned_div_rem(withdraw_output.batched_withdraw_info, devisor);

    if (withdraw_chain_id != chain_id) {
        return get_accumulated_withdraw_hash(
            chain_id,
            withdraw_outputs_len - 1,
            withdraw_outputs + WithdrawalTransactionOutput.SIZE,
            accumulated_withdraw_hash,
        );
    }

    let withdraw_hash: felt = hash2{hash_ptr=pedersen_ptr}(
        withdraw_output.batched_withdraw_info, withdraw_output.withdraw_address
    );

    let accumulated_withdraw_hash: felt = hash2{hash_ptr=pedersen_ptr}(
        accumulated_withdraw_hash, withdraw_hash
    );

    return get_accumulated_withdraw_hash(
        chain_id,
        withdraw_outputs_len - 1,
        withdraw_outputs + WithdrawalTransactionOutput.SIZE,
        accumulated_withdraw_hash,
    );
}

// * ================================================================================================================================================================
// * INIT OUTPUT STRUCTS * //

// * ================================================================================================================================================================
// * HELPERS * //

// * Notes * //
func _write_new_note_to_output{
    pedersen_ptr: HashBuiltin*, bitwise_ptr: BitwiseBuiltin*, note_output_ptr: NoteDiffOutput*
}(note: Note, index: felt) {
    alloc_locals;

    let output: NoteDiffOutput* = note_output_ptr;

    let (trimed_blinding: felt) = bitwise_and(note.blinding_factor, BIT_64_AMOUNT);
    let (hidden_amount: felt) = bitwise_xor(note.amount, trimed_blinding);

    // & batched_note_info format: | token (32 bits) | hidden amount (64 bits) | idx (64 bits) |
    assert output.batched_note_info = ((note.token * 2 ** 64) + hidden_amount) * 2 ** 64 + index;
    let (comm: felt) = hash2{hash_ptr=pedersen_ptr}(note.amount, note.blinding_factor);
    assert output.commitment = comm;
    assert output.address = note.address.x;

    let note_output_ptr = note_output_ptr + NoteDiffOutput.SIZE;

    return ();
}

// * Positions * //
func _write_position_info_to_output{
    position_output_ptr: PerpPositionOutput*, pedersen_ptr: HashBuiltin*
}(position: PerpPosition, index: felt) {
    alloc_locals;

    let output: PerpPositionOutput* = position_output_ptr;

    // & | index (59 bits) | synthetic_token (32 bits) | position_size (64 bits) | max_vlp_supply (64 bits) | vlp_token (32 bits) |
    assert output.batched_position_info_slot1 = (
        (
            (position.index * 2 ** 32 + position.position_header.synthetic_token) * 2 ** 64 +
            position.position_size
        ) * 2 ** 64 +
        position.position_header.max_vlp_supply
    ) * 2 ** 32 + position.position_header.vlp_token;

    // & | entry_price (64 bits) | liquidation_price (64 bits) | vlp_supply (64 bits) | last_funding_idx (32 bits) | order_side (1 bits) | allow_partial_liquidations (1 bits) |
    assert output.batched_position_info_slot2 = (
        (
            (
                ((position.entry_price * 2 ** 64) + position.liquidation_price) * 2 ** 64 +
                position.vlp_supply
            ) * 2 ** 32 +
            position.last_funding_idx
        ) * 2 +
        position.order_side
    ) * 2 + position.position_header.allow_partial_liquidations;

    assert output.public_key = position.position_header.position_address;

    let position_output_ptr = position_output_ptr + PerpPositionOutput.SIZE;

    return ();
}

// * Order Tabs * //
func _write_order_tab_info_to_output{
    bitwise_ptr: BitwiseBuiltin*,
    tab_output_ptr: OrderTabOutput*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
}(order_tab: OrderTab, index: felt) {
    alloc_locals;

    let output: OrderTabOutput* = tab_output_ptr;

    let tab_header: TabHeader* = &order_tab.tab_header;

    let (_, base_low) = split_felt(tab_header.base_blinding);
    let (_, quote_low) = split_felt(tab_header.quote_blinding);
    let blinding_sum: felt = base_low + quote_low;

    let (base_trimed_blinding: felt) = bitwise_and(tab_header.base_blinding, BIT_64_AMOUNT);
    let (base_hidden_amount: felt) = bitwise_xor(order_tab.base_amount, base_trimed_blinding);
    let (quote_trimed_blinding: felt) = bitwise_and(tab_header.quote_blinding, BIT_64_AMOUNT);
    let (quote_hidden_amount: felt) = bitwise_xor(order_tab.quote_amount, quote_trimed_blinding);
    let (vlp_trimed_blinding: felt) = bitwise_and(blinding_sum, BIT_64_AMOUNT);
    let (vlp_supply_hidden_amount: felt) = bitwise_xor(order_tab.vlp_supply, vlp_trimed_blinding);

    // & format: | index (64 bits) | base_token (32 bits) | quote_token (32 bits) | max_vlp_supply (64 bits) | is_smart_contract (1 bits)
    let batched_info1 = (
        ((index * 2 ** 32 + tab_header.base_token) * 2 ** 32 + tab_header.quote_token) * 2 ** 64 +
        tab_header.max_vlp_supply
    ) * 2 + tab_header.is_smart_contract;
    assert output.batched_tab_info_slot1 = batched_info1;

    // & format: | base_hidden_amount (64 bits) | quote_hidden_amount (64 bits) | vlp_supply_hidden_amount (64 bits) | vlp_token (32 bits) |
    let batched_info2 = (
        (base_hidden_amount * 2 ** 64 + quote_hidden_amount) * 2 ** 64 + vlp_supply_hidden_amount
    ) * 2 ** 32 + tab_header.vlp_token;
    assert output.batched_tab_info_slot2 = batched_info2;

    let (base_commitment: felt) = hash2{hash_ptr=pedersen_ptr}(
        order_tab.base_amount, tab_header.base_blinding
    );
    let (quote_commitment: felt) = hash2{hash_ptr=pedersen_ptr}(
        order_tab.quote_amount, tab_header.quote_blinding
    );
    let vlp_supply_commitment: felt = _get_vlp_supply_commitment(
        order_tab.vlp_supply, blinding_sum
    );

    assert output.base_commitment = base_commitment;
    assert output.quote_commitment = quote_commitment;
    assert output.vlp_supply_commitment = vlp_supply_commitment;
    assert output.public_key = tab_header.pub_key;

    let tab_output_ptr = tab_output_ptr + OrderTabOutput.SIZE;

    return ();
}

func _get_vlp_supply_commitment{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    vlp_supply: felt, blinding_sum: felt
) -> felt {
    alloc_locals;

    if (vlp_supply == 0) {
        return 0;
    } else {
        let (vlp_supply_commitment: felt) = hash2{hash_ptr=pedersen_ptr}(vlp_supply, blinding_sum);

        return vlp_supply_commitment;
    }
}

// * Empty Outputs * //
func _write_zero_indexes_to_output{pedersen_ptr: HashBuiltin*, empty_output_ptr: ZeroOutput*}(
    zero_idxs_len: felt, zero_idxs: felt*
) {
    alloc_locals;

    // & Batch indexes by 3 to reduce calldata cost
    if (zero_idxs_len == 0) {
        return ();
    }

    if (zero_idxs_len == 1) {
        let output: ZeroOutput* = empty_output_ptr;
        assert output.batched_idxs = zero_idxs[0];

        let empty_output_ptr = empty_output_ptr + ZeroOutput.SIZE;

        return ();
    }
    if (zero_idxs_len == 2) {
        let batched_zero_idxs = (zero_idxs[0] * 2 ** 64) + zero_idxs[1];

        let output: ZeroOutput* = empty_output_ptr;
        assert output.batched_idxs = batched_zero_idxs;

        let empty_output_ptr = empty_output_ptr + ZeroOutput.SIZE;

        return ();
    } else {
        let batched_zero_idxs = ((zero_idxs[0] * 2 ** 64) + zero_idxs[1]) * 2 ** 64 + zero_idxs[2];

        let output: ZeroOutput* = empty_output_ptr;
        assert output.batched_idxs = batched_zero_idxs;

        let empty_output_ptr = empty_output_ptr + ZeroOutput.SIZE;

        return _write_zero_indexes_to_output(zero_idxs_len - 3, &zero_idxs[3]);
    }
}
