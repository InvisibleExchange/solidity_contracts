from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import unsigned_div_rem
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.bitwise import bitwise_xor, bitwise_and

from helpers.utils import Note, hash_note
from deposits_withdrawals.deposits.deposit_utils import Deposit
from deposits_withdrawals.withdrawals.withdraw_utils import Withdrawal

from perpetuals.order.order_structs import PerpPosition
from perpetuals.order.order_hash import verify_position_hash

from unshielded_swaps.constants import BIT_64_AMOUNT
from rollup.global_config import GlobalConfig

struct GlobalDexState {
    config_code: felt,  // why do we need this? (rename)
    init_state_root: felt,
    final_state_root: felt,
    init_perp_state_root: felt,
    final_perp_state_root: felt,
    state_tree_depth: felt,
    perp_tree_depth: felt,
    global_expiration_timestamp: felt,
    n_deposits: felt,
    n_withdrawals: felt,
    n_output_positions: felt,
    n_empty_positions: felt,
    n_output_notes: felt,
    n_zero_notes: felt,
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
// * NOTES * //

// func write_note_dict_to_output{
//     pedersen_ptr: HashBuiltin*,
//     bitwise_ptr: BitwiseBuiltin*,
//     note_output_ptr: NoteDiffOutput*,
//     zero_note_output_ptr: ZeroOutput*,
// }(note_dict_start: DictAccess*, n_output_notes: felt) {
//     alloc_locals;

// if (n_output_notes == 0) {
//         return ();
//     }

// let idx: felt = note_dict_start.key;
//     let note_hash: felt = note_dict_start.new_value;

// if (note_hash == 0) {
//         _write_zero_note_to_output(idx);

// let note_dict_ptr = note_dict_start + DictAccess.SIZE;
//         return write_note_dict_to_output(note_dict_ptr, n_output_notes - 1);
//     }

// local note: Note;
//     %{
//         note_ = output_notes[ids.idx]

// memory[ids.note.address_ + ADDRESS_OFFSET + 0 ] = int(note_["address"]["x"])
//         memory[ids.note.address_ + ADDRESS_OFFSET + 1 ] = int(note_["address"]["y"])
//         memory[ids.note.address_ + TOKEN_OFFSET] = int(note_["token"])
//         memory[ids.note.address_ + AMOUNT_OFFSET] = int(note_["amount"])
//         memory[ids.note.address_ + BLINDING_FACTOR_OFFSET] = int(note_["blinding"])
//         memory[ids.note.address_ + INDEX_OFFSET] = int(note_["index"])
//         memory[ids.note.address_ + HASH_OFFSET] = int(note_["hash"])
//     %}

// let (hash: felt) = hash_note(note);

// %{
//         #     if ids.note_hash != ids.hash:
//         #         print("ERROR: index is : ", ids.idx)
//         #         print("ERROR: note hash is : ", ids.note_hash)
//         #         print("ERROR: note hash should be : ", ids.hash)
//         #         print("ERROR: note is : ", note_)
//         #
//     %}

// assert note_hash = hash;

// _write_new_note_to_output(note);

// let note_dict_ptr = note_dict_start + DictAccess.SIZE;
//     return write_note_dict_to_output(note_dict_ptr, n_output_notes - 1);
// }

// ?: Loop backwards through the notes array and write the last update for each index to the program output
func write_note_updates_to_output{
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    note_output_ptr: NoteDiffOutput*,
    zero_note_output_ptr: ZeroOutput*,
}(note_outputs: Note*, i: felt) {
    if (i == 0) {
        return ();
    }

    let note = note_outputs[i - 1];
    let note_idx = note.index;

    // ? Check if the index in the array already exists
    if (nondet %{ ids.note_idx in stored_indexes %} != 0) {
        // ? If it exists then get the note at that index and prove that it does and skip the update
        local array_position_idx: felt;
        %{ ids.array_position_idx = stored_indexes[ids.note_idx] %}

        assert_le(i - 1, array_position_idx);

        let prev_note_at_idx = note_outputs[array_position_idx];

        assert prev_note_at_idx.index = note_idx;
    } else {
        // ? If it does not exist then write the note to the output and store the index with hints
        if (note.hash == 0) {
            _write_zero_note_to_output(note_idx);
        } else {
            _write_new_note_to_output(note);
        }

        %{ stored_indexes[ids.note_idx] = i-1 %}
    }

    return write_note_updates_to_output(note_outputs_len, note_outputs, i - 1);
}

// * ================================================================================================================================================================0
// * DEPOSITS/WITHDRAWALS * //

func write_deposit_info_to_output{
    pedersen_ptr: HashBuiltin*,
    deposit_output_ptr: DepositTransactionOutput*,
    accumulated_deposit_hashes: DictAccess*,
}(deposit: Deposit) {
    alloc_locals;

    let (chain_id: felt, _) = unsigned_div_rem(deposit.deposit_id, 32);

    // & Write the deposit to the output --------------------------------------------
    let output: DepositTransactionOutput* = deposit_output_ptr;
    assert output.batched_deposit_info = ((deposit.deposit_id * 2 ** 64) + deposit.token) * 2 **
        64 + deposit.amount;
    assert output.stark_key = deposit.deposit_address;

    let deposit_output_ptr = deposit_output_ptr + DepositTransactionOutput.SIZE;

    // & Update the accumulated deposit hashes --------------------------------------
    // ? Get the previous accumulated hash
    local prev_hash: felt;
    %{ ids.prev_hash = accumulated_deposit_hashes[ids.chain_id] %}
    // ? The hash of the current deposit
    let (current_hash: felt) = hash2{hash_ptr=pedersen_ptr}(
        output.batched_deposit_info, output.stark_key
    );
    // ? hash the previous accumulated hash with the current deposit hash to get the new accumulated hash
    let (new_hash: felt) = hash2{hash_ptr=pedersen_ptr}(prev_hash, current_hash);

    let accumulated_deposit_hashes_ptr = accumulated_deposit_hashes;
    assert accumulated_deposit_hashes_ptr.key = chain_id;
    assert accumulated_deposit_hashes_ptr.prev_value = prev_hash;
    assert accumulated_deposit_hashes_ptr.new_value = new_hash;

    let accumulated_deposit_hashes = accumulated_deposit_hashes + DictAccess.SIZE;

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
        (withdrawal.withdrawal_id * 2 ** 32) + withdrawal.token
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
    local arr_len: felt;
    local arr: felt*;
    %{
        chain_ids = program_input["global_dex_state"]["chain_ids"]

        ids.arr_len = len(chain_ids)

        memory[ids.arr] = chain_ids_addr = segments.add()
        for i, cid in enumerate(chain_ids):
            memory[chain_ids_addr + i] = int(cid)
    %}

    return write_accumulated_deposit_hashes_to_output_inner(
        squashed_deposit_hashes_dict, squashed_deposit_withdrawal_dict, len
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
// * POSITIONS * //

func write_position_dict_to_output{
    pedersen_ptr: HashBuiltin*,
    position_output_ptr: PerpPositionOutput*,
    empty_position_output_ptr: ZeroOutput*,
}(position_dict_start: DictAccess*, n_output_positions: felt) {
    alloc_locals;

    if (n_output_positions == 0) {
        return ();
    }

    let idx: felt = position_dict_start.key;
    let position_hash: felt = position_dict_start.new_value;

    if (position_hash == 0) {
        write_empty_position_to_output(idx);

        let position_dict_ptr = position_dict_start + DictAccess.SIZE;
        return write_position_dict_to_output(position_dict_ptr, n_output_positions - 1);
    }

    local position: PerpPosition;
    %{
        position_ = output_positions[ids.idx]
        memory[ids.position.address_ + PERP_POSITION_ORDER_SIDE_OFFSET] = int(position_["order_side"])
        memory[ids.position.address_ + PERP_POSITION_SYNTHETIC_TOKEN_OFFSET] = int(position_["synthetic_token"])
        memory[ids.position.address_ + PERP_POSITION_COLLATERAL_TOKEN_OFFSET] = int(position_["collateral_token"])
        memory[ids.position.address_ + PERP_POSITION_POSITION_SIZE_OFFSET] = int(position_["position_size"])
        memory[ids.position.address_ + PERP_POSITION_MARGIN_OFFSET] = int(position_["margin"])
        memory[ids.position.address_ + PERP_POSITION_ENTRY_PRICE_OFFSET] = int(position_["entry_price"])
        memory[ids.position.address_ + PERP_POSITION_LIQUIDATION_PRICE_OFFSET] = int(position_["liquidation_price"])
        memory[ids.position.address_ + PERP_POSITION_BANKRUPTCY_PRICE_OFFSET] = int(position_["bankruptcy_price"])
        memory[ids.position.address_ + PERP_POSITION_ADDRESS_OFFSET] = int(position_["position_address"])
        memory[ids.position.address_ + PERP_POSITION_LAST_FUNDING_IDX_OFFSET] = int(position_["last_funding_idx"])
        memory[ids.position.address_ + PERP_POSITION_INDEX_OFFSET] = int(position_["index"])
        memory[ids.position.address_ + PERP_POSITION_HASH_OFFSET] = int(position_["hash"])
        memory[ids.position.address_ + PERP_POSITION_PARTIAL_LIQUIDATIONS_OFFSET] = int(position_["allow_partial_liquidations"])
    %}

    verify_position_hash(position);
    assert position.hash = position_hash;

    write_position_info_to_output(position);

    let position_dict_ptr = position_dict_start + DictAccess.SIZE;
    return write_position_dict_to_output(position_dict_ptr, n_output_positions - 1);
}

// * ================================================================================================================================================================0
// * ORDER TABS * //

func write_order_tab_dict_to_output{
    pedersen_ptr: HashBuiltin*,
    order_tab_output_ptr: OrderTabOutput*,
    empty_order_tabs_output_ptr: ZeroOutput*,
}(order_tab_dict_start: DictAccess*, n_output_tabs: felt) {
    alloc_locals;

    if (n_output_tabs == 0) {
        return ();
    }

    let idx: felt = order_tab_dict_start.key;
    let tab_hash: felt = order_tab_dict_start.new_value;

    if (tab_hash == 0) {
        write_empty_tab_to_output(idx);

        let tab_dict_ptr = order_tab_dict_start + DictAccess.SIZE;
        return write_order_tab_dict_to_output(tab_dict_ptr, n_output_tabs - 1);
    }

    local order_tab: OrderTab;
    // %{
    //     position_ = output_positions[ids.idx]
    //     memory[ids.position.address_ + PERP_POSITION_ORDER_SIDE_OFFSET] = int(position_["order_side"])
    //     memory[ids.position.address_ + PERP_POSITION_SYNTHETIC_TOKEN_OFFSET] = int(position_["synthetic_token"])
    //     memory[ids.position.address_ + PERP_POSITION_COLLATERAL_TOKEN_OFFSET] = int(position_["collateral_token"])
    //     memory[ids.position.address_ + PERP_POSITION_POSITION_SIZE_OFFSET] = int(position_["position_size"])
    //     memory[ids.position.address_ + PERP_POSITION_MARGIN_OFFSET] = int(position_["margin"])
    //     memory[ids.position.address_ + PERP_POSITION_ENTRY_PRICE_OFFSET] = int(position_["entry_price"])
    //     memory[ids.position.address_ + PERP_POSITION_LIQUIDATION_PRICE_OFFSET] = int(position_["liquidation_price"])
    //     memory[ids.position.address_ + PERP_POSITION_BANKRUPTCY_PRICE_OFFSET] = int(position_["bankruptcy_price"])
    //     memory[ids.position.address_ + PERP_POSITION_ADDRESS_OFFSET] = int(position_["position_address"])
    //     memory[ids.position.address_ + PERP_POSITION_LAST_FUNDING_IDX_OFFSET] = int(position_["last_funding_idx"])
    //     memory[ids.position.address_ + PERP_POSITION_INDEX_OFFSET] = int(position_["index"])
    //     memory[ids.position.address_ + PERP_POSITION_HASH_OFFSET] = int(position_["hash"])
    //     memory[ids.position.address_ + PERP_POSITION_PARTIAL_LIQUIDATIONS_OFFSET] = int(position_["allow_partial_liquidations"])
    // %}

    // verify_position_hash(position);
    // assert position.hash = position_hash;

    write_order_tab_info_to_output(order_tab);

    let tab_dict_ptr = order_tab_dict_start + DictAccess.SIZE;
    return write_order_tab_dict_to_output(tab_dict_ptr, n_output_tabs - 1);
}

// * ================================================================================================================================================================0
// * INIT OUTPUT STRUCTS * //

func init_output_structs{pedersen_ptr: HashBuiltin*}(dex_state_ptr: GlobalDexState*) {
    %{
        global_dex_state = program_input["global_dex_state"]
        ids.dex_state_ptr.config_code = int(global_dex_state["config_code"])
        ids.dex_state_ptr.init_state_root = int(global_dex_state["init_state_root"])
        ids.dex_state_ptr.final_state_root = int(global_dex_state["final_state_root"])
        ids.dex_state_ptr.init_perp_state_root = int(global_dex_state["init_perp_state_root"])
        ids.dex_state_ptr.final_perp_state_root = int(global_dex_state["final_perp_state_root"])
        ids.dex_state_ptr.state_tree_depth = int(global_dex_state["state_tree_depth"])
        ids.dex_state_ptr.perp_tree_depth = int(global_dex_state["perp_tree_depth"])
        ids.dex_state_ptr.global_expiration_timestamp = int(global_dex_state["global_expiration_timestamp"])
        ids.dex_state_ptr.n_deposits = int(global_dex_state["n_deposits"])
        ids.dex_state_ptr.n_withdrawals = int(global_dex_state["n_withdrawals"])
        ids.dex_state_ptr.n_output_positions = int(global_dex_state["n_output_positions"])
        ids.dex_state_ptr.n_empty_positions = int(global_dex_state["n_empty_positions"])
        ids.dex_state_ptr.n_output_notes = int(global_dex_state["n_output_notes"]) 
        ids.dex_state_ptr.n_zero_notes = int(global_dex_state["n_zero_notes"])


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

func _write_zero_note_to_output{pedersen_ptr: HashBuiltin*, zero_note_output_ptr: ZeroOutput*}(
    index: felt
) {
    alloc_locals;

    let output: ZeroOutput* = zero_note_output_ptr;

    assert output.index = index;

    let zero_note_output_ptr = zero_note_output_ptr + ZeroOutput.SIZE;

    return ();
}

// * Positions * //
func write_position_info_to_output{
    position_output_ptr: PerpPositionOutput*, pedersen_ptr: HashBuiltin*
}(position: PerpPosition) {
    alloc_locals;

    let output: PerpPositionOutput* = position_output_ptr;

    // & | index (32 bits) | synthetic_token (32 bits) | position_size (64 bits) | order_side (8 bits) | allow_partial_liquidations (8 bit)
    assert output.batched_position_info_slot1 = (
        ((position.index * 2 ** 32) + position.synthetic_token) * 2 ** 32 + position.position_size
    ) * 2 ** 16 + position.order_side * 2 ** 8 + position.allow_partial_liquidations;

    // & | entry_price (64 bits) | liquidation_price (64 bits) | last_funding_idx (32 bits)
    assert output.batched_position_info_slot2 = (
        ((position.entry_price * 2 ** 64) + position.liquidation_price) * 2 ** 32 +
        position.last_funding_idx
    );
    assert output.public_key = position.position_address;

    let position_output_ptr = position_output_ptr + PerpPositionOutput.SIZE;

    return ();
}

func write_empty_position_to_output{empty_position_output_ptr: ZeroOutput*}(position_idx: felt) {
    alloc_locals;

    let output: ZeroOutput* = empty_position_output_ptr;

    assert output.index = position_idx;

    let empty_position_output_ptr = empty_position_output_ptr + ZeroOutput.SIZE;

    return ();
}

// * Order Tabs * //
func write_order_tab_info_to_output{
    order_tab_output_ptr: OrderTabOutput*, pedersen_ptr: HashBuiltin*
}(order_tab: OrderTab*) {
    alloc_locals;

    let output: OrderTabOutput* = order_tab_output_ptr;

    let tab_header: TabHeader* = &order_tab.tab_header;

    let (base_trimed_blinding: felt) = bitwise_and(tab_header.base_blinding, BIT_64_AMOUNT);
    let (base_hidden_amount: felt) = bitwise_xor(order_tab.base_amount, base_trimed_blinding);
    let (quote_trimed_blinding: felt) = bitwise_and(tab_header.quote_blinding, BIT_64_AMOUNT);
    let (quote_hidden_amount: felt) = bitwise_xor(order_tab.quote_amount, quote_trimed_blinding);

    // & format: | index (32 bits) | base_token (32 bits) | quote_token (32 bits) | base hidden amount (64 bits)
    // &          | quote hidden amount (64 bits) |  is_smart_contract (8 bits) | is_perp (8 bits) |
    let o1 = ((tab_header.index * 2 ** 32) + tab_header.base_token * 2 ** 32) +
        tab_header.quote_token;
    let o2 = ((o1 * 2 ** 32) + base_hidden_amount * 2 ** 64) + quote_hidden_amount;
    assert output.batched_tab_info_slot1 = (o2 * 2 ** 64) + is_smart_contract * 2 ** 8 + is_perp;

    let (base_commitment: felt) = hash2{hash_ptr=pedersen_ptr}(
        order_tab.base_amount, tab_header.base_blinding
    );
    let (quote_commitment: felt) = hash2{hash_ptr=pedersen_ptr}(
        order_tab.quote_amount, tab_header.quote_blinding
    );

    assert output.base_commitment = base_commitment;
    assert output.quote_commitment = quote_commitment;
    assert output.public_key = tab_header.pub_key;

    let order_tab_output_ptr = order_tab_output_ptr + OrderTabOutput.SIZE;

    return ();
}

func write_empty_tab_to_output{empty_order_tabs_output_ptr: ZeroOutput*}(tab_idx: felt) {
    alloc_locals;

    let output: ZeroOutput* = empty_order_tabs_output_ptr;

    assert output.index = tab_idx;

    let empty_order_tabs_output_ptr = empty_order_tabs_output_ptr + ZeroOutput.SIZE;

    return ();
}
