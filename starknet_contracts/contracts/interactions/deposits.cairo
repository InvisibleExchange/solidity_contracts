%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.starknet.common.syscalls import get_block_number, get_block_timestamp
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import (
    assert_not_zero,
    assert_le,
    assert_lt,
    unsigned_div_rem,
    split_felt,
)
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.uint256 import Uint256

from starkware.cairo.common.pow import pow
from starkware.starknet.common.syscalls import get_tx_info, call_contract

from openzeppelin.token.erc20.IERC20 import IERC20

from contracts.interfaces.IAccount import IAccount
from contracts.structs.output_structs import DepositTransactionOutput
from contracts.helpers.parse_program_output import uncompress_deposit_output
from contracts.helpers.token_info import (
    scale_up,
    scale_down,
    get_token_id,
    register_token,
    get_token_address,
    get_token_scale_factor,
)

// TODO: Events should have id for easier indexing

// Event emitted when a deposit is made to the contract
@event
func deposit_event(pub_key: felt, token_id: felt, deposit_amount: felt, timestamp: felt) {
}

// Event emitted when a cancelation is started
@event
func deposit_cancel_event(pub_key: felt, token_address: felt, timestamp: felt) {
}

// Event emitted when a cancelation is refunded
@event
func deposit_cancel_refund_event(
    pub_key: felt, token_address: felt, amount: felt, timestamp: felt
) {
}

@event
func updated_pending_deposits_event(timestamp: felt, tx_batch_id: felt) {
}

// ———————————————————————————————————————————————————————————————————————————

@storage_var
func s_pending_deposit_amount(pub_key: felt, token_id: felt) -> (amount: felt) {
}

// ------ ----- ------ ------ ----- ------

struct DepositCancelation {
    address: felt,
    pub_key: felt,
    token_id: felt,
    timestamp: felt,
}

@storage_var
func s_deposits_cancelations(idx: felt) -> (cancelation: DepositCancelation) {
}

@storage_var
func s_num_deposit_cancelations() -> (num: felt) {
}

// ———————————————————————————————————————————————————————————————————————————
// Updates after tx_batch verification

@external
func update_pending_deposits{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    deposit_outputs_len: felt, deposit_outputs: DepositTransactionOutput*
) {
    _update_pending_deposits_inner(deposit_outputs_len, deposit_outputs);

    cancel_deposits();

    let (timestamp: felt) = get_block_timestamp();

    // todo: tx_batch_id could replace config code
    updated_pending_deposits_event.emit(timestamp, tx_batch_id=1234);

    return ();
}

@external
func _update_pending_deposits_inner{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}(deposit_outputs_len: felt, deposit_outputs: DepositTransactionOutput*) {
    // & reduces the pending deposits by the amount in deposit_outputs[i]
    // & if something is leftover after the update,
    // & it can be withdrawn, if cancel_deposit was called

    if (deposit_outputs_len == 0) {
        return ();
    }

    // ? Uncopress the deposit output
    let (deposit_id, token, amount, deposit_pub_key) = uncompress_deposit_output(
        deposit_outputs[0]
    );

    // ? Get the pending deposit amount
    let (deposit_amount: felt) = s_pending_deposit_amount.read(deposit_pub_key, token);

    // ? Assert that the deposited amount onchain is more than or equal to the deposited amount offchain
    with_attr error_message("Deposit amount is less than the amount deposited offchain") {
        assert_le(amount, deposit_amount);
    }

    // ? reduce the pending deposit amount
    s_pending_deposit_amount.write(
        pub_key=deposit_pub_key, token_id=token, value=deposit_amount - amount
    );

    return update_pending_deposits(deposit_outputs_len - 1, &deposit_outputs[1]);
}

// ———————————————————————————————————————————————————————————————————————————

// TODO: should approve the erc20 before calling deposit and use a multicall to do both at once
@external
func make_deposit{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_address: felt, amount: felt
) -> (deposit_amount: felt) {
    alloc_locals;

    // & This increases the deposited balance for this user and token this transcation batch

    // ? Get the msg_sender
    let (msg_sender: felt) = get_caller_address();
    with_attr error_message("Msg sender is zero") {
        assert_not_zero(msg_sender);
    }

    let pool_address = 1234567890;  // todo: address of the pool that allows for flashloans

    // ? Transfer in amount of ERC20(address) to the pool_contract
    let (amount_high, amount_low) = split_felt(amount);
    let uint256_amount: Uint256 = Uint256(low=amount_low, high=amount_high);

    let (success: felt) = IERC20.transferFrom(
        contract_address=token_address,
        sender=msg_sender,
        recipient=pool_address,
        amount=uint256_amount,
    );
    with_attr error_message("Transfer failed") {
        assert success = 1;
    }

    // ? Get the token id and scale the amount
    let token_id: felt = get_token_id(token_address);
    let deposit_amount_scaled = scale_down(amount, token_id);

    // ? Get the sender's public key and update the pending deposit amount
    let (public_key) = IAccount.getPublicKey(contract_address=msg_sender);

    let (pending_deposit: felt) = s_pending_deposit_amount.read(public_key, token_id);
    s_pending_deposit_amount.write(
        public_key, token_id, value=pending_deposit + deposit_amount_scaled
    );

    // ? Emit the deposit event (This gets caught by the indexer and accepted in the offchain state)
    let (timestamp: felt) = get_block_timestamp();
    deposit_event.emit(public_key, token_id, deposit_amount_scaled, timestamp);

    return (pending_deposit + deposit_amount_scaled,);
}

