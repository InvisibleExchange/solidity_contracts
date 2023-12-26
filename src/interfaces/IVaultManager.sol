// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IVaultManager {
    function isVaultRegistered(
        address tokenAddress
    ) external view returns (bool);

    function isTokenRegistered(uint32 tokenId) external view returns (bool);

    function getTokenAddress(uint32 tokenId) external view returns (address);

    function scaleUp(
        uint64 amount,
        uint32 tokenId
    ) external view returns (uint256);

    function scaleDown(
        uint256 amount,
        uint32 tokenId
    ) external view returns (uint64);

    function executeEscape(
        address tokenAddress,
        address payable recipient,
        uint256 escapeAmount
    ) external;
}
