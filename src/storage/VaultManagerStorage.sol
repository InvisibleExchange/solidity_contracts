// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract VaultManagerStorage {
    // * VAULT MANAGER ----------------------------------------

    event VaultRegisteredEvent(address tokenAddress);

    address escapeVerifier;
    address payable s_gasFeeCollector;
    mapping(address => bool) s_vaults; // maps token address to vault

    address[] addresses;

    uint32 chainId;

    // * TOKEN INFO -------------------------------------------

    event NewTokenRegisteredEvent(
        address tokenAddress,
        uint32 tokenId,
        uint8 scaleFactor
    );

    uint32 constant ETH_ID = 453755560;
    uint32 constant MIN_TOKEN_ID = 100_000;

    mapping(uint32 => bool) s_tokenIdIsRegistered;
    mapping(address => uint32) s_tokenAddress2Id;
    mapping(uint32 => address) s_tokenId2Address;
    mapping(uint32 => uint8) s_tokenId2ScaleFactor;

    mapping(address => address) s_clAggregators; // tokenAddress => ChainLink Aggregator Address
}
