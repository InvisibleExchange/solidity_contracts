// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IVaultManager {
    function registerToken(
        address tokenAddress,
        uint32 tokenId,
        uint8 offchainDecimals
    ) external;

    function isVaultRegistered(
        address tokenAddress
    ) external view returns (bool);
}
