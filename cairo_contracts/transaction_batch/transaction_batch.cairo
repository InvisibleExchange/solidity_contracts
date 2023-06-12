%builtins output pedersen range_check ecdsa bitwise

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin, BitwiseBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.dict import dict_new, dict_write, dict_update, dict_squash, dict_read
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.cairo_secp.bigint import BigInt3, bigint_to_uint256, uint256_to_bigint
from starkware.cairo.common.cairo_secp.ec import EcPoint
from starkware.cairo.common.merkle_multi_update import merkle_multi_update
from starkware.cairo.common.math import unsigned_div_rem, assert_le
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.squash_dict import squash_dict
from starkware.cairo.common.hash_state import (
    hash_init,
    hash_finalize,
    hash_update,
    hash_update_single,
)

from invisible_swaps.swap.invisible_swap import execute_swap
from deposits_withdrawals.deposits.deposit import verify_deposit
from deposits_withdrawals.withdrawals.withdrawal import verify_withdrawal

from perpetuals.funding.funding import set_funding_info, FundingInfo
from perpetuals.prices.prices import PriceRange, get_price_ranges
from perpetuals.perp_swap.perpetual_swap import execute_perpetual_swap
from perpetuals.transaction.change_margin import execute_margin_change

from invisible_swaps.split_notes.split_notes import execute_note_split

from rollup.python_definitions import python_define_utils
from rollup.output_structs import (
    GlobalDexState,
    NoteDiffOutput,
    ZeroOutput,
    WithdrawalTransactionOutput,
    DepositTransactionOutput,
    PerpPositionOutput,
    write_note_dict_to_output,
    write_position_dict_to_output,
    init_output_structs,
)
from rollup.global_config import GlobalConfig, init_global_config

const TREE_DEPTH = 5;

// TODO: Change output_positions and output_notes to point to a value in the program input instead of saving it memory until the write_dict_to_output functions

