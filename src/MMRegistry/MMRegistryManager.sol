// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/ProgramOutputParser.sol";

import "./MMRegistryStorage.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract MMRegistryManager is OwnableUpgradeable, MMRegistryStorage {
    // address public s_admin;

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

    // function registerSpotMarketMaker(
    //     uint32 baseAsset,
    //     uint32 quoteAsset,
    //     uint256 tabAddress,
    //     uint64 maxVlpSupply
    // ) public {
    //     require(
    //         s_approvedSpotMMs[msg.sender][tabAddress],
    //         "Only approved spot market makers can register"
    //     );
    //     require(
    //         s_spotMarkets[baseAsset][quoteAsset],
    //         "Spot market does not exist"
    //     );
    //     require(
    //         s_spotRegistrations[tabAddress].tabAddress == 0,
    //         "already registered"
    //     );

    //     // TODO: Get random vlpTokenId
    //     uint32 vlpTokenId = 1122334455;

    //     SpotMMRegistration memory registration = SpotMMRegistration(
    //         msg.sender,
    //         baseAsset,
    //         quoteAsset,
    //         tabAddress,
    //         maxVlpSupply,
    //         vlpTokenId,
    //         false
    //     );

    //     // store the registration under pending registrations
    //     s_spotRegistrations[tabAddress] = registration;

    //     emit newSpotMMRegistration(
    //         msg.sender,
    //         baseAsset,
    //         quoteAsset,
    //         tabAddress,
    //         maxVlpSupply,
    //         vlpTokenId
    //     );
    // }

    function registerPerpMarketMaker(
        uint32 syntheticAsset,
        uint256 positionAddress,
        uint64 maxVlpSupply
    ) external {
        require(
            s_approvedPerpMMs[msg.sender][positionAddress],
            "Only approved perp market makers can register"
        );
        require(s_perpMarkets[syntheticAsset], "Perp market does not exist");
        require(
            s_perpRegistrations[syntheticAsset].positionAddress == 0,
            "already registered"
        );

        // TODO: Get random vlpTokenId
        uint32 vlpTokenId = 13579;

        PerpMMRegistration memory registration = PerpMMRegistration(
            msg.sender,
            syntheticAsset,
            positionAddress,
            maxVlpSupply,
            vlpTokenId,
            0
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

    // * UPDATE PENDING * //
    function updatePendingRegistrations(
        OnChainMMActionOutput[] memory registrations
    ) internal {
        for (uint256 i = 0; i < registrations.length; i++) {
            OnChainMMActionOutput memory registration = registrations[i];

            (
                uint32 vlpToken,
                uint64 maxVlpSupply,
                uint64 vlpAmount,
                uint256 mmAddress
            ) = ProgramOutputParser.uncompressRegistrationOutput(registration);

            // ? isPerp
            PerpMMRegistration storage perpRegistration = s_perpRegistrations[
                mmAddress
            ];

            if (
                perpRegistration.vlpTokenId == vlpToken &&
                perpRegistration.maxVlpSupply == maxVlpSupply &&
                perpRegistration.positionAddress == mmAddress
            ) {
                console.log("vlpAmount", vlpAmount);
                perpRegistration.vlpAmount = vlpAmount;
            }
        }
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
