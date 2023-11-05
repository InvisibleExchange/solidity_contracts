// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IVaultManager.sol";
import "./IInteractions.sol";

import "../helpers/parseProgramOutput.sol";

interface IPedersenHash is IVaultManager, IInteractions {
    function updateStateAfterTxBatch(uint256[] calldata programOutput) external;

    function relayAccumulatedHashes(
        uint64 txBatchId,
        AccumulatedHashesOutput[] memory accumulatedHashOutputs
    ) external;
}
