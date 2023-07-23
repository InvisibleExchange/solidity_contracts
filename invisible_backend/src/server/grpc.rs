pub mod engine {
    tonic::include_proto!("engine");
}

use std::{
    collections::HashMap,
    str::FromStr,
    sync::Arc,
    thread::{JoinHandle, ThreadId},
};

use engine::{Address, GrpcNote, LimitOrderMessage, Signature as GrpcSignature};
use error_stack::{Report, Result};
use num_bigint::{BigInt, BigUint};
use parking_lot::Mutex;
use serde::Serialize;

use crate::{
    order_tab::{OrderTab, TabHeader},
    perpetual::{
        liquidations::{
            liquidation_engine::LiquidationSwap, liquidation_order::LiquidationOrder,
            liquidation_output::LiquidationResponse,
        },
        perp_helpers::perp_swap_outptut::PerpSwapResponse,
        perp_order::{CloseOrderFields, OpenOrderFields, PerpOrder},
        perp_position::PerpPosition,
        perp_swap::PerpSwap,
        OrderSide,
    },
    transaction_batch::tx_batch_structs::OracleUpdate,
    transactions::{
        deposit::Deposit,
        limit_order::{LimitOrder, SpotNotesInfo},
        swap::{Swap, SwapResponse},
        withdrawal::Withdrawal,
    },
    utils::crypto_utils::{EcPoint, Signature},
    utils::{
        errors::{GrpcMessageError, PerpSwapExecutionError, TransactionExecutionError},
        notes::Note,
    },
};

use self::engine::{
    DepositMessage, GrpcCloseOrderFields, GrpcOpenOrderFields, GrpcOracleUpdate, GrpcOrderTab,
    GrpcPerpPosition, GrpcTabHeader, LiquidationOrderMessage, MarginChangeReq, PerpOrderMessage,
    SpotNotesInfoMessage, WithdrawalMessage,
};

// * TRANSACTION ENGINE ======================================================================

// ------ DEPOSITS -------------------------------------------

impl TryFrom<DepositMessage> for Deposit {
    type Error = Report<GrpcMessageError>;

    fn try_from(req: DepositMessage) -> Result<Self, GrpcMessageError> {
        let mut notes: Vec<Note> = Vec::new();
        for n in req.notes.iter() {
            let note = Note::try_from(n.clone())?;

            notes.push(note);
        }

        let deposit = Deposit {
            transaction_type: "deposit".to_string(),
            deposit_id: req.deposit_id,
            deposit_token: req.deposit_token,
            deposit_amount: req.deposit_amount,
            notes,
            signature: Signature::try_from(req.signature.ok_or(GrpcMessageError {})?)?,
            stark_key: BigUint::from_str(&req.stark_key)
                .ok()
                .ok_or(GrpcMessageError {})?,
        };

        Ok(deposit)
    }
}

// ------ SPOT SWAPS -------------------------------------------

impl TryFrom<LimitOrderMessage> for LimitOrder {
    type Error = Report<GrpcMessageError>;

    fn try_from(req: LimitOrderMessage) -> Result<Self, GrpcMessageError> {
        let spot_note_info: Option<SpotNotesInfo> = if req.spot_note_info.is_some() {
            let notes_info =
                SpotNotesInfo::try_from(req.spot_note_info.ok_or(GrpcMessageError {})?)?;
            Some(notes_info)
        } else {
            None
        };

        let order_tab = if req.order_tab.is_some() {
            let tab = OrderTab::try_from(req.order_tab.ok_or(GrpcMessageError {})?)?;
            Some(Arc::new(Mutex::new(tab)))
        } else {
            None
        };

        let limit_order = LimitOrder::new(
            0,
            req.expiration_timestamp,
            req.token_spent,
            req.token_received,
            req.amount_spent,
            req.amount_received,
            req.fee_limit,
            spot_note_info,
            order_tab,
        );

        Ok(limit_order)
    }
}

