// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/ProgramOutputParser.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract MMRegistry is OwnableUpgradeable {
    // address public s_admin;

    event newSpotMMRegistration(
        address mmOwner,
        uint32 baseAsset,
        uint32 quoteAsset,
        uint256 tabAddress,
        uint64 maxVlpSupply,
        uint32 vlpTokenId
    );
    event newPerpMMRegistration(
        address mmOwner,
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
        bool isRegistered;
    }

    struct PerpMMRegistration {
        address mmOwner;
        uint32 syntheticAsset;
        uint256 positionAddress;
        uint64 maxVlpSupply;
        uint32 vlpTokenId;
        bool isRegistered;
    }

    uint32 public s_pendingSpotMMCount;
    mapping(uint256 => SpotMMRegistration) public s_spotRegistrations; // tabAddress => SpotMMRegistration
    uint32 public s_pendingPerpMMCount;
    mapping(uint256 => PerpMMRegistration) public s_perpRegistrations; // posAddress => PerpMMRegistration

    function updatePendingRegistrations(
        MMRegistrationOutput[] memory registrations,
        uint64 txBatchId
    ) public {
        for (uint256 i = 0; i < registrations.length; i++) {
            MMRegistrationOutput memory registration = registrations[i];

            (
                bool isPerp,
                uint32 vlpToken,
                uint64 maxVlpSupply,
                uint256 mmAddress
            ) = ProgramOutputParser.uncompressRegistrationOutput(registration);

            if (isPerp) {
                // ? isPerp
                PerpMMRegistration
                    storage perpRegistration = s_perpRegistrations[mmAddress];

                if (
                    perpRegistration.vlpTokenId == vlpToken &&
                    perpRegistration.maxVlpSupply == maxVlpSupply &&
                    perpRegistration.positionAddress == mmAddress
                ) {
                    perpRegistration.isRegistered = true;
                }
            } else {
                // ? isSpot
                SpotMMRegistration
                    storage spotRegistration = s_spotRegistrations[mmAddress];

                if (
                    spotRegistration.vlpTokenId == vlpToken &&
                    spotRegistration.maxVlpSupply == maxVlpSupply &&
                    spotRegistration.tabAddress == mmAddress
                ) {
                    spotRegistration.isRegistered = true;
                }
            }
        }
    }

    //

    function registerNewMarkets(
        uint32[] memory baseAssets,
        uint32[] memory quoteAssets,
        uint32[] memory syntheticAssets
    ) public onlyOwner {
        require(baseAssets.length == quoteAssets.length, "Invalid input");

        for (uint256 i = 0; i < baseAssets.length; i++) {
            uint32 baseAsset = baseAssets[i];
            uint32 quoteAsset = quoteAssets[i];

            s_spotMarkets[baseAsset][quoteAsset] = true;
        }

        for (uint256 i = 0; i < syntheticAssets.length; i++) {
            uint32 syntheticAsset = syntheticAssets[i];

            s_perpMarkets[syntheticAsset] = true;
        }
    }

    function approveMMRegistration(
        bool isPerp,
        address mmOwner,
        uint256 tabPosAddress
    ) public onlyOwner {
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
        require(
            s_spotRegistrations[tabAddress].tabAddress == 0,
            "already registered"
        );

        // TODO: Get random vlpTokenId
        uint32 vlpTokenId = 1122334455;

        SpotMMRegistration memory registration = SpotMMRegistration(
            msg.sender,
            baseAsset,
            quoteAsset,
            tabAddress,
            maxVlpSupply,
            vlpTokenId,
            false
        );

        // store the registration under pending registrations
        s_spotRegistrations[tabAddress] = registration;

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
        require(
            s_perpRegistrations[syntheticAsset].positionAddress != 0,
            "already registered"
        );

        // TODO: Get random vlpTokenId
        uint32 vlpTokenId = 1122334455;

        PerpMMRegistration memory registration = PerpMMRegistration(
            msg.sender,
            syntheticAsset,
            positionAddress,
            maxVlpSupply,
            vlpTokenId,
            false
        );

        // store the registration under pending registrations
        s_perpRegistrations[positionAddress] = registration;

        emit newPerpMMRegistration(
            msg.sender,
            syntheticAsset,
            positionAddress,
            maxVlpSupply,
            vlpTokenId
        );
    }

    function isAddressRegistered(uint256 mmAddress) public view returns (bool) {
        return
            s_spotRegistrations[mmAddress].isRegistered ||
            s_perpRegistrations[mmAddress].isRegistered;
    }
}
