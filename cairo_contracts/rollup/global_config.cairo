from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin, BitwiseBuiltin

// Structures:
// - assets: [token1, token2, ...]
// - observers : [observer1, observer2, ...]
// - leverage_bounds_per_asset: [token1, value11, value12, token2, value21, value22 ...]
// - everything else: [token1, value1, token2, value2, ...]

struct GlobalDexState {
    config_code: felt,  // why do we need this? (rename)
    init_state_root: felt,
    final_state_root: felt,
    state_tree_depth: felt,
    global_expiration_timestamp: felt,
    n_deposits: felt,
    n_withdrawals: felt,
    n_output_notes: felt,
    n_empty_notes: felt,
    n_output_positions: felt,
    n_empty_positions: felt,
    n_output_tabs: felt,
    n_empty_tabs: felt,
}

struct GlobalConfig {
    dex_state: GlobalDexState,
    assets_len: felt,
    assets: felt*,
    chain_ids_len: felt,
    chain_ids: felt*,
    collateral_token: felt,
    decimals_per_asset: felt*,
    price_decimals_per_asset: felt*,
    leverage_decimals: felt,
    leverage_bounds_per_asset: felt*,
    dust_amount_per_asset: felt*,
    observers_len: felt,
    observers: felt*,
    min_partial_liquidation_size: felt*,
}

func get_array_index_for_token{range_check_ptr, global_config: GlobalConfig*}(token: felt) -> (
    idx: felt
) {
    alloc_locals;

    let assets_len = global_config.assets_len;
    let assets = global_config.assets;

    if (token == global_config.collateral_token) {
        return (assets_len,);
    }

    let (idx: felt) = _get_array_index_for_token_internal(assets_len, assets, token, 0);

    return (idx,);
}

func _get_array_index_for_token_internal{range_check_ptr}(
    assets_len: felt, assets: felt*, token: felt, idx: felt
) -> (idx: felt) {
    if (token == assets[0]) {
        return (idx,);
    }

    // TODO: THIS CAN BE DONE WITH A HINT

    return _get_array_index_for_token_internal(assets_len - 1, &assets[1], token, idx + 1);
}

// get the observer pub key from the observer index
func get_observer_by_index{range_check_ptr, global_config: GlobalConfig*}(observer_idx: felt) -> (
    res: felt
) {
    return (global_config.observers[observer_idx],);
}

// Get token decimals
func token_decimals{range_check_ptr, global_config: GlobalConfig*}(token: felt) -> (res: felt) {
    let (token_idx) = get_array_index_for_token(token);

    let decimals_per_asset = global_config.decimals_per_asset;

    assert token = decimals_per_asset[2 * token_idx];

    let decimals = decimals_per_asset[2 * token_idx + 1];

    return (decimals,);
}

// Get token price decimals
func price_decimals{range_check_ptr, global_config: GlobalConfig*}(token: felt) -> (res: felt) {
    let (token_idx) = get_array_index_for_token(token);

    let price_decimals_per_asset = global_config.price_decimals_per_asset;

    assert token = price_decimals_per_asset[2 * token_idx];

    let decimals = price_decimals_per_asset[2 * token_idx + 1];

    return (decimals,);
}

// Get dust amount for a token
func get_dust_amount{range_check_ptr, global_config: GlobalConfig*}(token: felt) -> (res: felt) {
    let (token_idx) = get_array_index_for_token(token);

    let dust_amount_per_asset = global_config.dust_amount_per_asset;
    assert token = dust_amount_per_asset[2 * token_idx];
    let dust_amount = dust_amount_per_asset[2 * token_idx + 1];

    return (dust_amount,);
}

// Get min partial liquidation size for a token
func get_min_partial_liquidation_size{range_check_ptr, global_config: GlobalConfig*}(
    token: felt
) -> (res: felt) {
    let (token_idx) = get_array_index_for_token(token);

    let min_partial_liquidation_size = global_config.min_partial_liquidation_size;
    assert token = min_partial_liquidation_size[2 * token_idx];
    let size = min_partial_liquidation_size[2 * token_idx + 1];

    return (size,);
}

