// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../libraries/ProgramOutputParser.sol";
import "./MMRegistryUpdates.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract MMRegistryManager is OwnableUpgradeable, MMRegistryUpdates {
    uint32 constant MAX_VLP_ID = 100_000;

    function registerNewMarkets(
        uint32[] memory syntheticAssets
    ) external onlyOwner {
        // require(baseAssets.length == quoteAssets.length, "Invalid input");

        // for (uint256 i = 0; i < baseAssets.length; i++) {
        //     uint32 baseAsset = baseAssets[i];
        //     uint32 quoteAsset = quoteAssets[i];

        //     s_spotMarkets[baseAsset][quoteAsset] = true;
        // }

        for (uint256 i = 0; i < syntheticAssets.length; i++) {
            uint32 syntheticAsset = syntheticAssets[i];

            s_perpMarkets[syntheticAsset] = true;
        }
    }

    function approveMMRegistration(
        address mmOwner,
        uint256 tabPosAddress
    ) external onlyOwner {
        s_approvedPerpMMs[mmOwner][tabPosAddress] = true;
    }

    function registerPerpMarketMaker(
        uint32 syntheticAsset,
        uint256 positionAddress
    ) external {
        require(
            s_approvedPerpMMs[msg.sender][positionAddress],
            "Only approved perp market makers can register"
        );
        require(s_perpMarkets[syntheticAsset], "Perp market does not exist");
        // require(
        //     s_perpRegistrations[positionAddress].positionAddress == 0,
        //     "already registered"
        // );

        uint32 vlpTokenId = s_vlpTokenIdCount + 1;
        require(vlpTokenId < MAX_VLP_ID);
        s_vlpTokenIdCount += 1;

        PerpMMRegistration memory registration = PerpMMRegistration(
            msg.sender,
            syntheticAsset,
            positionAddress,
            vlpTokenId,
            0
        );

        // store the registration under pending registrations
        s_perpRegistrations[positionAddress] = registration;

        uint32 mmActionId = s_mmActionId;
        s_mmActionId++;

        emit newPerpMMRegistration(
            msg.sender,
            syntheticAsset,
            positionAddress,
            vlpTokenId,
            mmActionId
        );
    }

    // * VIEW FUNCTIONS * //

    function isMarketRegistered(
        uint32 syntheticAsset
    ) public view returns (bool) {
        return s_perpMarkets[syntheticAsset];
    }

    function isAddressRegistered(uint256 mmAddress) public view returns (bool) {
        return s_perpRegistrations[mmAddress].vlpAmount > 0;
    }
}
