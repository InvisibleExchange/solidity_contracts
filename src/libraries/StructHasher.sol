// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../interfaces/IPedersenHash.sol";


contract StructHasher {
    uint256 constant P = 2 ** 251 + 17 * 2 ** 192 + 1;

    function hashNote(Note calldata note) public pure returns (uint256) {
        //

        if (note.amount == 0) {
            return 0;
        }

        // & H = H({address, token, amount, blinding})
        uint256[] memory inputArr = new uint256[](4);
        inputArr[0] = note.addressX;
        inputArr[1] = note.token;
        inputArr[2] = note.amount;
        inputArr[3] = note.blinding;
        uint256 noteHash = hashArr(inputArr);

        return noteHash;
    }

    function hashPosition(
        Position memory position
    ) external pure returns (uint256) {
        //

        // & hash = H({allow_partial_liquidations, synthetic_token, position_address, vlp_token, max_vlp_supply, order_side, position_size, entry_price, liquidation_price, last_funding_idx, vlp_supply})
        uint256[] memory positionArr = new uint256[](4);
        positionArr[0] = position.allow_partial_liquidations ? 1 : 0;
        positionArr[1] = uint256(position.synthetic_token);
        positionArr[2] = uint256(position.position_address);
        positionArr[3] = position.vlp_token;
        positionArr[3] = position.max_vlp_supply;
        positionArr[4] = position.order_side ? 1 : 0;
        positionArr[5] = position.position_size;
        positionArr[6] = position.entry_price;
        positionArr[7] = position.liquidation_price;
        positionArr[8] = position.last_funding_idx;
        positionArr[9] = position.vlp_supply;
        uint256 positionHash = hashArr(positionArr);

        return positionHash;
    }

    function hashOrderTab(
        OrderTab memory orderTab
    ) external pure returns (uint256) {
        //

        // & H({base_token, quote_token, pub_key, base_amount, quote_amount})
        uint256[] memory headerArr = new uint256[](5);
        headerArr[0] = orderTab.base_token;
        headerArr[1] = orderTab.quote_token;
        headerArr[2] = orderTab.pub_key;
        headerArr[3] = orderTab.base_amount;
        headerArr[4] = orderTab.quote_amount;
        uint256 headerHash = hashArr(headerArr);

        return headerHash;
    }

    function hashOpenOrderFields(
        OpenOrderFields calldata openOrderFields
    ) external pure returns (uint256) {
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

    function hash2(uint256 a, uint256 b) public pure returns (uint256 hash_) {
        bytes memory data = abi.encodePacked(a, b);

        bytes32 h = keccak256(data);

        return uint256(h) % P;
    }

    function hashArr(uint256[] memory arr) public pure returns (uint256) {
        bytes memory data = abi.encodePacked(arr);

        bytes32 h = keccak256(data);

        return uint256(h) % P;
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
    uint64 max_vlp_supply;
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
    uint32 base_token;
    uint32 quote_token;
    uint256 base_blinding;
    uint256 quote_blinding;
    uint256 pub_key;
    //
    uint64 base_amount;
    uint64 quote_amount;
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
