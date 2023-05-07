%builtins output pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import unsigned_div_rem, assert_le

from perpetuals.prices.prices import PriceRange, get_price_ranges, validate_price_in_range

func main{output_ptr, pedersen_ptr: HashBuiltin*, range_check_ptr, ecdsa_ptr: SignatureBuiltin*}() {
    alloc_locals;

    let (price_ranges: PriceRange*) = get_price_ranges();

    %{
        print("min btc price: ", memory[ids.price_ranges.address_ + 0])
        print("max btc price: ", memory[ids.price_ranges.address_ + 1])
        print("min eth price: ", memory[ids.price_ranges.address_ + 2])
        print("max eth price: ", memory[ids.price_ranges.address_ + 3])
    %}

    // validate_price_in_range{price_ranges=price_ranges}(1301, 0);
    // validate_price_in_range{price_ranges=price_ranges}(30020, 1);

    // validate_price_in_range{price_ranges=price_ranges}(1001, 0);
    // validate_price_in_range{price_ranges=price_ranges}(33020, 1);

    %{ print("OK") %}

    return ();
}
