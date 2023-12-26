// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract VaultManagerStorage {
    // * VAULT MANAGER ----------------------------------------

    event VaultRegisteredEvent(address tokenAddress);

    address public escapeVerifier;
    address payable public s_gasFeeCollector;
    mapping(address => bool) s_vaults; // maps token address to vault

    address[] public addresses;

    uint64 chainId;

    // * TOKEN INFO -------------------------------------------

    event NewTokenRegisteredEvent(
        address tokenAddress,
        uint32 tokenId,
        uint8 scaleFactor
    );

    uint32 public constant ETH_ID = 453755560;
    uint32 constant MIN_TOKEN_ID = 100_000;

    mapping(uint32 => bool) public s_tokenIdIsRegistered;
    mapping(address => uint32) public s_tokenAddress2Id;
    mapping(uint32 => address) public s_tokenId2Address;
    mapping(uint32 => uint8) public s_tokenId2ScaleFactor;

    mapping(address => address) public s_clAggregators; // tokenAddress => ChainLink Aggregator Address
}
