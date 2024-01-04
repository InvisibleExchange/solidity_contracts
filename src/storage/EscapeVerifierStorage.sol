// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../libraries/StructHasher.sol";

abstract contract EscapeVerifierStorage {
    struct ForcedEscape {
        uint32 escapeId;
        uint32 timestamp;
        uint256 escapeHash;
        uint256[2] signature_a;
        uint256[2] signature_b; // Only for position escapes
        address caller;
    }

    // * Events
    event NoteEscapeEvent(
        uint32 indexed escapeId,
        uint32 timestamp,
        Note[] escape_notes,
        uint256[2] signature
    );
    event OrderTabEscapeEvent(
        uint32 escapeId,
        uint32 timestamp,
        OrderTab orderTab,
        uint256[2] signature
    );

    event PositionEscapeEventA(
        uint32 escapeId,
        uint64 closePrice,
        Position position_a,
        OpenOrderFields openOrderFields_b,
        address recipient,
        uint256[2] signature_a,
        uint256[2] signature_b
    );
    event PositionEscapeEventB(
        uint32 escapeId,
        uint64 closePrice,
        Position position_a,
        Position position_b,
        address recipient,
        uint256[2] signature_a,
        uint256[2] signature_b
    );

    event EscapeWithdrawalEvent(
        uint32 escapeId,
        uint32 timestamp,
        uint32 tokenId,
        uint64 amount,
        address recipient
    );

    uint32 s_escapeCount;
    mapping(uint32 => ForcedEscape) public s_forcedEscapes; // escapeId => ForecdEscape
    mapping(uint32 => mapping(uint32 => uint64)) public s_escapeAmounts; // escapeId => tokenId => amount
    mapping(address => mapping(uint32 => bool)) public s_successfulEscapes; //   owner => escapeId => isValid

    uint32 constant EXCHNAGE_VERIFICATION_TIME = 7 days;
    uint32 constant COLLATERAL_TOKEN = 2413654107;

    uint256 constant P = 2 ** 251 + 17 * 2 ** 192 + 1;

    // uint256 constant alpha = 1;
    // uint256 constant beta =
    //     3141592653589793238462643383279502884197169399375105820974944592307816406665;

    address invisibleAddr;
    address structHasher;
    uint256 version;
}
