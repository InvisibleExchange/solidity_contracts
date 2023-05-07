use num_bigint::{BigInt, BigUint, Sign};
use num_integer::Integer;
use num_traits::{FromPrimitive, ToPrimitive};

use crate::{perpetual::OrderSide, transaction_batch::tx_batch_structs::GlobalDexState};

const DEPOSIT_OUTPUT_SIZE: usize = 2;
const WITHDRAW_OUTPUT_SIZE: usize = 2;
const NOTE_OUTPUT_SIZE: usize = 3;
const POSITION_OUTPUT_SIZE: usize = 3;
const ZERO_OUTPUT_SIZE: usize = 1;

#[derive(Debug, Clone)]
pub struct ProgramOutput {
    pub dex_state: GlobalDexState,
    pub deposit_outputs: Vec<DepositOutput>,
    pub withdrawal_outputs: Vec<WithdrawalOutput>,
    pub position_outputs: Vec<PerpPositionOutput>,
    pub empty_position_idxs: Vec<u64>,
    pub note_output: Vec<NoteOutput>,
    pub zero_note_idxs: Vec<u64>,
}

pub fn parse_cairo_output(raw_program_output: Vec<&str>) -> ProgramOutput {
    // & cairo_output structure:
    // 0: dex_state
    // 1: deposits
    // 2: withdrawals
    // 3: positions
    // 4: empty positions
    // 5: notes
    // 6: zero notes

    let cairo_output = preprocess_cairo_output(raw_program_output);

    // ? Parse dex state
    let dex_state: GlobalDexState = parse_dex_state(&cairo_output[0..14]);

    // ? Parse deposits
    let cairo_output = &cairo_output[14..];
    let deposit_outputs = parse_deposit_outputs(cairo_output, dex_state.n_deposits);

    // ? Parse withdrawals
    let cairo_output = &cairo_output[(dex_state.n_deposits as usize * DEPOSIT_OUTPUT_SIZE)..];
    let withdrawal_outputs = parse_withdrawal_outputs(&cairo_output, dex_state.n_withdrawals);

    // ? Parse positions
    let cairo_output = &cairo_output[(dex_state.n_withdrawals as usize * WITHDRAW_OUTPUT_SIZE)..];
    let position_outputs = parse_position_outputs(cairo_output, dex_state.n_output_positions);

    // ? Parse empty_positions
    let cairo_output =
        &cairo_output[(dex_state.n_output_positions as usize * POSITION_OUTPUT_SIZE)..];
    let empty_position_idxs = parse_zero_indexes(cairo_output, dex_state.n_empty_positions);

    // ? Parse notes
    let cairo_output = &cairo_output[(dex_state.n_empty_positions as usize * ZERO_OUTPUT_SIZE)..];
    let note_output = parse_note_outputs(cairo_output, dex_state.n_output_notes);

    // ? Parse zero notes
    let cairo_output = &cairo_output[(dex_state.n_output_notes as usize * NOTE_OUTPUT_SIZE)..];
    let zero_note_idxs = parse_zero_indexes(cairo_output, dex_state.n_zero_notes);

    let program_output = ProgramOutput {
        dex_state,
        deposit_outputs,
        withdrawal_outputs,
        position_outputs,
        empty_position_idxs,
        note_output,
        zero_note_idxs,
    };

    return program_output;
}

// * =====================================================================================

fn parse_dex_state(output: &[BigUint]) -> GlobalDexState {
    assert!(output.len() == 14);

    let config_code = output[0].to_u64().unwrap();
    let init_state_root = &output[1];
    let final_state_root = &output[2];
    let init_perp_state_root = &output[3];
    let final_perp_state_root = &output[4];
    let state_tree_depth = output[5].to_u32().unwrap();
    let perp_tree_depth = output[6].to_u32().unwrap();
    let global_expiration_timestamp = output[7].to_u32().unwrap();
    let n_deposits = output[8].to_u32().unwrap();
    let n_withdrawals = output[9].to_u32().unwrap();
    let n_output_positions = output[10].to_u32().unwrap();
    let n_empty_positions = output[11].to_u32().unwrap();
    let n_output_notes = output[12].to_u32().unwrap();
    let n_zero_notes = output[13].to_u32().unwrap();

    GlobalDexState::new(
        config_code,
        &init_state_root,
        &final_state_root,
        &init_perp_state_root,
        &final_perp_state_root,
        state_tree_depth,
        perp_tree_depth,
        global_expiration_timestamp,
        n_output_notes,
        n_zero_notes,
        n_output_positions,
        n_empty_positions,
        n_deposits,
        n_withdrawals,
    )
}

// * =====================================================================================

#[derive(Debug, Clone)]
pub struct DepositOutput {
    pub token: u64,
    pub amount: u64,
    pub deposit_pub_key: BigUint,
}

fn parse_deposit_outputs(output: &[BigUint], num_deposits: u32) -> Vec<DepositOutput> {
    // output is offset by 12 (dex state)

    let mut deposits: Vec<DepositOutput> = Vec::new();

    for i in 0..num_deposits {
        let batch_deposit_info = output[(i * 2) as usize].clone();

        let split_num = split_by_bytes(&batch_deposit_info, vec![64, 64, 64]);

        let amount = split_num[0];
        let token = split_num[1];

        let deposit_pub_key = output[(i * 2 + 1) as usize].clone();

        let deposit = DepositOutput {
            token,
            amount,
            deposit_pub_key,
        };

        deposits.push(deposit);
    }

    return deposits;
}

// * =====================================================================================

#[derive(Debug, Clone)]
pub struct WithdrawalOutput {
    pub token: u64,
    pub amount: u64,
    pub withdrawal_address: BigUint,
}

