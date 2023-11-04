// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "src/interfaces/IPedersenHash.sol";

library StateStructHasher {
    address constant PEDERSEN_HASH_ADDRESS =
        address(0x1a1eB562D2caB99959352E40a03B52C00ba7a5b1);

    function hashNote(Note memory note) internal view returns (uint256) {
        //

        uint256[] memory commitmentArr = new uint256[](2);
        commitmentArr[0] = note.amount;
        commitmentArr[1] = note.blinding;
        uint256[] memory commitment = IPedersenHash(PEDERSEN_HASH_ADDRESS).hash(
            abi.encodePacked(commitmentArr)
        );

        uint256[] memory inputArr = new uint256[](3);
        inputArr[0] = note.addressX;
        inputArr[1] = note.token;
        inputArr[2] = commitment[0];

        uint256[] memory noteHash = IPedersenHash(PEDERSEN_HASH_ADDRESS).hash(
            abi.encodePacked(commitmentArr)
        );

        return noteHash[0];
    }

    function hashPosition(
        Position memory position
    ) internal view returns (uint256) {
        //

        // & hash = H({allow_partial_liquidations, synthetic_token, position_address,  vlp_token, max_vlp_supply})
        uint256[] memory headerArr = new uint256[](5);
        headerArr[0] = position.allow_partial_liquidations ? 1 : 0;
        headerArr[1] = position.synthetic_oken;
        headerArr[2] = position.position_address;
        headerArr[3] = position.vlp_token;
        headerArr[4] = position.max_vlp_supply;
        uint256[] memory headerHash = IPedersenHash(PEDERSEN_HASH_ADDRESS).hash(
            abi.encodePacked(headerArr)
        );

        // & hash = H({header_hash, order_side, position_size, entry_price, liquidation_price, current_funding_idx, vlp_supply})
        uint256[] memory positionArr = new uint256[](7);
        positionArr[0] = headerHash[0];
        positionArr[1] = position.order_side ? 1 : 0;
        positionArr[2] = position.position_size;
        positionArr[3] = position.entry_price;
        positionArr[4] = position.liquidation_price;
        positionArr[5] = position.last_fundinx_idx;
        positionArr[6] = position.vlp_supply;
        uint256[] memory positionHash = IPedersenHash(PEDERSEN_HASH_ADDRESS)
            .hash(abi.encodePacked(headerArr));

        return positionHash[0];
    }

    function hashOrderTab(
        OrderTab memory orderTab
    ) internal view returns (uint256) {
        //

        // & header_hash = H({ is_smart_contract, base_token, quote_token, vlp_token, max_vlp_supply, pub_key})

        uint256[] memory headerArr = new uint256[](6);
        headerArr[0] = orderTab.is_smart_contract ? 1 : 0;
        headerArr[1] = orderTab.base_token;
        headerArr[2] = orderTab.quote_token;
        headerArr[3] = orderTab.vlp_token;
        headerArr[4] = orderTab.max_vlp_supply;
        headerArr[4] = orderTab.pub_key;
        uint256[] memory headerHash = IPedersenHash(PEDERSEN_HASH_ADDRESS).hash(
            abi.encodePacked(headerArr)
        );

        uint256[] memory baseCommitmentArr = new uint256[](2);
        baseCommitmentArr[0] = orderTab.base_amount;
        baseCommitmentArr[1] = orderTab.base_blinding;
        uint256[] memory baseCommitment = IPedersenHash(PEDERSEN_HASH_ADDRESS)
            .hash(abi.encodePacked(baseCommitmentArr));

        uint256[] memory quoteCommitmentArr = new uint256[](2);
        quoteCommitmentArr[0] = orderTab.quote_amount;
        quoteCommitmentArr[1] = orderTab.quote_blinding;
        uint256[] memory quoteCommitment = IPedersenHash(PEDERSEN_HASH_ADDRESS)
            .hash(abi.encodePacked(quoteCommitmentArr));

        uint256[] memory vlpCommitmentArr = new uint256[](2);
        vlpCommitmentArr[0] = orderTab.vlp_supply;
        vlpCommitmentArr[1] =
            (orderTab.base_blinding % 2 ** 128) +
            (orderTab.quote_blinding % 2 ** 128);
        uint256[] memory vlpCommitment = IPedersenHash(PEDERSEN_HASH_ADDRESS)
            .hash(abi.encodePacked(vlpCommitmentArr));

        // & H({header_hash, base_commitment, quote_commitment, vlp_supply_commitment})
        uint256[] memory orderTabArr = new uint256[](7);
        orderTabArr[0] = headerHash[0];
        orderTabArr[1] = baseCommitment[0];
        orderTabArr[2] = quoteCommitment[0];
        orderTabArr[3] = vlpCommitment[0];
        uint256[] memory orderTabHash = IPedersenHash(PEDERSEN_HASH_ADDRESS)
            .hash(abi.encodePacked(headerArr));

        return orderTabHash[0];
    }
}

struct Note {
    uint64 index;
    uint256 addressX;
    uint32 token;
    uint64 amount;
    uint256 blinding;
}

struct Position {
    uint64 index;
    //
    uint32 synthetic_oken;
    uint256 position_address;
    bool allow_partial_liquidations;
    uint32 vlp_token;
    uint64 max_vlp_supply;
    //
    bool order_side;
    uint64 position_size;
    uint64 margin;
    uint64 entry_price;
    uint64 liquidation_price;
    uint64 bankruptcy_price;
    uint32 last_fundinx_idx;
    uint64 vlp_supply;
    //
}

struct OrderTab {
    uint64 tab_idx;
    //
    bool is_smart_contract;
    uint32 base_token;
    uint32 quote_token;
    uint256 base_blinding;
    uint256 quote_blinding;
    uint32 vlp_token;
    uint64 max_vlp_supply;
    uint256 pub_key;
    //
    uint64 base_amount;
    uint64 quote_amount;
    uint64 vlp_supply;
}
