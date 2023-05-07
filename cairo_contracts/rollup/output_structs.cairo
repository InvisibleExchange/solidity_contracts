from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import split_felt
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
    // & batched_note_info format: | token (64 bits) | hidden amount (64 bits) | idx (64 bits) |
    batched_note_info: felt,
    commitment: felt,
    address: felt,
}

// Represents the struct of data written to the program output for each Deposit.
struct DepositTransactionOutput {
    // & batched_note_info format: | deposit_id (64 bits) | token (64 bits) | amount (64 bits) |
    batched_deposit_info: felt,
    stark_key: felt,
}

// Represents the struct of data written to the program output for each Withdrawal.
struct WithdrawalTransactionOutput {
    // & batched_note_info format: | token (64 bits) | amount (64 bits) |
    batched_withdraw_info: felt,
    withdraw_address: felt,  // This should be the eth address to withdraw from
}

// Represents the struct of data written to the program output for each perpetual position Modifictaion.
struct PerpPositionOutput {
    // & format: | index (64 bits) | synthetic_token (64 bits) | position_size (64 bits) | order_side (8 bit) |
    // & format: | entry_price (64 bits) | liquidation_price (64 bits) | last_funding_idx (32 bits) |  |
    // & format: | public key <-> position_address (251 bits) |
    batched_position_info_slot1: felt,
    batched_position_info_slot2: felt,
    public_key: felt,
}

// This is used to output the index of the note/position that has been spent/closed
// The class is only defined for clarity we could just use a felt instead
struct ZeroOutput {
    // & format: | index (64 bits) |
    index: felt,
}

// =======================================================

func write_new_note_to_output{
    pedersen_ptr: HashBuiltin*, bitwise_ptr: BitwiseBuiltin*, note_output_ptr: NoteDiffOutput*
}(note: Note) {
    alloc_locals;

    let output: NoteDiffOutput* = note_output_ptr;

    let (trimed_blinding: felt) = bitwise_and(note.blinding_factor, BIT_64_AMOUNT);
    let (hidden_amount: felt) = bitwise_xor(note.amount, trimed_blinding);
    assert output.batched_note_info = ((note.token * 2 ** 64) + hidden_amount) * 2 ** 64 +
        note.index;
    let (comm: felt) = hash2{hash_ptr=pedersen_ptr}(note.amount, note.blinding_factor);
    assert output.commitment = comm;
    assert output.address = note.address.x;

    let note_output_ptr = note_output_ptr + NoteDiffOutput.SIZE;

    return ();
}

func write_zero_note_to_output{pedersen_ptr: HashBuiltin*, zero_note_output_ptr: ZeroOutput*}(
    index: felt
) {
    alloc_locals;

    let output: ZeroOutput* = zero_note_output_ptr;

    assert output.index = index;

    let zero_note_output_ptr = zero_note_output_ptr + ZeroOutput.SIZE;

    return ();
}

func write_note_dict_to_output{
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    note_output_ptr: NoteDiffOutput*,
    zero_note_output_ptr: ZeroOutput*,
}(note_dict_start: DictAccess*, n_output_notes: felt) {
    alloc_locals;

    if (n_output_notes == 0) {
        return ();
    }

    let idx: felt = note_dict_start.key;
    let note_hash: felt = note_dict_start.new_value;

    if (note_hash == 0) {
        write_zero_note_to_output(idx);

        let note_dict_ptr = note_dict_start + DictAccess.SIZE;
        return write_note_dict_to_output(note_dict_ptr, n_output_notes - 1);
    }

    local note: Note;
    %{
        note_ = output_notes[ids.idx]

        memory[ids.note.address_ + ADDRESS_OFFSET + 0 ] = int(note_["address"]["x"]) 
        memory[ids.note.address_ + ADDRESS_OFFSET + 1 ] = int(note_["address"]["y"]) 
        memory[ids.note.address_ + TOKEN_OFFSET] = int(note_["token"])
        memory[ids.note.address_ + AMOUNT_OFFSET] = int(note_["amount"])
        memory[ids.note.address_ + BLINDING_FACTOR_OFFSET] = int(note_["blinding"])
        memory[ids.note.address_ + INDEX_OFFSET] = int(note_["index"])
        memory[ids.note.address_ + HASH_OFFSET] = int(note_["hash"])
    %}

    let (hash: felt) = hash_note(note);

    %{
        #     if ids.note_hash != ids.hash:
        #         print("ERROR: index is : ", ids.idx)
        #         print("ERROR: note hash is : ", ids.note_hash)
        #         print("ERROR: note hash should be : ", ids.hash)
        #         print("ERROR: note is : ", note_)
        #
    %}

    assert note_hash = hash;

    write_new_note_to_output(note);

    let note_dict_ptr = note_dict_start + DictAccess.SIZE;
    return write_note_dict_to_output(note_dict_ptr, n_output_notes - 1);
}

// =======================================================

func write_deposit_info_to_output{
    pedersen_ptr: HashBuiltin*, deposit_output_ptr: DepositTransactionOutput*
}(deposit: Deposit) {
    alloc_locals;

    let output: DepositTransactionOutput* = deposit_output_ptr;

    assert output.batched_deposit_info = ((deposit.deposit_id * 2 ** 64) + deposit.token) * 2 **
        64 + deposit.amount;
    assert output.stark_key = deposit.deposit_address;

    let deposit_output_ptr = deposit_output_ptr + DepositTransactionOutput.SIZE;

    return ();
}

func write_withdrawal_info_to_output{
    pedersen_ptr: HashBuiltin*, withdraw_output_ptr: WithdrawalTransactionOutput*, range_check_ptr
}(withdrawal: Withdrawal) {
    alloc_locals;

    let output: WithdrawalTransactionOutput* = withdraw_output_ptr;

    assert output.batched_withdraw_info = (withdrawal.token) * 2 ** 64 + withdrawal.amount;
    assert output.withdraw_address = withdrawal.withdrawal_address;

    let withdraw_output_ptr = withdraw_output_ptr + WithdrawalTransactionOutput.SIZE;

    return ();
}

// =======================================================

func write_position_info_to_output{
    position_output_ptr: PerpPositionOutput*, pedersen_ptr: HashBuiltin*
}(position: PerpPosition) {
    alloc_locals;

    let output: PerpPositionOutput* = position_output_ptr;

    assert output.batched_position_info_slot1 = (
        ((position.index * 2 ** 64) + position.synthetic_token) * 2 ** 64 + position.position_size
    ) * 2 ** 8 + position.order_side;

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
    %}

    verify_position_hash(position);
    assert position.hash = position_hash;

    write_position_info_to_output(position);

    let position_dict_ptr = position_dict_start + DictAccess.SIZE;
    return write_position_dict_to_output(position_dict_ptr, n_output_positions - 1);
}

// * INIT OUTPUT STRUCTS =================================

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

        print("global_config_output_ptr", global_config_output_ptr)

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
            print(global_config_output_ptr + counter + i)
            memory[global_config_output_ptr + counter + i] = int(observers[i])
    %}

    return ();
}
