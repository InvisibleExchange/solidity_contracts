// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../storage/VaultManagerStorage.sol";
import "../interfaces/ICLAggregator.sol";

abstract contract TokenInfo is VaultManagerStorage {
    function __tokenInfo_init() internal {
        // ETH
        s_tokenAddress2Id[address(0)] = ETH_ID;
        s_tokenId2Address[ETH_ID] = address(0);
        s_tokenId2ScaleFactor[ETH_ID] = 18 - 8;
        s_tokenIdIsRegistered[ETH_ID] = true;
    }

    function _setClAggregator(
        address tokenAddress,
        address aggregatorAddress
    ) internal {
        s_clAggregators[tokenAddress] = aggregatorAddress;
    }

    //
    // sacle-factor = onchain_decimals - offchain_decimals
    // If token has 18 decimals onchain and 9 decimals offchain then scale factor is 10
    //

    function _registerToken(
        address tokenAddress,
        uint32 tokenId,
        uint8 offchainDecimals
    ) internal {
        require(tokenAddress != address(0), "Token address Should not be 0");
        require(tokenId != 0, "Token ID Should not be 0");

        require(
            s_tokenAddress2Id[tokenAddress] == 0,
            "Token already registered"
        );
        require(
            s_tokenId2Address[tokenId] == address(0),
            "Token already registered"
        );
        require(tokenId > MIN_TOKEN_ID);

        IERC20Metadata token = IERC20Metadata(tokenAddress);
        uint8 tokenDecimals = token.decimals();
        uint8 scaleFactor = tokenDecimals - offchainDecimals;

        require(scaleFactor <= 18, "Scale factor too large");

        s_tokenAddress2Id[tokenAddress] = tokenId;
        s_tokenId2Address[tokenId] = tokenAddress;
        s_tokenId2ScaleFactor[tokenId] = scaleFactor;

        s_tokenIdIsRegistered[tokenId] = true;

        emit NewTokenRegisteredEvent(tokenAddress, tokenId, scaleFactor);
    }

    function scaleUp(
        uint64 amount,
        uint32 tokenId
    ) public view returns (uint256 amountScaled) {
        require(s_tokenIdIsRegistered[tokenId], "Token not registered");

        uint8 scaleFactor = s_tokenId2ScaleFactor[tokenId];

        require(scaleFactor >= 0, "Invalid scale factor");
        require(scaleFactor <= 18, "Invalid scale factor");
        amountScaled = uint256(amount) * (10 ** scaleFactor);

        return amountScaled;
    }

    function scaleDown(
        uint256 amount,
        uint32 tokenId
    ) public view returns (uint64 amountScaled) {
        require(s_tokenIdIsRegistered[tokenId], "Token not registered");

        uint8 scaleFactor = s_tokenId2ScaleFactor[tokenId];

        require(scaleFactor >= 0, "Invalid scale factor");
        require(scaleFactor <= 18, "Invalid scale factor");
        amountScaled = uint64(amount / (10 ** scaleFactor));

        return amountScaled;
    }

    function getTokenPrice(
        address tokenAddress
    ) public view returns (uint8, uint256) {
        require(s_tokenAddress2Id[tokenAddress] != 0, "Token not registered");

        address clAggregator = s_clAggregators[tokenAddress];

        if (clAggregator == address(0)) {
            // ? This is a stablecoin
            return (8, 10 ** 8);
        }

        uint8 decimals = ICLAggregator(clAggregator).decimals();
        uint256 latestPrice = uint256(
            ICLAggregator(clAggregator).latestAnswer()
        );

        // uint8 decimals = 8;
        // uint256 latestPrice = 10 ** 8;

        return (decimals, latestPrice);
    }

    function getTokenAddress(uint32 tokenId) public view returns (address) {
        return s_tokenId2Address[tokenId];
    }

    function getTokenId(address tokenAddress) public view returns (uint32) {
        return s_tokenAddress2Id[tokenAddress];
    }

    function isTokenRegistered(uint32 tokenId) public view returns (bool) {
        return s_tokenIdIsRegistered[tokenId];
    }

    function getScaleFactor(uint32 tokenId) public view returns (uint8) {
        return s_tokenId2ScaleFactor[tokenId];
    }
}
