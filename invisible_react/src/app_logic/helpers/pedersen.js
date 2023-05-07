const starknet_hash_utils = require("starknet/utils/hash");

/* global BigInt */

const pedersen_hash = starknet_hash_utils.pedersen;
const compute_hash_on_elements = starknet_hash_utils.computeHashOnElements;

function pedersen(vec2) {
  return BigInt(pedersen_hash(vec2), 16);
}

function computeHashOnElements(arr) {
  return BigInt(compute_hash_on_elements(arr), 16);
}

module.exports = { pedersen, computeHashOnElements };
