// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../core/L1/EscapeVerifier.sol";

interface IEscapeVerifier {
    function updatePendingEscapes(EscapeOutput[] memory escapeOutputs) external;

    function updatePendingPositionEscapes(
        PositionEscapeOutput[] memory escapeOutputs
    ) external;
}
