// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IVaults.sol";

import "../helpers/tokenInfo.sol";
import "../vaults/VaultRegistry.sol";

// Todo: instead of providing the starkKey, we could just provide the initial Ko from the off-chain state

contract MMRegistry is TokenInfo,  VaultRegistry {
    address public owner;

    event newSpotMMRegistration(
        address mmOwner,
        uint32 baseAsset,
        uint32 quoteAsset,
        uint256 tabAddress,
        uint64 maxVlpSupply,
        uint32 vlpTokenId
    );
    event newPerpMMRegistration(
        address owner,
        uint32 syntheticAsset,
        uint256 positionAddress,
        uint64 maxVlpSupply,
        uint32 vlpTokenId
    );

    mapping(address => mapping(uint256 => bool)) public s_approvedSpotMMs; // user => tabAddress => isApproved
    mapping(address => mapping(uint256 => bool)) public s_approvedPerpMMs; // user => positionAddress => isApproved

    mapping(uint32 => mapping(uint32 => bool)) public s_spotMarkets; // baseAsset => quoteAsset => marketExists
    mapping(uint32 => bool) s_perpMarkets; // syntheticAsset => marketExists

    struct SpotMMRegistration {
        address mmOwner;
        uint32 baseAsset;
        uint32 quoteAsset;
        uint256 tabAddress;
        uint64 maxVlpSupply;
        uint32 vlpTokenId;
    }

    struct PerpMMRegistration {
        address owner;
        uint32 syntheticAsset;
        uint256 positionAddress;
        uint64 maxVlpSupply;
        uint32 vlpTokenId;
    }

    uint32 public s_pendingSpotMMCount = 0;
    SpotMMRegistration[] public s_pendingSpotRegiistrations;
    uint32 public s_pendingPerpMMCount = 0;
    PerpMMRegistration[] public s_pendingPerpRegiistrations;

    constructor(
        address _owner,
        uint32[] memory baseAssets,
        uint32[] memory quoteAssets,
        uint32[] memory syntheticAssets
    ) {
        for (uint256 i = 0; i < baseAssets.length; i++) {
            uint32 baseAsset = baseAssets[i];
            uint32 quoteAsset = quoteAssets[i];

            s_spotMarkets[baseAsset][quoteAsset] = true;
        }

        for (uint256 i = 0; i < syntheticAssets.length; i++) {
            uint32 syntheticAsset = syntheticAssets[i];

            s_perpMarkets[syntheticAsset] = true;
        }

        owner = _owner;
    }

    //

    function approveMMRegistration(
        bool isPerp,
        address mmOwner,
        uint256 tabPosAddress
    ) public {
        require(
            msg.sender == owner,
            "Only owner can register a spot market maker"
        );

        if (isPerp) {
            s_approvedPerpMMs[mmOwner][tabPosAddress] = true;
        } else {
            s_approvedSpotMMs[mmOwner][tabPosAddress] = true;
        }
    }

    function registerSpotMarketMaker(
        uint32 baseAsset,
        uint32 quoteAsset,
        uint256 tabAddress,
        uint64 maxVlpSupply
    ) public {
        require(
            s_approvedSpotMMs[msg.sender][tabAddress],
            "Only approved spot market makers can register"
        );

        require(
            s_spotMarkets[baseAsset][quoteAsset],
            "Spot market does not exist"
        );

        // TODO: Get random vlpTokenId
        uint32 vlpTokenId = 1122334455;

        SpotMMRegistration memory registration = SpotMMRegistration(
            msg.sender,
            baseAsset,
            quoteAsset,
            tabAddress,
            maxVlpSupply,
            vlpTokenId
        );

        // store the registration under pending registrations
        s_pendingSpotRegiistrations[s_pendingSpotMMCount] = registration;
        s_pendingSpotMMCount += 1;

        emit newSpotMMRegistration(
            msg.sender,
            baseAsset,
            quoteAsset,
            tabAddress,
            maxVlpSupply,
            vlpTokenId
        );
    }

    function registerPerpMarketMaker(
        uint32 syntheticAsset,
        uint256 positionAddress,
        uint64 maxVlpSupply
    ) public {
        require(
            s_approvedPerpMMs[msg.sender][positionAddress],
            "Only approved perp market makers can register"
        );

        require(s_perpMarkets[syntheticAsset], "Perp market does not exist");

        // TODO: Get random vlpTokenId
        uint32 vlpTokenId = 1122334455;

        PerpMMRegistration memory registration = PerpMMRegistration(
            msg.sender,
            syntheticAsset,
            positionAddress,
            maxVlpSupply,
            vlpTokenId
        );

        // store the registration under pending registrations
        s_pendingPerpRegiistrations[s_pendingPerpMMCount] = registration;
        s_pendingPerpMMCount += 1;

        emit newPerpMMRegistration(
            msg.sender,
            syntheticAsset,
            positionAddress,
            maxVlpSupply,
            vlpTokenId
        );
    }
}