impl TryFrom<SpotNotesInfoMessage> for SpotNotesInfo {
    type Error = Report<GrpcMessageError>;

    fn try_from(req: SpotNotesInfoMessage) -> Result<Self, GrpcMessageError> {
        let mut notes_in: Vec<Note> = Vec::new();
        for n in req.notes_in.iter() {
            let note = Note::try_from(n.clone())?;

            notes_in.push(note);
        }

        let refund_note: Option<Note>;
        if req.refund_note.is_some() {
            let n = Note::try_from(req.refund_note.ok_or(GrpcMessageError {})?)?;
            refund_note = Some(n);
        } else {
            refund_note = None
        }

        let spot_notes_info = SpotNotesInfo {
            dest_received_address: EcPoint::try_from(
                req.dest_received_address.ok_or(GrpcMessageError {})?,
            )?,
            dest_received_blinding: BigUint::from_str(req.dest_received_blinding.as_str())
                .ok()
                .ok_or(GrpcMessageError {})?,
            notes_in,
            refund_note,
        };

        Ok(spot_notes_info)
    }
}

impl TryFrom<GrpcOrderTab> for OrderTab {
    type Error = Report<GrpcMessageError>;

    fn try_from(req: GrpcOrderTab) -> Result<Self, GrpcMessageError> {
        let tab_header = TabHeader::try_from(req.tab_header.ok_or(GrpcMessageError {})?)?;
        let position = if req.position.is_some() {
            Some(PerpPosition::try_from(
                req.position.ok_or(GrpcMessageError {})?,
            )?)
        } else {
            None
        };
        let order_tab = OrderTab::new(
            tab_header,
            req.base_token,
            req.quote_token,
            req.base_amount,
            req.quote_amount,
            position,
        );

        Ok(order_tab)
    }
}

impl TryFrom<GrpcTabHeader> for TabHeader {
    type Error = Report<GrpcMessageError>;

    fn try_from(req: GrpcTabHeader) -> Result<Self, GrpcMessageError> {
        let header = TabHeader::new(
            req.expiration_timestamp,
            req.is_perp,
            req.is_smart_contract,
            BigUint::from_str(&req.pub_key).unwrap_or_default(),
        );

        Ok(header)
    }
}

impl From<OrderTab> for GrpcOrderTab {
    fn from(req: OrderTab) -> Self {
        let header = GrpcTabHeader {
            expiration_timestamp: req.tab_header.expiration_timestamp,
            is_perp: req.tab_header.is_perp,
            is_smart_contract: req.tab_header.is_smart_contract,
            pub_key: req.tab_header.pub_key.to_string(),
        };

        let order_tab = GrpcOrderTab {
            tab_idx: req.tab_idx,
            tab_header: Some(header),
            base_token: req.base_token,
            quote_token: req.quote_token,
            base_amount: req.base_amount,
            quote_amount: req.quote_amount,
            position: None,
        };

        return order_tab;
    }
}

// ------ WITHDRAWALS -------------------------------------------

impl TryFrom<WithdrawalMessage> for Withdrawal {
    type Error = Report<GrpcMessageError>;

    fn try_from(req: WithdrawalMessage) -> Result<Self, GrpcMessageError> {
        let mut notes_in: Vec<Note> = Vec::new();
        for n in req.notes_in.iter() {
            let note = Note::try_from(n.clone())?;

            notes_in.push(note);
        }

        let refund_note: Option<Note>;
        if req.refund_note.is_some() {
            let n = Note::try_from(req.refund_note.ok_or(GrpcMessageError {})?)?;
            refund_note = Some(n);
        } else {
            refund_note = None
        }

        let withdrawal = Withdrawal {
            transaction_type: "withdrawal".to_string(),
            withdrawal_chain_id: req.withdrawal_chain_id,
            withdrawal_token: req.withdrawal_token,
            withdrawal_amount: req.withdrawal_amount,
            notes_in,
            refund_note,
            signature: Signature::try_from(req.signature.ok_or(GrpcMessageError {})?)?,
            stark_key: BigUint::from_str(&req.stark_key).or_else(|e| {
                return Err(Report::new(GrpcMessageError {}).attach_printable(e));
            })?,
        };

        Ok(withdrawal)
    }
}

