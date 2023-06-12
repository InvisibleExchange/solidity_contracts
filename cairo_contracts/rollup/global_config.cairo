// Structures:
// - assets: [token1, token2, ...]
// - observers : [observer1, observer2, ...]
// - leverage_bounds_per_asset: [token1, value11, value12, token2, value21, value22 ...]
// - everything else: [token1, value1, token2, value2, ...]

struct GlobalConfig {
    assets_len: felt,
    assets: felt*,
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

func init_global_config(global_config_ptr: GlobalConfig*) {
    %{
        global_config = program_input["global_config"]

        memory[ids.global_config_ptr.address_ + LEVERAGE_DECIMALS_OFFSET] = global_config["leverage_decimals"]
        memory[ids.global_config_ptr.address_ + COLLATERAL_TOKEN_OFFSET] = global_config["collateral_token"]
        # Assets
        assets = global_config["assets"]
        memory[ids.global_config_ptr.address_ + ASSETS_LEN_OFFSET] = len(assets)
        memory[ids.global_config_ptr.address_ + ASSETS_OFFSET] = assets_ = segments.add()
        for i in range(len(assets)):
            memory[assets_ + i] = int(assets[i])
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
