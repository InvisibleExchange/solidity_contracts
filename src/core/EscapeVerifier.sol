// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/StructHasher.sol";
import "../libraries/ProgramOutputParser.sol";
import "../libraries/ElipticCurve.sol";

import "../interfaces/IVaultManager.sol";
import "../interfaces/IStructHasher.sol";
import "../interfaces/IPedersenHash.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "forge-std/console.sol";

contract EscapeVerifier is Initializable, OwnableUpgradeable, UUPSUpgradeable {
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
        uint32 indexed timestamp,
        Note[] escape_notes,
        uint256[2] indexed signature
    );
    event OrderTabEscapeEvent(
        uint32 escapeId,
        uint32 timestamp,
        OrderTab orderTab,
        uint256[2] signature
    );

    event PositionEscapeEvent(
        uint32 escapeId,
        uint64 closePrice,
        Position position_a,
        OpenOrderFields openOrderFields_b,
        uint256[2] signature_a,
        uint256[2] signature_b
    );
    event PositionEscapeEvent(
        uint32 escapeId,
        uint64 closePrice,
        Position position_a,
        Position position_b,
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

    uint32 public s_escapeCount;
    mapping(uint32 => ForcedEscape) public s_forcedEscapes; // escapeId => ForecdEscape
    mapping(uint32 => mapping(uint32 => uint64)) public s_escapeAmounts; // escapeId => tokenId => amount
    mapping(address => mapping(uint32 => bool)) public s_successfulEscapes; //   owner => escapeId => isValid

    // TODO: This should be set in an initializer not the code itself
    address constant PEDERSEN_HASH_ADDRESS =
        address(0x1a1eB562D2caB99959352E40a03B52C00ba7a5b1);
    address constant ELIPTIC_CURVE_ADDRESS = address(0x00);

    uint32 constant EXCHNAGE_VERIFICATION_TIME = 7 days;
    uint32 constant COLLATERAL_TOKEN = 55555;

    uint256 constant alpha = 1;
    uint256 constant beta =
        3141592653589793238462643383279502884197169399375105820974944592307816406665;
    uint256 constant P = 2 ** 251 + 17 * 2 ** 192 + 1;

    uint256 public version;
    address invisibleAddr;
    address structHasher;

    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        version = 1;
    }

    function setInvisibleAddress(address _invisible) external onlyOwner {
        invisibleAddr = _invisible;
    }

    function setStructHasher(address _structHasher) external onlyOwner {
        structHasher = _structHasher;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // * ====================================================================
    // * Notes
    function startNoteEscape(
        Note[] calldata notes,
        uint256[2] calldata signature,
        uint32 _escapeId // TODO: ONLY FOR TESTING
    ) external {
        require(signature[0] < P, "number not in range");
        require(signature[1] < P, "number not in range");

        uint32 timestamp = uint32(block.timestamp);

        // uint32 escapeId = s_escapeCount;
        // s_escapeCount++;
        uint32 escapeId = _escapeId;

        uint256 escapeHash = hashNoteEscapeMessage(escapeId, notes);

        s_forcedEscapes[escapeId] = ForcedEscape(
            escapeId,
            timestamp,
            escapeHash,
            signature,
            [uint256(0), uint256(0)],
            msg.sender
        );

        for (uint256 i = 0; i < notes.length; i++) {
            require(
                IVaultManager(invisibleAddr).isTokenRegistered(notes[i].token),
                "Token not registered"
            );

            require(notes[i].addressX < P, "number not in range");
            require(notes[i].blinding < P, "number not in range");

            s_escapeAmounts[escapeId][notes[i].token] += notes[i].amount;
        }

        console.log("escape hash ", s_forcedEscapes[escapeId].escapeHash);
        console.log("usdc escape amount ", s_escapeAmounts[escapeId][55555]);
        console.log("eth escape amount ", s_escapeAmounts[escapeId][54321]);

        emit NoteEscapeEvent(escapeId, timestamp, notes, signature);
    }

    function hashNoteEscapeMessage(
        uint32 escapeId,
        Note[] calldata notes
    ) public view returns (uint256) {
        uint256[] memory inputArr = new uint256[](notes.length + 1);
        inputArr[0] = escapeId;

        for (uint256 i = 0; i < notes.length; i++) {
            inputArr[i + 1] = IStructHasher(structHasher).hashNote(notes[i]);
        }

        uint256 noteEscapeHash = IStructHasher(structHasher).hashArr(inputArr);

        return noteEscapeHash;
    }

    // * ====================================================================
    // * Order Tabs
    function startOrderTabEscape(
        OrderTab calldata orderTab,
        uint256[2] calldata signature,
        uint32 _escapeId // TODO: ONLY FOR TESTING
    ) external {
        require(
            IVaultManager(invisibleAddr).isTokenRegistered(orderTab.base_token),
            "Base token not registered"
        );
        require(
            IVaultManager(invisibleAddr).isTokenRegistered(
                orderTab.quote_token
            ),
            "Quote Token not registered"
        );
        require(
            !orderTab.is_smart_contract,
            "Cannot force escape a smart contract inititated orderTab"
        );

        require(orderTab.base_blinding < P, "number not in range");
        require(orderTab.quote_blinding < P, "number not in range");
        require(orderTab.pub_key < P, "number not in range");

        require(signature[0] < P, "number not in range");
        require(signature[1] < P, "number not in range");

        uint32 timestamp = uint32(block.timestamp);

        // uint32 escapeId = s_escapeCount;
        // s_escapeCount++;
        uint32 escapeId = _escapeId;

        uint256 escapeHash = IStructHasher(structHasher).hashOrderTab(orderTab);

        s_forcedEscapes[escapeId] = ForcedEscape(
            escapeId,
            timestamp,
            escapeHash,
            signature,
            [uint256(0), uint256(0)],
            msg.sender
        );

        s_escapeAmounts[escapeId][orderTab.base_token] += orderTab.base_amount;
        s_escapeAmounts[escapeId][orderTab.quote_token] += orderTab
            .quote_amount;

        console.log("escape hash ", s_forcedEscapes[escapeId].escapeHash);
        console.log("usdc escape amount ", s_escapeAmounts[escapeId][55555]);
        console.log("eth escape amount ", s_escapeAmounts[escapeId][54321]);

        emit OrderTabEscapeEvent(escapeId, timestamp, orderTab, signature);
    }

    // * ====================================================================
    // * Positions
    function startPositionEscape(
        Position calldata position_a,
        uint64 closePrice,
        Position calldata position_b,
        uint256[2] calldata signature_a,
        uint256[2] calldata signature_b
    ) external {
        uint32 escapeId = s_escapeCount;
        s_escapeCount++;

        require(position_b.position_address < P, "number not in range");

        uint256 positionHash = IStructHasher(structHasher).hashPosition(
            position_b
        );
        uint256 escapeHash = hashPositionEscapeMessage(
            escapeId,
            position_a,
            closePrice,
            positionHash
        );

        escapePositionInner(
            position_a,
            closePrice,
            escapeId,
            escapeHash,
            signature_a,
            signature_b
        );

        emit PositionEscapeEvent(
            escapeId,
            closePrice,
            position_a,
            position_b,
            signature_a,
            signature_b
        );
    }

    function startPositionEscape(
        Position calldata position_a,
        uint64 closePrice,
        OpenOrderFields calldata openOrderFields_b,
        uint256[2] calldata signature_a,
        uint256[2] calldata signature_b,
        uint32 _escapeId // TODO: ONLY FOR TESTING
    ) external {
        //

        // uint32 escapeId = s_escapeCount;
        // s_escapeCount++;
        uint32 escapeId = _escapeId;

        _verifyOrderFields(openOrderFields_b);

        uint256 fields_hash = IStructHasher(structHasher).hashOpenOrderFields(
            openOrderFields_b
        );
        uint256 escapeHash = hashPositionEscapeMessage(
            escapeId,
            position_a,
            closePrice,
            fields_hash
        );

        escapePositionInner(
            position_a,
            closePrice,
            escapeId,
            escapeHash,
            signature_a,
            signature_b
        );

        console.log("escape hash ", s_forcedEscapes[escapeId].escapeHash);

        emit PositionEscapeEvent(
            escapeId,
            closePrice,
            position_a,
            openOrderFields_b,
            signature_a,
            signature_b
        );
    }

    function escapePositionInner(
        Position calldata position_a,
        uint64 closePrice,
        uint32 escapeId,
        uint256 escapeHash,
        uint256[2] calldata signature_a,
        uint256[2] calldata signature_b
    ) private {
        require(closePrice > 0);
        require(
            position_a.vlp_token == 0,
            "Cannot force escape a smart contract inititated position"
        );
        require(position_a.position_address < P, "number not in range");
        require(signature_a[0] < P, "number not in range");
        require(signature_a[1] < P, "number not in range");
        require(signature_b[0] < P, "number not in range");
        require(signature_b[1] < P, "number not in range");

        uint32 timestamp = uint32(block.timestamp);

        // TODO: We shouldnt used msg.sender here but rather a recipient value so that either party can initiate the escape
        s_forcedEscapes[escapeId] = ForcedEscape(
            escapeId,
            timestamp,
            escapeHash,
            signature_a,
            signature_b,
            msg.sender
        );
    }

    function hashPositionEscapeMessage(
        uint32 escapeId,
        Position calldata position_a,
        uint64 closePrice,
        uint256 hashInp4
    ) public view returns (uint256) {
        // & H = (escape_id, position_a.hash, close_price, open_order_fields_b.hash)

        uint256[] memory inputArr = new uint256[](4);
        inputArr[0] = escapeId;
        uint256 posHash = IStructHasher(structHasher).hashPosition(position_a);
        inputArr[1] = posHash;
        inputArr[2] = closePrice;
        inputArr[3] = hashInp4;

        uint256 positionEscapeHash = IStructHasher(structHasher).hashArr(
            inputArr
        );

        console.log("escapeId ", escapeId);
        console.log("positionHash ", posHash);
        console.log("closePrice ", closePrice);
        console.log("hashInp4 ", hashInp4);
        console.log("positionEscapeHash ", positionEscapeHash);

        return positionEscapeHash;
    }

    function _verifyOrderFields(
        OpenOrderFields calldata openOrderFields
    ) private pure {
        // ? Verify that all the values are in range (less than P)
        // ? Verify that the initial margin is correct
        // ? Verify all the notes are collateral token notes

        require(openOrderFields.position_address < P, "number not in range");

        uint64 sum = 0;
        for (uint256 i = 0; i < openOrderFields.notes_in.length; i++) {
            require(
                openOrderFields.notes_in[i].token == COLLATERAL_TOKEN,
                "Invalid collateral note token"
            );

            require(
                openOrderFields.notes_in[i].addressX < P,
                "number not in range"
            );
            require(
                openOrderFields.notes_in[i].blinding < P,
                "number not in range"
            );

            sum += openOrderFields.notes_in[i].amount;
        }

        if (openOrderFields.refund_note.amount > 0) {
            require(
                openOrderFields.refund_note.token == COLLATERAL_TOKEN,
                "Invalid collateral note token"
            );
            require(
                openOrderFields.refund_note.index ==
                    openOrderFields.notes_in[0].index,
                "invalid refund_note_index"
            );
        }

        uint64 inititalMargin = sum - openOrderFields.refund_note.amount;

        require(
            inititalMargin == openOrderFields.initial_margin,
            "Invalid initial margin"
        );

        require(
            openOrderFields.collateral_token == COLLATERAL_TOKEN,
            "Invalid collateral token"
        );
    }

    // * ====================================================================
    // * Verification

    function updatePendingEscapes(
        EscapeOutput[] memory escapeOutputs
    ) external {
        require(
            msg.sender == invisibleAddr,
            "Only invisible contract can call this function"
        );

        for (uint i = 0; i < escapeOutputs.length; i++) {
            (
                bool is_valid,
                EscapeType escape_type,
                uint32 escape_id,
                uint256 escape_message_hash,
                uint256 signature_r,
                uint256 signature_s
            ) = ProgramOutputParser.uncompressEscapeOutput(escapeOutputs[i]);

            ForcedEscape storage escape = s_forcedEscapes[escape_id];

            if (escape.escapeHash != escape_message_hash) continue;
            if (escape.signature_a[0] != signature_r) continue;
            if (escape.signature_a[1] != signature_s) continue;

            if (is_valid) {
                s_successfulEscapes[escape.caller][escape_id] = true;
            }

            delete s_forcedEscapes[escape_id];
        }
    }

    function updatePendingPositionEscapes(
        PositionEscapeOutput[] memory escapeOutputs
    ) external {
        require(
            msg.sender == invisibleAddr,
            "Only invisible contract can call this function"
        );

        console.log("escapeOutputs.length ", escapeOutputs.length);

        for (uint i = 0; i < escapeOutputs.length; i++) {
            (
                bool is_valid,
                uint32 escape_id,
                uint64 escape_value,
                uint256 escape_message_hash,
                uint256 signature_a_r,
                uint256 signature_a_s,
                uint256 signature_b_r,
                uint256 signature_b_s
            ) = ProgramOutputParser.uncompressEscapeOutput(escapeOutputs[i]);

            console.log("escape id ", escape_id);
            console.log("escape value ", escape_value);
            console.log("escape message hash ", escape_message_hash);

            ForcedEscape storage escape = s_forcedEscapes[escape_id];

            if (escape.escapeHash != escape_message_hash) continue;
            if (escape.signature_a[0] != signature_a_r) continue;
            if (escape.signature_a[1] != signature_a_s) continue;
            if (escape.signature_b[0] != signature_b_r) continue;
            if (escape.signature_b[1] != signature_b_s) continue;
            if (is_valid) {
                s_escapeAmounts[escape_id][COLLATERAL_TOKEN] += escape_value;
                s_successfulEscapes[escape.caller][escape_id] = true;
            }

            delete s_forcedEscapes[escape_id];
        }
    }

    // * ====================================================================
    // * Withdrawals

    function withdrawForcedEscape(uint32 escapeId, uint32 tokenId) external {
        uint32 timestamp = uint32(block.timestamp);

        require(
            s_successfulEscapes[msg.sender][escapeId],
            "Invalid escape attempt"
        );

        uint64 amount = s_escapeAmounts[escapeId][tokenId];
        require(amount > 0, "No escaped notes");

        s_escapeAmounts[escapeId][tokenId] = 0;

        uint256 amountScaled = IVaultManager(invisibleAddr).scaleUp(
            amount,
            tokenId
        );

        address tokenAddress = IVaultManager(invisibleAddr).getTokenAddress(
            tokenId
        );

        IVaultManager(invisibleAddr).executeEscape(
            tokenAddress,
            payable(msg.sender),
            amountScaled
        );

        emit EscapeWithdrawalEvent(
            escapeId,
            timestamp,
            tokenId,
            amount,
            msg.sender
        );
    }

    function forceEscapeAfterTimeout(
        Note[] calldata notes,
        uint256[2][] calldata noteAddresses,
        OrderTab[] calldata orderTabs,
        uint256[2][] calldata orderTabAddresses,
        Position[] calldata positions,
        uint256[2][] calldata positionAddresses
    ) external {
        // verify that all the notes/tabs/positions exist in the state and verify the signatures

        uint32 escapeId = s_escapeCount;
        s_escapeCount++;

        uint256[] memory pubKeySum = new uint256[](2);
        pubKeySum[0] = 0;
        pubKeySum[1] = 0;

        for (uint i = 0; i < notes.length; i++) {
            Note calldata note = notes[i];
            uint256[2] calldata addr = noteAddresses[i];

            // TODO: Verify the merkle proof!

            require(note.addressX == addr[0], "Invalid address");
            require(
                EllipticCurve.isOnCurve(addr[0], addr[1], alpha, beta, P),
                "Invalid address"
            );

            (uint256 pkSumX, uint256 pkSumY) = EllipticCurve.ecAdd(
                pubKeySum[0],
                pubKeySum[1],
                addr[0],
                addr[1],
                alpha,
                P
            );
            pubKeySum[0] = pkSumX;
            pubKeySum[1] = pkSumY;

            s_escapeAmounts[escapeId][note.token] += note.amount;
        }

        for (uint i = 0; i < orderTabs.length; i++) {
            OrderTab calldata orderTab = orderTabs[i];
            uint256[2] calldata addr = orderTabAddresses[i];

            // TODO: Verify the merkle proof!

            require(orderTab.pub_key == addr[0], "Invalid address");
            require(
                EllipticCurve.isOnCurve(addr[0], addr[1], alpha, beta, P),
                "Invalid address"
            );

            (uint256 pkSumX, uint256 pkSumY) = EllipticCurve.ecAdd(
                pubKeySum[0],
                pubKeySum[1],
                addr[0],
                addr[1],
                alpha,
                P
            );
            pubKeySum[0] = pkSumX;
            pubKeySum[1] = pkSumY;

            s_escapeAmounts[escapeId][orderTab.base_token] += orderTab
                .base_amount;
            s_escapeAmounts[escapeId][orderTab.quote_token] += orderTab
                .quote_amount;
        }

        for (uint i = 0; i < positions.length; i++) {
            Position calldata position = positions[i];
            uint256[2] calldata addr = orderTabAddresses[i];

            // TODO: Verify the merkle proof!

            require(position.position_address == addr[0], "Invalid address");
            require(
                EllipticCurve.isOnCurve(addr[0], addr[1], alpha, beta, P),
                "Invalid address"
            );

            (uint256 pkSumX, uint256 pkSumY) = EllipticCurve.ecAdd(
                pubKeySum[0],
                pubKeySum[1],
                addr[0],
                addr[1],
                alpha,
                P
            );
            pubKeySum[0] = pkSumX;
            pubKeySum[1] = pkSumY;

            s_escapeAmounts[escapeId][position.synthetic_token] += position
                .position_size;
        }

        // TODO: Verify the signature

        s_successfulEscapes[msg.sender][escapeId] = true;
    }
}