func main{
    output_ptr,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
}() {
    alloc_locals;

    // GLOBAL VERIABLES
    %{ transaction_input_data = program_input["transactions"] %}

    // Define python hint functions and classes
    python_define_utils();

    // * INITIALIZE DICTIONARIES ******************************************************

    local note_dict: DictAccess*;
    local fee_tracker_dict: DictAccess*;
    local position_dict: DictAccess*;
    %{
        ids.note_dict = segments.add()
        ids.fee_tracker_dict = segments.add()
        ids.position_dict = segments.add()
    %}
    let note_dict_start = note_dict;
    let fee_tracker_dict_start = fee_tracker_dict;
    let position_dict_start = position_dict;

    local global_config: GlobalConfig*;
    %{ ids.global_config = segments.add() %}
    init_global_config(global_config);

    // * SPLIT OUTPUT SECTIONS ******************************************************
    local n_deposits: felt;
    local n_withdrawals: felt;
    local n_output_positions: felt;
    local n_empty_positions: felt;
    local n_output_notes: felt;
    local global_config_len: felt;
    %{
        ids.n_deposits = int(program_input["global_dex_state"]["n_deposits"]) *  ids.DepositTransactionOutput.SIZE
        ids.n_withdrawals = int(program_input["global_dex_state"]["n_withdrawals"]) * ids.WithdrawalTransactionOutput.SIZE
        ids.n_output_positions = int(program_input["global_dex_state"]["n_output_positions"]) * ids.PerpPositionOutput.SIZE
        ids.n_empty_positions = int(program_input["global_dex_state"]["n_empty_positions"])  * ids.ZeroOutput.SIZE
        ids.n_output_notes = int(program_input["global_dex_state"]["n_output_notes"]) * ids.NoteDiffOutput.SIZE

        assets_len = len(program_input["global_config"]["assets"])
        observers_len = len(program_input["global_config"]["observers"])

        ids.global_config_len =  8 + 10 * assets_len + observers_len
    %}

    local dex_state_ptr: GlobalDexState* = cast(output_ptr, GlobalDexState*);
    local deposit_output_ptr: DepositTransactionOutput* = cast(
        output_ptr + GlobalDexState.SIZE + global_config_len, DepositTransactionOutput*
    );
    local withdraw_output_ptr: WithdrawalTransactionOutput* = cast(
        deposit_output_ptr + n_deposits, WithdrawalTransactionOutput*
    );
    local position_output_ptr: PerpPositionOutput* = cast(
        withdraw_output_ptr + n_withdrawals, PerpPositionOutput*
    );
    // indexes of positions to be removed
    local empty_position_output_ptr: ZeroOutput* = cast(
        position_output_ptr + n_output_positions, ZeroOutput*
    );
    local note_output_ptr: NoteDiffOutput* = cast(
        empty_position_output_ptr + n_empty_positions, NoteDiffOutput*
    );
    // indexes of notes to be removed
    local zero_note_output_ptr: ZeroOutput* = cast(note_output_ptr + n_output_notes, ZeroOutput*);

    // %{
    //     print("dex_state_ptr", ids.dex_state_ptr.address_)
    //     print("deposit_output_ptr", ids.deposit_output_ptr.address_)
    //     print("withdraw_output_ptr", ids.withdraw_output_ptr.address_)
    //     print("position_output_ptr", ids.position_output_ptr.address_)
    //     print("empty_position_output_ptr", ids.empty_position_output_ptr.address_)
    //     print("note_output_ptr", ids.note_output_ptr.address_)
    //     print("zero_note_output_ptr", ids.zero_note_output_ptr.address_)
    // %}

    // Initialize output sections
    init_output_structs(dex_state_ptr);

    // * SET FUNDING INFO AND PRICE RANGES * #

    local funding_info: FundingInfo*;
    %{ ids.funding_info = segments.add() %}
    set_funding_info(funding_info);

    // todo: Use this to verify liquidation prices
    // let (price_ranges: PriceRange*) = get_price_ranges{global_config: global_config}();

    // * EXECUTE TRANSACTION BATCH ================================================

    %{
        import time
        t1_start = time.time()
    %}
    execute_transactions{
        note_dict=note_dict,
        fee_tracker_dict=fee_tracker_dict,
        position_dict=position_dict,
        deposit_output_ptr=deposit_output_ptr,
        withdraw_output_ptr=withdraw_output_ptr,
        empty_position_output_ptr=empty_position_output_ptr,
        zero_note_output_ptr=zero_note_output_ptr,
        funding_info=funding_info,
        global_config=global_config,
    }();
    %{
        t2_end = time.time()
        print("batch execution time total: ", t2_end-t1_start)
    %}

    // * Squash dictionaries =========================================================

    local squashed_note_dict: DictAccess*;
    %{ ids.squashed_note_dict = segments.add() %}
    let (squashed_note_dict_end) = squash_dict(
        dict_accesses=note_dict_start, dict_accesses_end=note_dict, squashed_dict=squashed_note_dict
    );
    local squashed_note_dict_len = (squashed_note_dict_end - squashed_note_dict) / DictAccess.SIZE;

    // ------------------------------------------------------------------------------

    local squashed_position_dict: DictAccess*;
    %{ ids.squashed_position_dict = segments.add() %}
    let (squashed_position_dict_end) = squash_dict(
        dict_accesses=position_dict_start,
        dict_accesses_end=position_dict,
        squashed_dict=squashed_position_dict,
    );
    local squashed_position_dict_len = (squashed_position_dict_end - squashed_position_dict) /
        DictAccess.SIZE;

    // local pos_dict_len = (position_dict - position_dict_start) / DictAccess.SIZE;
    // %{
    //     for i in range(ids.pos_dict_len):
    //         print(memory[ids.position_dict_start.address_ + i*ids.DictAccess.SIZE +0])
    //         print(memory[ids.position_dict_start.address_ + i*ids.DictAccess.SIZE +1])
    //         print(memory[ids.position_dict_start.address_ + i*ids.DictAccess.SIZE +2])
    //         # print("======")
    // %}

    // * VERIFY MERKLE TREE UPDATES ******************************************************

    verify_merkle_tree_updates(
        dex_state_ptr.init_state_root,
        dex_state_ptr.final_state_root,
        dex_state_ptr.init_perp_state_root,
        dex_state_ptr.final_perp_state_root,
        squashed_note_dict,
        squashed_note_dict_len,
        squashed_position_dict,
        squashed_position_dict_len,
        dex_state_ptr.state_tree_depth,
        dex_state_ptr.perp_tree_depth,
    );

    // * WRITE NEW NOTES AND POSITIONS TO THE PROGRAM OUTPUT ******************************

    write_note_dict_to_output{
        pedersen_ptr=pedersen_ptr,
        bitwise_ptr=bitwise_ptr,
        note_output_ptr=note_output_ptr,
        zero_note_output_ptr=zero_note_output_ptr,
    }(squashed_note_dict, squashed_note_dict_len);

    write_position_dict_to_output{
        pedersen_ptr=pedersen_ptr,
        position_output_ptr=position_output_ptr,
        empty_position_output_ptr=empty_position_output_ptr,
    }(squashed_position_dict, squashed_position_dict_len);

    // local note_dict_len = (note_dict - note_dict_start) / DictAccess.SIZE;
    // %{
    //     for i in range(ids.squashed_note_dict_len):
    //         print(memory[ids.squashed_note_dict.address_ + i*ids.DictAccess.SIZE +0])
    //         # print(memory[ids.squashed_note_dict.address_ + i*ids.DictAccess.SIZE +1])
    //         print(memory[ids.squashed_note_dict.address_ + i*ids.DictAccess.SIZE +2])
    //         # print("======")

    // print("======")
    // %}
    // // local pos_dict_len = (position_dict - position_dict_start) / DictAccess.SIZE;
    // %{
    //     for i in range(ids.squashed_position_dict_len):
    //         print(memory[ids.squashed_position_dict.address_ + i*ids.DictAccess.SIZE +0])
    //         # print(memory[ids.squashed_position_dict.address_ + i*ids.DictAccess.SIZE +1])
    //         print(memory[ids.squashed_position_dict.address_ + i*ids.DictAccess.SIZE +2])
    //         # print("======")
    // %}

    // update the output ptr to point to the end of the program output
    local output_ptr: felt = cast(zero_note_output_ptr, felt);

    %{ print("all good") %}

    return ();
}