// ------ PERPETUAL SWAPS -------------------------------------------

impl TryFrom<PerpOrderMessage> for PerpOrder {
    type Error = Report<GrpcMessageError>;

    fn try_from(req: PerpOrderMessage) -> Result<Self, GrpcMessageError> {
        let result: PerpOrder;
        match req.position_effect_type {
            0 => {
                let open_order_fields =
                    OpenOrderFields::try_from(req.open_order_fields.ok_or(GrpcMessageError {})?)?;

                result = PerpOrder::new_open_order(
                    0,
                    req.expiration_timestamp,
                    if req.order_side == 1 {
                        OrderSide::Long
                    } else {
                        OrderSide::Short
                    },
                    req.synthetic_token,
                    req.synthetic_amount,
                    req.collateral_amount,
                    req.fee_limit,
                    open_order_fields,
                );
            }
            1 => {
                result = PerpOrder::new_modify_order(
                    0,
                    req.expiration_timestamp,
                    PerpPosition::try_from(req.position.ok_or(GrpcMessageError {})?)?,
                    if req.order_side == 1 {
                        OrderSide::Long
                    } else {
                        OrderSide::Short
                    },
                    req.synthetic_token,
                    req.synthetic_amount,
                    req.collateral_amount,
                    req.fee_limit,
                );
            }
            2 => {
                let close_order_fields =
                    CloseOrderFields::try_from(req.close_order_fields.ok_or(GrpcMessageError {})?)?;

                result = PerpOrder::new_close_order(
                    0,
                    req.expiration_timestamp,
                    PerpPosition::try_from(req.position.ok_or(GrpcMessageError {})?)?,
                    if req.order_side == 1 {
                        OrderSide::Long
                    } else {
                        OrderSide::Short
                    },
                    req.synthetic_token,
                    req.synthetic_amount,
                    req.collateral_amount,
                    req.fee_limit,
                    close_order_fields,
                );
            }
            _ => {
                return Err(Report::new(GrpcMessageError {}).attach("Invalid position effect type"))
            }
        }

        Ok(result)
    }
}

impl TryFrom<GrpcOpenOrderFields> for OpenOrderFields {
    type Error = Report<GrpcMessageError>;

    fn try_from(req: GrpcOpenOrderFields) -> Result<Self, GrpcMessageError> {
        let mut notes_in: Vec<Note> = Vec::new();
        for n in req.notes_in.iter() {
            let note = Note::try_from(n.clone())?;

            notes_in.push(note);
        }

        let refund_note: Option<Note>;
        if req.refund_note.is_some() {
            let n = Note::try_from(req.refund_note.ok_or(GrpcMessageError {})?)?;
            refund_note = Some(n);
        } else {
            refund_note = None
        }

        let fields = OpenOrderFields {
            initial_margin: req.initial_margin,
            collateral_token: req.collateral_token,
            notes_in,
            refund_note,
            position_address: BigUint::from_str(&req.position_address)
                .map_err(|_| GrpcMessageError {})?,
            allow_partial_liquidations: req.allow_partial_liquidations,
        };

        Ok(fields)
    }
}

impl TryFrom<GrpcCloseOrderFields> for CloseOrderFields {
    type Error = Report<GrpcMessageError>;

    fn try_from(req: GrpcCloseOrderFields) -> Result<Self, GrpcMessageError> {
        let fields = CloseOrderFields {
            dest_received_address: EcPoint::try_from(
                req.dest_received_address.ok_or(GrpcMessageError {})?,
            )?,
            dest_received_blinding: BigUint::from_str(&req.dest_received_blinding.as_str())
                .ok()
                .ok_or(GrpcMessageError {})?,
        };

        Ok(fields)
    }
}

