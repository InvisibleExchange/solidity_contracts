from starkware.cairo.common.ec_point import EcPoint

from helpers.utils import Note

struct PerpOrder {
    order_id: felt,
    expiration_timestamp: felt,
    position_effect_type: felt,  // 0 = Open, 1 = addMargin, 2 = ReduceSize, 3 = Close
    pos_addr_string: felt,
    order_side: felt,  // 0 for buy, 1 for sell
    synthetic_token: felt,
    synthetic_amount: felt,
    collateral_amount: felt,
    fee_limit: felt,
    hash: felt,
}

struct OpenOrderFields {
    initial_margin: felt,
    collateral_token: felt,
    notes_in_len: felt,
    notes_in: Note*,
    refund_note: Note,
    position_address: felt,
    allow_partial_liquidations: felt,
}

struct CloseOrderFields {
    return_collateral_address: felt,
    return_collateral_blinding: felt,
}

struct PerpPosition {
    order_side: felt,
    synthetic_token: felt,
    collateral_token: felt,
    position_size: felt,
    margin: felt,
    entry_price: felt,
    liquidation_price: felt,
    bankruptcy_price: felt,
    position_address: felt,
    last_funding_idx: felt,
    index: felt,
    hash: felt,
    allow_partial_liquidations: felt,
}
