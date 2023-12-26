// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IPedersenHash {
    function hash(
        bytes memory input
    ) external view returns (uint256[] memory output);
}