// LIQUIDATION ORDER

impl TryFrom<LiquidationOrderMessage> for LiquidationOrder {
    type Error = Report<GrpcMessageError>;

    fn try_from(req: LiquidationOrderMessage) -> Result<Self, GrpcMessageError> {
        let open_order_fields =
            OpenOrderFields::try_from(req.open_order_fields.ok_or(GrpcMessageError {})?)?;
        let position = PerpPosition::try_from(req.position.ok_or(GrpcMessageError {})?)?;

        let result = LiquidationOrder::new(
            position,
            if req.order_side == 1 {
                OrderSide::Long
            } else {
                OrderSide::Short
            },
            req.synthetic_token,
            req.synthetic_amount,
            req.collateral_amount,
            open_order_fields,
        );

        return Ok(result);
    }
}

// ————————————————————————————————————————————————————————————————————————————————————————————————————————

// POSITIONS

impl From<PerpPosition> for GrpcPerpPosition {
    fn from(req: PerpPosition) -> Self {
        GrpcPerpPosition {
            order_side: if req.order_side == OrderSide::Long {
                1
            } else {
                0
            },
            position_size: req.position_size,
            synthetic_token: req.synthetic_token,
            collateral_token: req.collateral_token,
            margin: req.margin,
            entry_price: req.entry_price,
            liquidation_price: req.liquidation_price,
            bankruptcy_price: req.bankruptcy_price,
            allow_partial_liquidations: req.allow_partial_liquidations,
            position_address: BigUint::from_str(&req.position_address.to_string())
                .unwrap_or_default()
                .to_string(),
            last_funding_idx: req.last_funding_idx,
            index: req.index,
            hash: req.hash.to_string(),
        }
    }
}

impl TryFrom<GrpcPerpPosition> for PerpPosition {
    type Error = Report<GrpcMessageError>;

    fn try_from(req: GrpcPerpPosition) -> Result<Self, GrpcMessageError> {
        let order_side = if req.order_side == 1 {
            OrderSide::Long
        } else {
            OrderSide::Short
        };
        let position_address =
            BigUint::from_str(&req.position_address).map_err(|_| GrpcMessageError {})?;

        // let hash = _hash_position(
        //     &order_side,
        //     req.synthetic_token,
        //     req.position_size,
        //     req.entry_price,
        //     req.liquidation_price,
        //     &position_address,
        //     req.last_funding_idx,
        // );

        let position = PerpPosition {
            order_side,
            position_size: req.position_size,
            synthetic_token: req.synthetic_token,
            collateral_token: req.collateral_token,
            margin: req.margin,
            entry_price: req.entry_price,
            liquidation_price: req.liquidation_price,
            bankruptcy_price: req.bankruptcy_price,
            allow_partial_liquidations: req.allow_partial_liquidations,
            position_address,
            last_funding_idx: req.last_funding_idx,
            index: req.index,
            hash: BigUint::from_str(&req.hash).map_err(|_| GrpcMessageError {})?,
        };

        Ok(position)
    }
}

// ————————————————————————————————————————————————————————————————————————————————————————————————————————

// ActiveOrders

// ————————————————————————————————————————————————————————————————————————————————————————————————————————

// ------ UTILS -------------------------------------------

impl TryFrom<Address> for EcPoint {
    type Error = Report<GrpcMessageError>;

    fn try_from(req: Address) -> Result<Self, GrpcMessageError> {
        let point = EcPoint {
            x: BigInt::from_str(req.x.as_str())
                .ok()
                .ok_or(GrpcMessageError {})?,
            y: BigInt::from_str(req.y.as_str())
                .ok()
                .ok_or(GrpcMessageError {})?,
        };

        Ok(point)
    }
}

