// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../interfaces/IPedersenHash.sol";

contract PedersenStructHasher {
    address constant PEDERSEN_HASH_ADDRESS =
        address(0x1a1eB562D2caB99959352E40a03B52C00ba7a5b1);

    function hashNote(Note calldata note) public view returns (uint256) {
        //

        if (note.amount == 0) {
            return 0;
        }

        uint256 commitment = hash2(note.amount, note.blinding);

        uint256[] memory inputArr = new uint256[](3);
        inputArr[0] = note.addressX;
        inputArr[1] = note.token;
        inputArr[2] = commitment;
        uint256 noteHash = hashArr(inputArr);

        return noteHash;
    }

    function hashPosition(
        Position memory position
    ) external view returns (uint256) {
        //

        // & hash = H({allow_partial_liquidations, synthetic_token, position_address,  vlp_token})
        uint256[] memory headerArr = new uint256[](4);
        headerArr[0] = position.allow_partial_liquidations ? 1 : 0;
        headerArr[1] = uint256(position.synthetic_token);
        headerArr[2] = uint256(position.position_address);
        headerArr[3] = position.vlp_token;
        uint256 headerHash = hashArr(headerArr);

        // & hash = H({header_hash, order_side, position_size, entry_price, liquidation_price, current_funding_idx, vlp_supply})
        uint256[] memory positionArr = new uint256[](7);
        positionArr[0] = headerHash;
        positionArr[1] = position.order_side ? 1 : 0;
        positionArr[2] = position.position_size;
        positionArr[3] = position.entry_price;
        positionArr[4] = position.liquidation_price;
        positionArr[5] = position.last_funding_idx;
        positionArr[6] = position.vlp_supply;
        uint256 positionHash = hashArr(positionArr);

        return positionHash;
    }

    function hashOrderTab(
        OrderTab memory orderTab
    ) external view returns (uint256) {
        //

        // & header_hash = H({ is_smart_contract, base_token, quote_token, pub_key})

        uint256[] memory headerArr = new uint256[](6);
        headerArr[0] = orderTab.is_smart_contract ? 1 : 0;
        headerArr[1] = orderTab.base_token;
        headerArr[2] = orderTab.quote_token;
        headerArr[5] = orderTab.pub_key;
        uint256 headerHash = hashArr(headerArr);

        uint256 baseCommitment = hash2(
            orderTab.base_amount,
            orderTab.base_blinding
        );

        uint256 quoteCommitment = hash2(
            orderTab.quote_amount,
            orderTab.quote_blinding
        );

        if (orderTab.vlp_supply <= 0) {
            // & H({header_hash, base_commitment, quote_commitment, vlp_supply_commitment})
            uint256[] memory orderTabArr = new uint256[](4);
            orderTabArr[0] = headerHash;
            orderTabArr[1] = baseCommitment;
            orderTabArr[2] = quoteCommitment;
            orderTabArr[3] = 0;
            uint256 orderTabHash = hashArr(orderTabArr);

            return orderTabHash;
        } else {
            uint256 vlpCommitment = hash2(
                orderTab.vlp_supply,
                (orderTab.base_blinding % 2 ** 128) +
                    (orderTab.quote_blinding % 2 ** 128)
            );

            // & H({header_hash, base_commitment, quote_commitment, vlp_supply_commitment})
            uint256[] memory orderTabArr = new uint256[](4);
            orderTabArr[0] = headerHash;
            orderTabArr[1] = baseCommitment;
            orderTabArr[2] = quoteCommitment;
            orderTabArr[3] = vlpCommitment;
            uint256 orderTabHash = hashArr(orderTabArr);

            return orderTabHash;
        }
    }

    function hashOpenOrderFields(
        OpenOrderFields calldata openOrderFields
    ) external view returns (uint256) {
        //
        // & H = (note_hashes, refund_note_hash, initial_margin, collateral_token, position_address, allow_partial_liquidations)

        uint256[] memory inputArr = new uint256[](
            openOrderFields.notes_in.length + 5
        );
        for (uint256 i = 0; i < openOrderFields.notes_in.length; i++) {
            inputArr[i] = hashNote(openOrderFields.notes_in[i]);
        }
        inputArr[openOrderFields.notes_in.length] = hashNote(
            openOrderFields.refund_note
        );
        inputArr[openOrderFields.notes_in.length + 1] = openOrderFields
            .initial_margin;
        inputArr[openOrderFields.notes_in.length + 2] = openOrderFields
            .collateral_token;
        inputArr[openOrderFields.notes_in.length + 3] = openOrderFields
            .position_address;
        inputArr[openOrderFields.notes_in.length + 4] = openOrderFields
            .allow_partial_liquidations
            ? 1
            : 0;

        uint256 fieldsHash = hashArr(inputArr);

        return fieldsHash;
    }

    function hash2(uint256 a, uint256 b) public view returns (uint256 hash_) {
        hash_ = IPedersenHash(PEDERSEN_HASH_ADDRESS).hash(
            abi.encodePacked([a, b])
        )[0];
    }

    function hashArr(uint256[] memory arr) public view returns (uint256) {
        uint256 hash_ = 0;
        for (uint256 i = 0; i < arr.length; i++) {
            hash_ = IPedersenHash(PEDERSEN_HASH_ADDRESS).hash(
                abi.encodePacked([hash_, arr[i]])
            )[0];
        }

        uint256[2] memory hashInp = [hash_, arr.length];
        hash_ = IPedersenHash(PEDERSEN_HASH_ADDRESS).hash(
            abi.encodePacked(hashInp)
        )[0];

        return hash_;
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
    uint32 synthetic_token;
    uint256 position_address;
    bool allow_partial_liquidations;
    uint32 vlp_token;
    //
    bool order_side;
    uint64 position_size;
    uint64 margin;
    uint64 entry_price;
    uint64 liquidation_price;
    uint64 bankruptcy_price;
    uint32 last_funding_idx;
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
    uint256 pub_key;
    //
    uint64 base_amount;
    uint64 quote_amount;
    uint64 vlp_supply;
}

//

struct OpenOrderFields {
    uint64 initial_margin;
    uint32 collateral_token;
    Note[] notes_in;
    Note refund_note;
    uint256 position_address;
    bool allow_partial_liquidations;
}
