// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IPedersenHash {
    function hash(
        bytes memory input
    ) external view returns (uint256[] memory output);
}