// Verify the chain id exists
func verify_valid_chain_id{range_check_ptr, global_config: GlobalConfig*}(chain_id: felt) {
    let is_valid = _verify_valid_chain_id_inner(
        global_config.chain_ids_len, global_config.chain_ids, chain_id
    );

    assert is_valid = 1;

    return ();
}

func _verify_valid_chain_id_inner{range_check_ptr}(
    chain_ids_len: felt, chain_ids: felt*, chain_id: felt
) -> felt {
    if (chain_ids_len == 0) {
        return 0;
    }

    if (chain_id == chain_ids[0]) {
        return 1;
    }

    return _verify_valid_chain_id_inner(chain_ids_len - 1, &chain_ids[1], chain_id);
}

// * ==============================================================

func init_global_config(global_config_ptr: GlobalConfig*) {
    %{
        # // * DEX STATE FIEELDS
        dex_state = program_input["global_dex_state"]
        program_input_counts = dex_state["program_input_counts"]
        dex_state_addr = ids.global_config_ptr.address_ + ids.GlobalConfig.dex_state
        memory[dex_state_addr + ids.GlobalDexState.config_code] = int(dex_state["config_code"])
        memory[dex_state_addr + ids.GlobalDexState.init_state_root] = int(dex_state["init_state_root"])
        memory[dex_state_addr + ids.GlobalDexState.final_state_root] = int(dex_state["final_state_root"])
        memory[dex_state_addr + ids.GlobalDexState.state_tree_depth] = dex_state["state_tree_depth"]
        memory[dex_state_addr + ids.GlobalDexState.global_expiration_timestamp] = dex_state["global_expiration_timestamp"]
        memory[dex_state_addr + ids.GlobalDexState.n_deposits] = program_input_counts["n_deposits"]
        memory[dex_state_addr + ids.GlobalDexState.n_withdrawals] = program_input_counts["n_withdrawals"]
        memory[dex_state_addr + ids.GlobalDexState.n_output_notes] = program_input_counts["n_output_notes"]
        memory[dex_state_addr + ids.GlobalDexState.n_empty_notes] = program_input_counts["n_empty_notes"]
        memory[dex_state_addr + ids.GlobalDexState.n_output_positions] = program_input_counts["n_output_positions"]
        memory[dex_state_addr + ids.GlobalDexState.n_empty_positions] = program_input_counts["n_empty_positions"]
        memory[dex_state_addr + ids.GlobalDexState.n_output_tabs] = program_input_counts["n_output_tabs"]
        memory[dex_state_addr + ids.GlobalDexState.n_empty_tabs] = program_input_counts["n_empty_tabs"]

        # // * GLOBAL CONFIG FIELDS
        global_config = program_input["global_config"]

        memory[ids.global_config_ptr.address_ + LEVERAGE_DECIMALS_OFFSET] = global_config["leverage_decimals"]
        memory[ids.global_config_ptr.address_ + COLLATERAL_TOKEN_OFFSET] = global_config["collateral_token"]
        # Assets
        assets = global_config["assets"]
        memory[ids.global_config_ptr.address_ + ASSETS_LEN_OFFSET] = len(assets)
        memory[ids.global_config_ptr.address_ + ASSETS_OFFSET] = assets_ = segments.add()
        for i in range(len(assets)):
            memory[assets_ + i] = int(assets[i])
         # Chain IDs
        chain_ids = global_config["chain_ids"]
        memory[ids.global_config_ptr.address_ + CHAIN_IDS_LEN_OFFSET] = len(chain_ids)
        memory[ids.global_config_ptr.address_ + CHAIN_IDS_OFFSET] = chain_ids_ = segments.add()
        for i in range(len(chain_ids)):
            memory[chain_ids_ + i] = int(chain_ids[i])
        # Decimals per asset
        decimals_per_asset = global_config["decimals_per_asset"]
        memory[ids.global_config_ptr.address_ + DECIMALS_PER_ASSET_OFFSET] = decimals1 = segments.add()
        for i in range(0, len(decimals_per_asset), 2):
            memory[decimals1 + i] = int(decimals_per_asset[i])
            memory[decimals1 + i + 1] = int(decimals_per_asset[i+1])
        # Price decimals per asset
        price_decimals_per_asset = global_config["price_decimals_per_asset"]
        memory[ids.global_config_ptr.address_ + PRICE_DECIMALS_PER_ASSET_OFFSET] = decimals2 = segments.add()
        for i in range(0, len(price_decimals_per_asset), 2):
            memory[decimals2 + i] = int(price_decimals_per_asset[i])
            memory[decimals2 + i + 1] = int(price_decimals_per_asset[i+1])
        #  Leverage bounds per asset
        leverage_bounds_per_asset = global_config["leverage_bounds_per_asset"]
        memory[ids.global_config_ptr.address_ + LEVERAGE_BOUNDS_PER_ASSET_OFFSET] = decimals3 = segments.add()
        for i in range(0, len(leverage_bounds_per_asset), 3):
            memory[decimals3 + i] = int(leverage_bounds_per_asset[i])
            memory[decimals3 + i + 1] = int(leverage_bounds_per_asset[i+1] * 100)
            memory[decimals3 + i + 2] = int(leverage_bounds_per_asset[i+2] * 100)
        # Dust amount per asset
        dust_amount_per_asset = global_config["dust_amount_per_asset"]
        memory[ids.global_config_ptr.address_ + DUST_AMOUNT_PER_ASSET_OFFSET] = amounts_ = segments.add()
        for i in range(0, len(dust_amount_per_asset), 2):
            memory[amounts_ + i] = int(dust_amount_per_asset[i])
            memory[amounts_ + i + 1] = int(dust_amount_per_asset[i+1])
        # observers
        observers = global_config["observers"]
        memory[ids.global_config_ptr.address_ + OBSERVERS_LEN_OFFSET] = len(observers)
        memory[ids.global_config_ptr.address_ + OBSERVERS_OFFSET] = observers_ = segments.add()
        for i in range(len(observers)):
            memory[observers_ + i] = int(observers[i])
        # min partial liquidation size 
        min_partial_liquidation_sizes = global_config["min_partial_liquidation_sizes"]
        memory[ids.global_config_ptr.address_ + MIN_PARTIAL_LIQUIDATION_SIZE_OFFSET] = min_pl_size = segments.add()
        for i in range(0, len(min_partial_liquidation_sizes), 2):
            memory[min_pl_size + i] = int(min_partial_liquidation_sizes[i])
            memory[min_pl_size + i + 1] = int(min_partial_liquidation_sizes[i+1])
    %}

    return ();
}

