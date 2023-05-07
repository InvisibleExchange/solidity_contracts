// // ? Parse Perp Positions
// // Todo: Might not need to parse positions to save gas (this can be done by anyone who wants to).
// let (positions_len, positions: PerpPositionOutput*) = parse_positions_array(
//     program_output, dex_state.n_withdrawals
// );
// let program_output_len = program_output_len - dex_state.n_output_positions * PerpPositionOutput.SIZE;
// let program_output = &program_output[dex_state.n_output_positions * PerpPositionOutput.SIZE];
// // ? Parse empty position indexes
// let (empty_pos_idxs_len: felt, empty_pos_idxs: felt*) = parse_empty_outputs(
//     program_output, dex_state.n_empty_positions
// );
// // ? Parse Notes
// // Todo: Might not need to parse notes to save gas (this can be done by anyone who wants to).
// let (notes_len, notes: NoteDiffOutput*) = parse_note_output_array(
//     program_output, dex_state.n_output_notes
// );
// // ? Parse zero note indexes
// let (zero_note_idxs_len: felt, zero_note_idxs: felt*) = parse_empty_outputs(
//     program_output, dex_state.n_zero_notes
// );

func parse_note_output_array(program_output: felt*, n_notes: felt) -> (
    notes_len: felt, notes: NoteDiffOutput*
) {
    alloc_locals;

    let (local empty_arr: NoteDiffOutput*) = alloc();

    let (notes_len: felt, notes: NoteDiffOutput*) = _build_notes_array(
        program_output, n_notes, 0, empty_arr
    );

    return (notes_len, notes);
}

func _build_notes_array(
    program_output: felt*, n_notes: felt, notes_len: felt, notes: NoteDiffOutput*
) -> (notes_len: felt, notes: NoteDiffOutput*) {
    if (n_notes == notes_len) {
        return (notes_len, notes);
    }

    let position_info = NoteDiffOutput(
        batched_note_info=program_output[0], address=program_output[1], commitment=program_output[2]
    );

    assert notes[notes_len] = position_info;

    return _build_notes_array(&program_output[3], n_notes, notes_len + 1, notes);
}

// ------------------------------------------------------------------------------

func parse_positions_array(program_output: felt*, n_positions: felt) -> (
    positions_len: felt, positions: PerpPositionOutput*
) {
    alloc_locals;

    let (local empty_arr: PerpPositionOutput*) = alloc();

    let (positions_len: felt, positions: PerpPositionOutput*) = _build_positions_array(
        program_output, n_positions, 0, empty_arr
    );

    return (positions_len, positions);
}

func _build_positions_array(
    program_output: felt*, n_positions: felt, positions_len: felt, positions: PerpPositionOutput*
) -> (positions_len: felt, positions: PerpPositionOutput*) {
    if (n_positions == positions_len) {
        return (positions_len, positions);
    }

    let position_info = PerpPositionOutput(
        batched_position_info_slot1=program_output[0],
        batched_position_info_slot2=program_output[1],
        public_key=program_output[2],
    );

    assert positions[positions_len] = position_info;

    return _build_positions_array(&program_output[3], n_positions, positions_len + 1, positions);
}

// ------------------------------------------------------------------------------

func parse_empty_outputs(program_output: felt*, n_zero_idxs: felt) -> (
    indexes_len: felt, indexes: felt*
) {
    alloc_locals;

    let (local empty_arr: felt*) = alloc();

    let (indexes_len: felt, indexes: felt*) = _build_zero_indexes_arr(
        program_output, n_zero_idxs, 0, empty_arr
    );

    return (indexes_len, indexes);
}

func _build_zero_indexes_arr(
    program_output: felt*, n_zero_idxs: felt, indexes_len: felt, indexes: felt*
) -> (indexes_len: felt, indexes: felt*) {
    if (n_zero_idxs == indexes_len) {
        return (indexes_len, indexes);
    }

    assert indexes[indexes_len] = program_output[0];

    return _build_zero_indexes_arr(&program_output[1], n_zero_idxs, indexes_len + 1, indexes);
}

// ------------------------------------------------------------------------------