// ———————————————————————————————————————————————————————————————————————————
// Cancelations

@external
func start_cancel_deposit{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_address: felt
) {
    // & Initiates the cancel deposit process, which will take effect at the next state update,
    // & if the deposit was not used in the offchain state.

    // ? Get the msg_sender and his public key
    let (msg_sender: felt) = get_caller_address();
    assert_not_zero(msg_sender);
    let (public_key) = IAccount.getPublicKey(contract_address=msg_sender);

    let token_id: felt = get_token_id(token_address);

    // ? Get the running cancelation index of this batch
    let (cancelation_idx: felt) = s_num_deposit_cancelations.read();

    // ? Store the cancelation request
    let (timestamp: felt) = get_block_timestamp();
    let cancelation = DepositCancelation(
        address=msg_sender, pub_key=public_key, token_id=token_id, timestamp=timestamp
    );
    s_deposits_cancelations.write(cancelation_idx, value=cancelation);

    // ? Increment the running cancelation count
    s_num_deposit_cancelations.write(cancelation_idx + 1);

    // ? Emit the cancelation event
    deposit_cancel_event.emit(public_key, token_address, timestamp);

    return ();
}

func cancel_deposits{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    // ! Must only be executed after all the pending deposit updates have been executed.

    let (num_cancelations: felt) = s_num_deposit_cancelations.read();

    _cancel_deposits_inner(num_cancelations);

    s_num_deposit_cancelations.write(0);

    return ();
}

// *finsih and test
func _cancel_deposits_inner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    num_cancelations: felt
) {
    alloc_locals;

    if (num_cancelations == 0) {
        return ();
    }

    // ? Does not clear s_deposits_cancelations to save gas, because it isn't necessary
    let (deposit_cancelation: DepositCancelation) = s_deposits_cancelations.read(
        num_cancelations - 1
    );

    // todo: verify the timestamp if needed

    // ? Get the pending deposit amount
    let (pending_deposit: felt) = s_pending_deposit_amount.read(
        deposit_cancelation.pub_key, deposit_cancelation.token_id
    );

    // ? If refund_amount>0 : transfer the pending deposit back to the user
    let cond: felt = is_le(1, pending_deposit);
    if (cond == 1) {
        // Todo: Instead of refunding the deposit allow the user to claim it
        return refund_deposit(pending_deposit, deposit_cancelation);
    } else {
        return ();
    }

    // return ();
}

func refund_deposit{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    pending_deposit: felt, deposit_cancelation: DepositCancelation
) {
    alloc_locals;

    // ? Scale up the amount and convert it back to uint256
    let deposit_amount_scaled = scale_up(pending_deposit, deposit_cancelation.token_id);
    let (high, low) = split_felt(deposit_amount_scaled);
    let uint256_amount: Uint256 = Uint256(low=low, high=high);

    let token_address: felt = get_token_address(deposit_cancelation.token_id);

    // ? Refund the deposit back to the user
    let (success: felt) = IERC20.transfer(
        contract_address=token_address, recipient=deposit_cancelation.address, amount=uint256_amount
    );

    if (success == 1) {
        // ? Set the pending deposit amount to zero
        s_pending_deposit_amount.write(
            deposit_cancelation.pub_key, deposit_cancelation.token_id, value=0
        );

        // ? Emit an event that the deposit was refunded
        // Todo: This is gas intenive and proably unnecessary
        // let (timestamp: felt) = get_block_timestamp();
        // deposit_cancel_refund_event.emit(
        //     deposit_cancelation.pub_key, token_address, deposit_amount_scaled, timestamp
        // );

        return ();
    } else {
        return ();
    }
}

// * VIEW FUNCTIONS * ————————————————————————————————————————————————————————————————————

@view
func get_pending_deposit_amount{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    user_address: felt, token_address: felt
) -> (deposit_amount: felt) {
    alloc_locals;

    assert_not_zero(user_address);

    let (public_key) = IAccount.getPublicKey(contract_address=user_address);

    let token_id: felt = get_token_id(token_address);

    let (deposit_amount: felt) = s_pending_deposit_amount.read(public_key, token_id);

    let deposit_amount_scaled = scale_up(deposit_amount, token_id);

    return (deposit_amount_scaled,);
}

// TOKEN INFO

@external
func register_token_proxy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_address: felt, scale_factor: felt
) -> (token_id: felt) {
    let (token_id: felt) = register_token(token_address, scale_factor);

    return (token_id,);
}

@view
func get_token_id_proxy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_address: felt
) -> (res: felt) {
    let res = get_token_id(token_address);

    return (res,);
}

@view
func get_token_address_proxy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_id: felt
) -> (res: felt) {
    let res = get_token_address(token_id);

    return (res,);
}

@view
func get_token_scale_factor_proxy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_id: felt
) -> (res: felt) {
    let res = get_token_scale_factor(token_id);

    return (res,);
}