impl TryFrom<GrpcNote> for Note {
    type Error = Report<GrpcMessageError>;

    fn try_from(req: GrpcNote) -> Result<Self, GrpcMessageError> {
        let note = Note::new(
            req.index,
            EcPoint::try_from(req.address.ok_or(GrpcMessageError {})?)?,
            req.token,
            req.amount,
            BigUint::from_str(req.blinding.as_str())
                .ok()
                .ok_or(GrpcMessageError {})?,
        );

        Ok(note)
    }
}

impl TryFrom<GrpcSignature> for Signature {
    type Error = Report<GrpcMessageError>;

    fn try_from(req: GrpcSignature) -> Result<Self, GrpcMessageError> {
        let sig = Signature {
            r: req.r.to_string(),
            s: req.s.to_string(),
        };

        Ok(sig)
    }
}

// —————————————————————————————————————

impl From<Note> for GrpcNote {
    fn from(req: Note) -> Self {
        GrpcNote {
            index: req.index,
            address: Some(Address {
                x: req.address.x.to_str_radix(10),
                y: req.address.y.to_str_radix(10),
            }),
            token: req.token,
            amount: req.amount,
            blinding: req.blinding.to_str_radix(10),
        }
    }
}

impl From<EcPoint> for Address {
    fn from(req: EcPoint) -> Self {
        Address {
            x: req.x.to_string(),
            y: req.y.to_string(),
        }
    }
}

// ...........................

impl TryFrom<MarginChangeReq> for ChangeMarginMessage {
    type Error = Report<GrpcMessageError>;

    fn try_from(req: MarginChangeReq) -> Result<Self, GrpcMessageError> {
        // position
        if req.position.is_none() {
            return Err(Report::new(GrpcMessageError {}));
        }
        let position = PerpPosition::try_from(req.position.ok_or(GrpcMessageError {})?)?;

        // signature
        if req.signature.is_none() {
            return Err(Report::new(GrpcMessageError {}));
        }
        let sig = Signature::try_from(req.signature.ok_or(GrpcMessageError {})?)?;

        // notes and close order fields
        let notes_in: Option<Vec<Note>>;
        let refund_note: Option<Note>;
        let close_order_fields: Option<CloseOrderFields>;
        if req.margin_change >= 0 {
            let mut notes_in_: Vec<Note> = Vec::new();
            for n in req.notes_in.iter() {
                let note = Note::try_from(n.clone())?;

                if position.collateral_token != note.token {
                    return Err(Report::new(GrpcMessageError {}));
                }

                notes_in_.push(note);
            }
            if req.refund_note.is_none() {
                refund_note = None;
            } else {
                let ref_note = Note::try_from(req.refund_note.ok_or(GrpcMessageError {})?)?;

                if position.collateral_token != ref_note.token {
                    return Err(Report::new(GrpcMessageError {}));
                }

                refund_note = Some(ref_note);
            }

            notes_in = Some(notes_in_);
            close_order_fields = None;
        } else {
            if req.close_order_fields.is_none() {
                return Err(Report::new(GrpcMessageError {}));
            } else {
                let close_order_fields_ =
                    CloseOrderFields::try_from(req.close_order_fields.ok_or(GrpcMessageError {})?)?;
                close_order_fields = Some(close_order_fields_);
            }

            notes_in = None;
            refund_note = None;
        }

        Ok(ChangeMarginMessage {
            margin_change: req.margin_change,
            notes_in,
            refund_note,
            close_order_fields,
            position,
            signature: sig,
            user_id: req.user_id,
        })
    }
}

// ...........................

impl TryFrom<GrpcOracleUpdate> for OracleUpdate {
    type Error = Report<GrpcMessageError>;