// * ===============================================================

// & depth_and_exipration_time: | state_tree_depth (8 bits) | global_expiration_timestamp (32 bits) |
// & output_counts: | n_deposits (32 bits) | n_withdrawals (32 bits) | n_output_positions (32 bits) | n_empty_positions (32 bits) |
// &                | n_output_notes (32 bits) | n_empty_notes (32 bits) | n_output_tabs (32 bits) | n_empty_tabs (32 bits) |

func init_output_structs{pedersen_ptr: HashBuiltin*}(
    config_output_ptr: felt*, global_config: GlobalConfig*
) -> (config_output_ptr: felt*) {
    let dex_state: GlobalDexState = global_config.dex_state;

    assert config_output_ptr[0] = dex_state.init_state_root;
    assert config_output_ptr[1] = dex_state.final_state_root;

    // & 1: | state_tree_depth (8 bits) | global_expiration_timestamp (32 bits) | config_code (128 bits) |
    let batched_info = (
        (dex_state.state_tree_depth * 2 ** 32) + dex_state.global_expiration_timestamp
    ) * 2 ** 128 + dex_state.config_code;
    assert config_output_ptr[2] = batched_info;

    // & 2: | n_deposits (32 bits) | n_withdrawals (32 bits) | n_output_positions (32 bits) | n_empty_positions (32 bits) |
    // &    | n_output_notes (32 bits) | n_empty_notes (32 bits) | n_output_tabs (32 bits) | n_empty_tabs (32 bits) |
    let batched_info = (
        (
            (
                (
                    (
                        ((dex_state.n_deposits * 2 ** 32) + dex_state.n_withdrawals) * 2 ** 32 +
                        dex_state.n_output_positions
                    ) * 2 ** 32 +
                    dex_state.n_empty_positions
                ) * 2 ** 32 +
                dex_state.n_output_notes
            ) * 2 ** 32 +
            dex_state.n_empty_notes
        ) * 2 ** 32 +
        dex_state.n_output_tabs
    ) * 2 ** 32 + dex_state.n_empty_tabs;
    assert config_output_ptr[3] = batched_info;

    // * Global Config =========================================================================

    // & 1: | collateral_token (64 bits) | leverage_decimals (8 bits) | assets_len (32 bits) | observers_len (32 bits) |
    let batched_info = (
        ((global_config.collateral_token * 2 ** 8) + global_config.leverage_decimals) * 2 ** 32 +
        global_config.assets_len
    ) * 2 ** 32 + global_config.observers_len;
    assert config_output_ptr[4] = batched_info;

    // ? assets
    let (config_output_ptr: felt*) = output_batched_arr(
        global_config.assets_len, global_config.assets, config_output_ptr + 5
    );
    // ? Chain IDs
    let (config_output_ptr: felt*) = output_batched_arr(
        global_config.chain_ids_len, global_config.chain_ids, config_output_ptr
    );
    // ? observers
    let (config_output_ptr: felt*) = output_batched_arr(
        global_config.observers_len, global_config.observers, config_output_ptr
    );

    // ? decimals_per_asset
    let (config_output_ptr: felt*) = output_batched_arr(
        2 * (global_config.assets_len + 1), global_config.decimals_per_asset, config_output_ptr
    );
    // ? price_decimals_per_asset
    let (config_output_ptr: felt*) = output_batched_arr(
        2 * global_config.assets_len, global_config.price_decimals_per_asset, config_output_ptr
    );
    // ? min_partial_liquidation_size
    let (config_output_ptr: felt*) = output_batched_arr(
        2 * global_config.assets_len, global_config.min_partial_liquidation_size, config_output_ptr
    );
    // ? dust_amount_per_asset
    let (config_output_ptr: felt*) = output_batched_arr(
        2 * (global_config.assets_len + 1), global_config.dust_amount_per_asset, config_output_ptr
    );

    // ? leverage_bounds_per_asset
    let (config_output_ptr: felt*) = output_batched_arr(
        3 * global_config.assets_len, global_config.leverage_bounds_per_asset, config_output_ptr
    );

    assert config_output_ptr[
        0
    ] = 100000000000000000000000000000000000000000000000000000000000000000000;
    assert config_output_ptr[
        1
    ] = 100000000000000000000000000000000000000000000000000000000000000000000;

    return (config_output_ptr + 2,);
}

func output_batched_arr(arr_len: felt, arr: felt*, config_output_ptr: felt*) -> (
    config_output_ptr: felt*
) {
    if (arr_len == 0) {
        return (config_output_ptr,);
    }

    if (arr_len == 1) {
        assert config_output_ptr[0] = arr[0];
        let config_output_ptr = config_output_ptr + 1;

        return (config_output_ptr,);
    }
    if (arr_len == 2) {
        let batched_info = (arr[0] * 2 ** 64) + arr[1];

        assert config_output_ptr[0] = batched_info;
        let config_output_ptr = config_output_ptr + 1;

        return (config_output_ptr,);
    }
    if (arr_len == 3) {
        let batched_info = ((arr[0] * 2 ** 64) + arr[1]) * 2 ** 64 + arr[2];

        assert config_output_ptr[0] = batched_info;
        let config_output_ptr = config_output_ptr + 1;

        return (config_output_ptr,);
    } else {
        let batched_info = ((arr[0] * 2 ** 64) + arr[1]) * 2 ** 64 + arr[2];

        assert config_output_ptr[0] = batched_info;
        let config_output_ptr = config_output_ptr + 1;

        return output_batched_arr(arr_len - 3, &arr[3], config_output_ptr);
    }
}
