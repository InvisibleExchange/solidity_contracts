// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../libraries/StructHasher.sol";
import "../../libraries/ProgramOutputParser.sol";
import "../../storage/EscapeVerifierStorage.sol";

import "../../interfaces/IVaultManager.sol";
import "../../interfaces/IStructHasher.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// TODO: Make sure the same escape cannot be submitted twice

contract EscapeVerifier is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    EscapeVerifierStorage
{
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
        uint256[2] calldata signature
    ) external {
        require(signature[0] < P, "number not in range");
        require(signature[1] < P, "number not in range");

        uint32 timestamp = uint32(block.timestamp);

        uint32 escapeId = s_escapeCount;
        s_escapeCount++;

        for (uint256 i = 0; i < notes.length; i++) {
            require(
                IVaultManager(invisibleAddr).isTokenRegistered(notes[i].token),
                "Token not registered"
            );

            require(notes[i].addressX < P, "number not in range");
            require(notes[i].blinding < P, "number not in range");

            s_escapeAmounts[escapeId][notes[i].token] += notes[i].amount;
        }

        uint256 escapeHash = hashNoteEscapeMessage(notes);

        s_forcedEscapes[escapeId] = ForcedEscape(
            escapeId,
            timestamp,
            escapeHash,
            signature,
            [uint256(0), uint256(0)],
            msg.sender
        );

        emit NoteEscapeEvent(escapeId, timestamp, notes, signature);
    }

    function hashNoteEscapeMessage(
        Note[] calldata notes
    ) public view returns (uint256) {
        uint256[] memory inputArr = new uint256[](notes.length);

        for (uint256 i = 0; i < notes.length; i++) {
            inputArr[i] = IStructHasher(structHasher).hashNote(notes[i]);
        }

        uint256 noteEscapeHash = IStructHasher(structHasher).hashArr(inputArr);

        return noteEscapeHash;
    }

    // * ====================================================================
    // * Order Tabs
    function startOrderTabEscape(
        OrderTab calldata orderTab,
        uint256[2] calldata signature
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

        require(orderTab.base_blinding < P, "number not in range");
        require(orderTab.quote_blinding < P, "number not in range");
        require(orderTab.pub_key < P, "number not in range");

        require(signature[0] < P, "number not in range");
        require(signature[1] < P, "number not in range");

        uint32 timestamp = uint32(block.timestamp);

        uint32 escapeId = s_escapeCount;
        s_escapeCount++;

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

        emit OrderTabEscapeEvent(escapeId, timestamp, orderTab, signature);
    }

    // * ====================================================================
    // * Positions
    function startPositionEscape1(
        Position calldata position_a,
        uint64 closePrice,
        Position calldata position_b,
        address recipient,
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
            position_a,
            closePrice,
            positionHash,
            recipient
        );

        escapePositionInner(
            position_a,
            closePrice,
            recipient,
            escapeId,
            escapeHash,
            signature_a,
            signature_b
        );

        emit PositionEscapeEventB(
            escapeId,
            closePrice,
            position_a,
            position_b,
            recipient,
            signature_a,
            signature_b
        );
    }

    function startPositionEscape2(
        Position calldata position_a,
        uint64 closePrice,
        OpenOrderFields calldata openOrderFields_b,
        address recipient,
        uint256[2] calldata signature_a,
        uint256[2] calldata signature_b
    ) external {
        //

        uint32 escapeId = s_escapeCount;
        s_escapeCount++;

        _verifyOrderFields(openOrderFields_b);

        uint256 fields_hash = IStructHasher(structHasher).hashOpenOrderFields(
            openOrderFields_b
        );
        uint256 escapeHash = hashPositionEscapeMessage(
            position_a,
            closePrice,
            fields_hash,
            recipient
        );

        escapePositionInner(
            position_a,
            closePrice,
            recipient,
            escapeId,
            escapeHash,
            signature_a,
            signature_b
        );

        emit PositionEscapeEventA(
            escapeId,
            closePrice,
            position_a,
            openOrderFields_b,
            recipient,
            signature_a,
            signature_b
        );
    }

    function escapePositionInner(
        Position calldata position_a,
        uint64 closePrice,
        address recipient,
        uint32 escapeId,
        uint256 escapeHash,
        uint256[2] calldata signature_a,
        uint256[2] calldata signature_b
    ) private {
        require(closePrice > 0, "Invalid close price");
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

        s_forcedEscapes[escapeId] = ForcedEscape(
            escapeId,
            timestamp,
            escapeHash,
            signature_a,
            signature_b,
            recipient
        );
    }

    function hashPositionEscapeMessage(
        Position calldata position_a,
        uint64 closePrice,
        uint256 hashInp4,
        address recipient
    ) public view returns (uint256) {
        // & H = (position_a.hash, close_price, open_order_fields_b.hash, recipient)

        uint256[] memory inputArr = new uint256[](4);
        uint256 posHash = IStructHasher(structHasher).hashPosition(position_a);
        inputArr[0] = posHash;
        inputArr[1] = closePrice;
        inputArr[2] = hashInp4;
        inputArr[3] = uint256(uint160(recipient));

        uint256 positionEscapeHash = IStructHasher(structHasher).hashArr(
            inputArr
        );

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

    event TestEvent(
        bool is_valid,
        EscapeType escape_type,
        uint32 escape_id,
        uint256 escape_message_hash,
        uint256 signature_r,
        uint256 signature_s
    );

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

        for (uint i = 0; i < escapeOutputs.length; i++) {
            (
                bool is_valid,
                uint32 escape_id,
                uint64 escape_value,
                address recipient,
                uint256 escape_message_hash,
                uint256 signature_a_r,
                uint256 signature_a_s,
                uint256 signature_b_r,
                uint256 signature_b_s
            ) = ProgramOutputParser.uncompressEscapeOutput(escapeOutputs[i]);

            ForcedEscape storage escape = s_forcedEscapes[escape_id];

            if (escape.escapeHash != escape_message_hash) continue;
            if (escape.signature_a[0] != signature_a_r) continue;
            if (escape.signature_a[1] != signature_a_s) continue;
            if (escape.signature_b[0] != signature_b_r) continue;
            if (escape.signature_b[1] != signature_b_s) continue;
            if (escape.caller != recipient) continue;
            if (is_valid) {
                s_escapeAmounts[escape_id][COLLATERAL_TOKEN] += escape_value;
                s_successfulEscapes[recipient][escape_id] = true;
            }

            delete s_forcedEscapes[escape_id];
        }
    }

    // * ====================================================================
    // * Withdrawals

    function withdrawForcedEscape(
        uint32 escapeId,
        uint32 tokenId
    ) external nonReentrant {
        uint32 timestamp = uint32(block.timestamp);

        require(
            s_successfulEscapes[msg.sender][escapeId],
            "Invalid escape attempt"
        );

        uint64 amount = s_escapeAmounts[escapeId][tokenId];
        require(amount > 0, "No escaped amount to claim");

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

    // * ====================================================================

    // function test(uint8 option) external {
    //     if (option == 0) {
    //         Note[] memory notes = new Note[](1);
    //         notes[0] = Note(
    //             1,
    //             1892652375893125298235632798523846235738495234623495782352345325,
    //             3332652375893125298235632798523846235738495234623495782352345325,
    //             3592681469,
    //             100000000,
    //             1892652375893125298235632798523846235738495234623495782352345325
    //         );

    //         uint[2] memory signature = [
    //             uint256(
    //                 1892652375893125298235632798523846235738495234623495782352345325
    //             ),
    //             uint256(
    //                 1892652375893125298235632798523846235738495234623495782352345325
    //             )
    //         ];

    //         emit NoteEscapeEvent(1, 3794302, notes, signature);
    //     } else if (option == 1) {
    //         OrderTab memory orderTab = OrderTab(
    //             11,
    //             3592681469,
    //             2413654107,
    //             1892652375893125298235632798523846235738495234623495782352345325,
    //             2378562359832657523895236527352385723497523695378235823695723432,
    //             9782356275235973284448444332444442445634523541287423615789324623,
    //             350000000,
    //             2000000000
    //         );

    //         uint[2] memory signature = [
    //             uint256(
    //                 1892652375893125298235632798523846235738495234623495782352345325
    //             ),
    //             uint256(
    //                 1892652375893125298235632798523846235738495234623495782352345325
    //             )
    //         ];

    //         emit OrderTabEscapeEvent(2, 3794302, orderTab, signature);
    //     } else if (option == 2) {
    //         Position memory position_a = Position(
    //             7,
    //             453755560,
    //             1892652375893125298235632798523846235738495234623495782352345325,
    //             true,
    //             0,
    //             0,
    //             true,
    //             100000000,
    //             100000000,
    //             100000000,
    //             0,
    //             0,
    //             0,
    //             0
    //         );
    //         Position memory position_b = Position(
    //             7,
    //             453755560,
    //             1892652375893125298235632798523846235738495234623495782352345325,
    //             true,
    //             0,
    //             0,
    //             true,
    //             200000000,
    //             50000000,
    //             150000000,
    //             50000000,
    //             49000000,
    //             0,
    //             0
    //         );

    //         uint[2] memory signature_a = [
    //             uint256(
    //                 1892652375893125298235632798523846235738495234623495782352345325
    //             ),
    //             uint256(
    //                 1892652375893125298235632798523846235738495234623495782352345325
    //             )
    //         ];

    //         uint[2] memory signature_b = [
    //             uint256(
    //                 1892652375893125298235632798523846235738495234623495782352345325
    //             ),
    //             uint256(
    //                 1892652375893125298235632798523846235738495234623495782352345325
    //             )
    //         ];

    //         emit PositionEscapeEventB(
    //             3,
    //             98765000,
    //             position_a,
    //             position_b,
    //             address(0x2b2eA7eC7e366666772DaAf496817c14b8c0Ae74),
    //             signature_a,
    //             signature_b
    //         );
    //     } else if (option == 3) {
    //         Position memory position_a = Position(
    //             7,
    //             453755560,
    //             1892652375893125298235632798523846235738495234623495782352345325,
    //             true,
    //             0,
    //             0,
    //             true,
    //             100000000,
    //             100000000,
    //             100000000,
    //             0,
    //             0,
    //             0,
    //             0
    //         );

    //         Note[] memory notes = new Note[](1);
    //         notes[0] = Note(
    //             1,
    //             1892652375893125298235632798523846235738495234623495782352345325,
    //             3332652375893125298235632798523846235738495234623495782352345325,
    //             3592681469,
    //             100000000,
    //             1892652375893125298235632798523846235738495234623495782352345325
    //         );
    //         OpenOrderFields memory openOrderFields_b = OpenOrderFields(
    //             100000000,
    //             55555,
    //             notes,
    //             Note(
    //                 7,
    //                 1892652375893125298235632798523846235738495234623495782352345325,
    //                 3332652375893125298235632798523846235738495234623495782352345325,
    //                 453755560,
    //                 100000000,
    //                 1892652375893125298235632798523846235738495234623495782352345325
    //             ),
    //             1892652375893125298235632798523846235738495234623495782352345325,
    //             true
    //         );

    //         uint[2] memory signature_a = [
    //             uint256(
    //                 1892652375893125298235632798523846235738495234623495782352345325
    //             ),
    //             uint256(
    //                 1892652375893125298235632798523846235738495234623495782352345325
    //             )
    //         ];

    //         uint[2] memory signature_b = [
    //             uint256(
    //                 1892652375893125298235632798523846235738495234623495782352345325
    //             ),
    //             uint256(
    //                 1892652375893125298235632798523846235738495234623495782352345325
    //             )
    //         ];

    //         emit PositionEscapeEventA(
    //             4,
    //             98765000,
    //             position_a,
    //             openOrderFields_b,
    //             address(0x2b2eA7eC7e366666772DaAf496817c14b8c0Ae74),
    //             signature_a,
    //             signature_b
    //         );
    //     }
    // }

    // * ====================================================================

    // // TODO: Make a proof with circom?
    // function forceEscapeAfterTimeout(
    //     Note[] calldata notes,
    //     uint256[2][] calldata noteAddresses,
    //     OrderTab[] calldata orderTabs,
    //     uint256[2][] calldata orderTabAddresses,
    //     Position[] calldata positions,
    //     uint256[2][] calldata positionAddresses
    // ) external nonReentrant {
    //     // verify that all the notes/tabs/positions exist in the state and verify the signatures

    //     uint32 escapeId = s_escapeCount;
    //     s_escapeCount++;

    //     uint256[] memory pubKeySum = new uint256[](2);
    //     pubKeySum[0] = 0;
    //     pubKeySum[1] = 0;

    //     for (uint i = 0; i < notes.length; i++) {
    //         Note calldata note = notes[i];
    //         uint256[2] calldata addr = noteAddresses[i];

    //         // TODO: Verify the merkle proof!

    //         require(note.addressX == addr[0], "Invalid address");
    //         require(
    //             EllipticCurve.isOnCurve(addr[0], addr[1], alpha, beta, P),
    //             "Invalid address"
    //         );

    //         (uint256 pkSumX, uint256 pkSumY) = EllipticCurve.ecAdd(
    //             pubKeySum[0],
    //             pubKeySum[1],
    //             addr[0],
    //             addr[1],
    //             alpha,
    //             P
    //         );
    //         pubKeySum[0] = pkSumX;
    //         pubKeySum[1] = pkSumY;

    //         s_escapeAmounts[escapeId][note.token] += note.amount;
    //     }

    //     for (uint i = 0; i < orderTabs.length; i++) {
    //         OrderTab calldata orderTab = orderTabs[i];
    //         uint256[2] calldata addr = orderTabAddresses[i];

    //         // TODO: Verify the merkle proof!

    //         require(orderTab.pub_key == addr[0], "Invalid address");
    //         require(
    //             EllipticCurve.isOnCurve(addr[0], addr[1], alpha, beta, P),
    //             "Invalid address"
    //         );

    //         (uint256 pkSumX, uint256 pkSumY) = EllipticCurve.ecAdd(
    //             pubKeySum[0],
    //             pubKeySum[1],
    //             addr[0],
    //             addr[1],
    //             alpha,
    //             P
    //         );
    //         pubKeySum[0] = pkSumX;
    //         pubKeySum[1] = pkSumY;

    //         s_escapeAmounts[escapeId][orderTab.base_token] += orderTab
    //             .base_amount;
    //         s_escapeAmounts[escapeId][orderTab.quote_token] += orderTab
    //             .quote_amount;
    //     }

    //     for (uint i = 0; i < positions.length; i++) {
    //         Position calldata position = positions[i];
    //         uint256[2] calldata addr = positionAddresses[i];

    //         // TODO: Verify the merkle proof!

    //         require(position.position_address == addr[0], "Invalid address");
    //         require(
    //             EllipticCurve.isOnCurve(addr[0], addr[1], alpha, beta, P),
    //             "Invalid address"
    //         );

    //         (uint256 pkSumX, uint256 pkSumY) = EllipticCurve.ecAdd(
    //             pubKeySum[0],
    //             pubKeySum[1],
    //             addr[0],
    //             addr[1],
    //             alpha,
    //             P
    //         );
    //         pubKeySum[0] = pkSumX;
    //         pubKeySum[1] = pkSumY;

    //         s_escapeAmounts[escapeId][position.synthetic_token] += position
    //             .position_size;
    //     }

    //     // TODO: Verify the signature

    //     s_successfulEscapes[msg.sender][escapeId] = true;
    // }
}