    fn try_from(req: GrpcOracleUpdate) -> Result<Self, GrpcMessageError> {
        let mut signatures: Vec<Signature> = Vec::new();
        for s in req.signatures.iter() {
            let sig = Signature::try_from(s.clone())?;

            signatures.push(sig);
        }

        let point = OracleUpdate {
            token: req.token,
            timestamp: req.timestamp,
            observer_ids: req.observer_ids,
            prices: req.prices,
            signatures,
        };

        Ok(point)
    }
}

// ————————————————————————————————————————————————————————————————————————————————————————————————————————

#[derive(Debug, Default)]
pub struct GrpcTxResponse {
    pub tx_handle: Option<
        JoinHandle<Result<(Option<SwapResponse>, Option<Vec<u64>>), TransactionExecutionError>>,
    >,
    pub perp_tx_handle: Option<JoinHandle<Result<PerpSwapResponse, PerpSwapExecutionError>>>,
    pub liquidation_tx_handle:
        Option<JoinHandle<Result<LiquidationResponse, PerpSwapExecutionError>>>,
    pub margin_change_response: Option<(Option<MarginChangeResponse>, String)>, //
    pub new_idxs: Option<std::result::Result<Vec<u64>, String>>, // For deposit orders
    pub funding_info: Option<(HashMap<u64, Vec<i64>>, HashMap<u64, Vec<u64>>)>,
    pub successful: bool,
}

impl GrpcTxResponse {
    pub fn new(successful: bool) -> GrpcTxResponse {
        GrpcTxResponse {
            successful,
            ..Default::default()
        }
    }
}

// * CONTROL ENGINE ======================================================================

#[derive(Debug)]
pub struct MarginChangeResponse {
    pub new_note_idx: u64,
    pub position: PerpPosition,
    // pub position_address: String,
    // pub position_idx: u64,
    // pub synthetic_token: u64,
    // pub order_side: OrderSide,
    // pub liquidation_price: u64,
}

pub enum ControlActionType {
    FinalizeBatch,
}

pub struct GrpcControlMessage {
    pub control_action: ControlActionType,
}

// * ===================================================================================

pub enum MessageType {
    DepositMessage,
    SwapMessage,
    WithdrawalMessage,
    PerpSwapMessage,
    LiquidationMessage,
    SplitNotes,
    MarginChange,
    Rollback,
    FundingUpdate,
    IndexPriceUpdate,
    Undefined,
    FinalizeBatch,
}

impl Default for MessageType {
    fn default() -> MessageType {
        MessageType::Undefined
    }
}

#[derive(Default)]
pub struct GrpcMessage {
    pub msg_type: MessageType,
    pub deposit_message: Option<Deposit>,
    pub swap_message: Option<Swap>,
    pub withdrawal_message: Option<Withdrawal>,
    pub perp_swap_message: Option<PerpSwap>,
    pub liquidation_message: Option<LiquidationSwap>,
    pub split_notes_message: Option<(Vec<Note>, Note, Option<Note>)>,
    pub change_margin_message: Option<ChangeMarginMessage>,
    pub rollback_info_message: Option<(ThreadId, RollbackMessage)>,
    pub funding_update_message: Option<FundingUpdateMessage>,
    pub price_update_message: Option<Vec<OracleUpdate>>,
}

impl GrpcMessage {
    pub fn new() -> Self {
        GrpcMessage::default()
    }
}

#[derive(Clone)]
pub struct RollbackMessage {
    pub tx_type: String,
    pub notes_in_a: (u64, Option<Vec<Note>>),
    pub notes_in_b: (u64, Option<Vec<Note>>),
}

#[derive(Clone)]
pub struct FundingUpdateMessage {
    pub impact_prices: HashMap<u64, (u64, u64)>,
}

#[derive(Clone, Debug, Serialize)]
pub struct ChangeMarginMessage {
    pub margin_change: i64,
    pub notes_in: Option<Vec<Note>>,
    pub refund_note: Option<Note>,
    pub close_order_fields: Option<CloseOrderFields>,
    pub position: PerpPosition,
    pub signature: Signature,
    pub user_id: u64,
}