func execute_transactions{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    note_dict: DictAccess*,
    fee_tracker_dict: DictAccess*,
    position_dict: DictAccess*,
    deposit_output_ptr: DepositTransactionOutput*,
    withdraw_output_ptr: WithdrawalTransactionOutput*,
    empty_position_output_ptr: ZeroOutput*,
    zero_note_output_ptr: ZeroOutput*,
    funding_info: FundingInfo*,
    global_config: GlobalConfig*,
}() {
    alloc_locals;

    if (nondet %{ len(transaction_input_data) == 0 %} != 0) {
        return ();
    }

    %{
        current_transaction = transaction_input_data.pop(0) 
        tx_type = current_transaction["transaction_type"]
    %}

    if (nondet %{ tx_type == "swap" %} != 0) {
        %{ current_swap = current_transaction %}

        %{ t1_note_split = time.time() %}
        execute_swap();
        %{
            t2_note_split = time.time()
            print("spot swap time: ", t2_note_split - t1_note_split)
        %}

        return execute_transactions();
    }

    if (nondet %{ tx_type == "deposit" %} != 0) {
        %{ current_deposit = current_transaction["deposit"] %}

        verify_deposit();

        return execute_transactions();
    }

    if (nondet %{ tx_type == "withdrawal" %} != 0) {
        %{ current_withdrawal = current_transaction["withdrawal"] %}

        verify_withdrawal();

        return execute_transactions();
    }

    if (nondet %{ tx_type == "perpetual_swap" %} != 0) {
        %{ current_swap = current_transaction %}

        %{ t1_note_split = time.time() %}
        execute_perpetual_swap();
        %{
            t2_note_split = time.time()
            print("perp swap time: ", t2_note_split - t1_note_split)
        %}

        return execute_transactions();
    }

    if (nondet %{ tx_type == "note_split" %} != 0) {
        %{ current_split_info = current_transaction["note_split"] %}

        %{ t1_note_split = time.time() %}
        execute_note_split();
        %{
            t2_note_split = time.time()
            print("note split time: ", t2_note_split - t1_note_split)
        %}

        return execute_transactions();
    }
    if (nondet %{ tx_type == "margin_change" %} != 0) {
        %{
            current_margin_change_info = current_transaction["margin_change"]
            zero_index = int(current_transaction["zero_idx"])
        %}

        execute_margin_change();

        return execute_transactions();
    } else {
        %{ print("unknown transaction type: ", current_transaction) %}
        return execute_transactions();
    }
}

func verify_merkle_tree_updates{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    prev_root: felt,
    new_root: felt,
    perpetual_prev_root: felt,
    perpetual_new_root: felt,
    squashed_note_dict: DictAccess*,
    squashed_note_dict_len: felt,
    squashed_position_dict: DictAccess*,
    squashed_position_dict_len: felt,
    state_tree_depth: felt,
    perp_tree_depth: felt,
) {
    %{ t1_merkle = time.time() %}
    %{
        preimage = program_input["preimage"]
        preimage = {int(k):[int(x) for x in v] for k,v in preimage.items()}
    %}
    merkle_multi_update{hash_ptr=pedersen_ptr}(
        squashed_note_dict, squashed_note_dict_len, state_tree_depth, prev_root, new_root
    );
    %{
        t2_merkle = time.time()
        print("merkle update time: ", t2_merkle - t1_merkle)
    %}

    %{ t1_merkle = time.time() %}
    %{
        preimage = program_input["perpetual_preimage"]
        preimage = {int(k):[int(x) for x in v] for k,v in preimage.items()}
    %}
    merkle_multi_update{hash_ptr=pedersen_ptr}(
        squashed_position_dict,
        squashed_position_dict_len,
        perp_tree_depth,
        perpetual_prev_root,
        perpetual_new_root,
    );
    %{
        t2_merkle = time.time()
        print("perpetual merkle update time: ", t2_merkle - t1_merkle)
    %}

    return ();
}