fn parse_withdrawal_outputs(output: &[BigUint], num_wthdrawals: u32) -> Vec<WithdrawalOutput> {
    // output is offset by 12 (dex state)

    let mut withdrawals: Vec<WithdrawalOutput> = Vec::new();

    for i in 0..num_wthdrawals {
        let batch_withdrawal_info = output[(i * 2) as usize].clone();

        let split_vec = split_by_bytes(&batch_withdrawal_info, vec![64, 64, 64]);

        let amount = split_vec[0];
        let token = split_vec[1];

        let withdrawal_address = output[(i * 2 + 1) as usize].clone();

        let withdrawal = WithdrawalOutput {
            token,
            amount,
            withdrawal_address,
        };

        withdrawals.push(withdrawal);
    }

    return withdrawals;
}

// * =====================================================================================

#[derive(Debug, Clone)]
pub struct PerpPositionOutput {
    pub synthetic_token: u64,
    pub position_size: u64,
    pub order_side: OrderSide,
    pub entry_price: u64,
    pub liquidation_price: u64,
    pub last_funding_idx: u64,
    pub index: u64,
    pub public_key: BigUint,
}

fn parse_position_outputs(output: &[BigUint], num_positions: u32) -> Vec<PerpPositionOutput> {
    let mut positions: Vec<PerpPositionOutput> = Vec::new();

    for i in 0..num_positions {
        let batched_position_info_slot1 = output[(i * 3) as usize].clone();
        let batched_position_info_slot2 = output[(i * 3) as usize].clone();

        // & format: | index (64 bits) | synthetic_token (64 bits) | position_size (64 bits) | order_side (8 bit) |
        // & format: | entry_price (64 bits) | liquidation_price (64 bits) | last_funding_idx (32 bits) |
        // & format: | public key <-> position_address (251 bits) |

        let split_vec_slot1 = split_by_bytes(&batched_position_info_slot1, vec![64, 64, 64, 8]);
        let split_vec_slot2 = split_by_bytes(&batched_position_info_slot2, vec![64, 64, 32, 64]);

        let order_side = if split_vec_slot1[0] == 0 {
            OrderSide::Long
        } else {
            OrderSide::Short
        };
        let position_size = split_vec_slot1[1];
        let synthetic_token = split_vec_slot1[2];
        let index = split_vec_slot1[3];
        let last_funding_idx = split_vec_slot2[0];
        let liquidation_price = split_vec_slot2[1];
        let entry_price = split_vec_slot2[2];

        let public_key = output[(i * 3 + 2) as usize].clone();

        let position = PerpPositionOutput {
            synthetic_token,
            position_size,
            order_side,
            entry_price,
            liquidation_price,
            last_funding_idx,
            index,
            public_key,
        };

        positions.push(position);
    }

    return positions;
}

#[derive(Debug, Clone)]
pub struct NoteOutput {
    pub index: u64,
    pub token: u64,
    pub hidden_amount: u64,
    pub commitment: BigUint,
    pub address: BigUint,
}

fn parse_note_outputs(output: &[BigUint], num_notes: u32) -> Vec<NoteOutput> {
    // output is offset by 12 (dex state)

    let mut notes: Vec<NoteOutput> = Vec::new();

    for i in 0..num_notes {
        let batched_note_info = output[(i * 3) as usize].clone();

        // & batched_note_info format: | token (64 bits) | hidden amount (64 bits) | idx (64 bits) |

        let split_vec = split_by_bytes(&batched_note_info, vec![64, 64, 64]);
        let index = split_vec[0];
        let hidden_amount = split_vec[1];
        let token = split_vec[2];

        let commitment = output[(i * 3 + 1) as usize].clone();
        let address = output[(i * 3 + 2) as usize].clone();

        let note = NoteOutput {
            index,
            token,
            hidden_amount,
            commitment,
            address,
        };

        notes.push(note);
    }

    return notes;
}

fn parse_zero_indexes(output: &[BigUint], num_zero_idxs: u32) -> Vec<u64> {
    let slice: Vec<BigUint> = output[0..num_zero_idxs as usize].try_into().unwrap();
    let zero_idxs = slice
        .iter()
        .map(|x| x.to_u64().unwrap())
        .collect::<Vec<u64>>();
    return zero_idxs;
}

// * =====================================================================================

fn preprocess_cairo_output(program_output: Vec<&str>) -> Vec<BigUint> {
    let p: BigInt =
        BigInt::from_u64(2).unwrap().pow(251) + 17 * BigInt::from_u64(2).unwrap().pow(192) + 1;

    let arr2 = program_output
        .iter()
        .map(|x| BigInt::parse_bytes(x.as_bytes(), 10).unwrap())
        .collect::<Vec<BigInt>>();

    let arr = arr2
        .iter()
        .map(|x| {
            let num = if x.sign() == Sign::Minus {
                p.clone() + x
            } else {
                x.clone()
            };

            num.to_biguint().unwrap()
        })
        .collect::<Vec<BigUint>>();

    return arr;
}

fn split_by_bytes(num: &BigUint, bit_lenghts: Vec<u8>) -> Vec<u64> {
    // & returns a vector of values split by the bit_lenghts in revers order

    let mut peaces: Vec<u64> = Vec::new();
    let mut num = num.clone();
    for i in (0..bit_lenghts.len()).rev() {
        let (q, r) = num.div_mod_floor(&BigUint::from(2u128.pow(bit_lenghts[i] as u32)));
        peaces.push(r.to_u64().unwrap());
        num = q;
    }

    return peaces;
}
