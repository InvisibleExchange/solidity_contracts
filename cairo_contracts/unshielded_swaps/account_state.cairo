from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.hash_state import (
    hash_init,
    hash_finalize,
    hash_update,
    hash_update_single,
)

const ZERO_VAULT_HASH = 3051532127692517571387022095821932649971160144101372951378323654799587621206;

struct AccountSpace {
    public_key: felt,
    token_id: felt,
    balance: felt,
}

struct LimitOrder {
    nonce: felt,
    public_key: felt,
    expiration_timestamp: felt,
    signature_r: felt,
    signature_s: felt,
    token_spent: felt,
    token_received: felt,
    amount_spent: felt,
    amount_received: felt,
    spender_account_index: felt,
    receiver_account_index: felt,
    fee_limit: felt,
}

func limit_order_hash{pedersen_ptr: HashBuiltin*}(limit_order: LimitOrder) -> (hash: felt) {
    alloc_locals;

    // | 90 bits amount_spent | 90 bits amount_received | 32 bits nonce |
    tempvar bundled_amounts = limit_order.amount_spent * 2 ** 122 + limit_order.amount_received * 2 ** 32 + limit_order.nonce;

    // | 75 bits token_spent | 75 bits token_received | 75 bits fee_limit |
    tempvar bundled_tokens = limit_order.token_spent * 2 ** 150 + limit_order.token_received * 2 ** 75 + limit_order.fee_limit;

    // | 90 bits spender_account | 90 bits receiver_account | 32 bits expiration_timestamp |
    tempvar bundled_accounts = limit_order.spender_account_index * 2 ** 122 + limit_order.receiver_account_index * 2 ** 32 + limit_order.expiration_timestamp;

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state_ptr) = hash_init();
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, bundled_amounts);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, bundled_tokens);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, bundled_accounts);
        let (hash) = hash_finalize(hash_state_ptr);
        let pedersen_ptr = hash_ptr;
        return (hash=hash);
    }
}

func account_space_hash{pedersen_ptr: HashBuiltin*}(account_state: AccountSpace) -> (hash: felt) {
    alloc_locals;

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state_ptr) = hash_init();
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, account_state.public_key);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, account_state.token_id);
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, account_state.balance);
        let (hash) = hash_finalize(hash_state_ptr);
        let pedersen_ptr = hash_ptr;
        return (hash=hash);
    }
}

func new_account_space{pedersen_ptr: HashBuiltin*}(
    pub_key: felt, token_id: felt, balance: felt
) -> (acc: AccountSpace) {
    alloc_locals;

    let acc: AccountSpace = AccountSpace(public_key=pub_key, token_id=token_id, balance=balance);

    return (acc,);
}
