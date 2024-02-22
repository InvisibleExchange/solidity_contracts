// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

abstract contract MainStorage {
    uint32 public s_txBatchId;

    mapping(uint32 => uint256) public s_txBatchId2StateRoot;
    mapping(uint32 => uint256) public s_txBatchId2Timestamp;

    mapping(uint32 => bool) s_accumulatedHashesRelayed; // txBatchId => wasRelayed

    event TxBatchProcesssed(
        uint32 indexed txBatchId,
        uint256 prevStateRoot,
        uint256 newStateRoot,
        uint256 timestamp
    );

    address s_L1MessageRelay; // The contract that passes messages from the L1 contract
    address s_escapeVerifier; // The contract that verifies the escape proofs

    uint256 constant INIT_STATE_ROOT =
        2450644354998405982022115704618884006901283874365176806194200773707121413423;

    uint256 public version;
}
