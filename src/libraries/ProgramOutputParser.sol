// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../utils/ProgramOutputStructs.sol";

import "forge-std/console.sol";

library ProgramOutputParser {
    function parseProgramOutput(
        uint256[] calldata cairoProgramOutput
    )
        internal
        view
        returns (
            GlobalDexState memory dexState,
            AccumulatedHashesOutput[] memory hashes,
            DepositTransactionOutput[] memory deposits,
            WithdrawalTransactionOutput[] memory withdrawals,
            MMRegistrationOutput[] memory registrations,
            EscapeOutput[] memory escapes,
            PositionEscapeOutput[] memory positionEscapes
        )
    {
        dexState = parseDexState(cairoProgramOutput[:5]);

        cairoProgramOutput = cairoProgramOutput[5:];
        GlobalConfig memory config = parseGlobalConfig(cairoProgramOutput);

        // ? 1 + 3*assets_len + 5*synthetic_assets_len + observers_len + chain_ids_len
        uint32 configLen = 1 +
            3 *
            config.assetsLen +
            5 *
            config.syntheticAssetsLen +
            config.observersLen +
            config.chainIdsLen;

        cairoProgramOutput = cairoProgramOutput[configLen:];
        hashes = parseAccumulatedHashes(
            cairoProgramOutput[:config.chainIdsLen * 3]
        );

        cairoProgramOutput = cairoProgramOutput[config.chainIdsLen * 3:];
        deposits = parseDepositsArray(
            cairoProgramOutput[:dexState.nDeposits * 2]
        );

        cairoProgramOutput = cairoProgramOutput[dexState.nDeposits * 2:];
        withdrawals = parseWithdrawalsArray(
            cairoProgramOutput[:dexState.nWithdrawals * 2]
        );

        cairoProgramOutput = cairoProgramOutput[dexState.nWithdrawals * 2:];
        registrations = parseMMRegistrationsArray(
            cairoProgramOutput[:dexState.nMMRegistrations * 2]
        );

        cairoProgramOutput = cairoProgramOutput[dexState.nMMRegistrations * 2:];
        escapes = parseEscapesArray(
            cairoProgramOutput[:(dexState.nNoteEscapes + dexState.nTabEscapes) *
                4]
        );

        cairoProgramOutput = cairoProgramOutput[(dexState.nNoteEscapes +
            dexState.nTabEscapes) * 4:];
        positionEscapes = parsePositionEscapesArray(
            cairoProgramOutput[:dexState.nPositionEscapes * 6]
        );
    }

    // * ------------------------------------------------------
    function parseDexState(
        uint256[] calldata dexStateArr
    ) private pure returns (GlobalDexState memory) {
        uint256 initStateRoot = dexStateArr[0];
        uint256 finalStateRoot = dexStateArr[1];

        uint256 batchedInfo = dexStateArr[2];
        uint8 stateTreeDepth = uint8(batchedInfo >> 64);
        uint32 globalExpirationTimestamp = uint32(batchedInfo >> 32);
        uint32 txBatchId = uint32(batchedInfo);

        batchedInfo = dexStateArr[3];
        uint32 nDeposits = uint32(batchedInfo >> 192);
        uint32 nWithdrawals = uint32(batchedInfo >> 160);
        uint32 nMMRegistrations = uint32(batchedInfo >> 128);

        // & 3: | n_zero_indexes (32 bits) | n_note_escape_outputs (32 bits) | n_tab_escape_outputs (32 bits) |  n_position_escape_outputs (32 bits) |
        batchedInfo = dexStateArr[4];
        uint32 nNoteEscapes = uint32(batchedInfo >> 64);
        uint32 nTabEscapes = uint32(batchedInfo >> 32);
        uint32 nPositionEscapes = uint32(batchedInfo);

        GlobalDexState memory dexState = GlobalDexState({
            txBatchId: txBatchId,
            initStateRoot: initStateRoot,
            finalStateRoot: finalStateRoot,
            stateTreeDepth: stateTreeDepth,
            globalExpirationTimestamp: globalExpirationTimestamp,
            nDeposits: nDeposits,
            nWithdrawals: nWithdrawals,
            nMMRegistrations: nMMRegistrations,
            nNoteEscapes: nNoteEscapes,
            nPositionEscapes: nPositionEscapes,
            nTabEscapes: nTabEscapes
        });

        return dexState;
    }

    // * ------------------------------------------------------
    function parseGlobalConfig(
        uint256[] calldata configArr
    ) private pure returns (GlobalConfig memory) {
        uint256 batchedInfo = configArr[0];

        uint32 collateralToken = uint32(batchedInfo >> 136);
        uint8 leverageDecimals = uint8(batchedInfo >> 128);
        uint32 assetsLen = uint32(batchedInfo >> 96);
        uint32 syntheticAssetsLen = uint32(batchedInfo >> 64);
        uint32 observersLen = uint32(batchedInfo >> 32);
        uint32 chainIdsLen = uint32(batchedInfo);

        GlobalConfig memory config = GlobalConfig({
            collateralToken: collateralToken,
            leverageDecimals: leverageDecimals,
            assetsLen: assetsLen,
            syntheticAssetsLen: syntheticAssetsLen,
            observersLen: observersLen,
            chainIdsLen: chainIdsLen
        });

        return config;
    }

    // * ------------------------------------------------------
    function parseAccumulatedHashes(
        uint256[] calldata hashesArr
    ) private pure returns (AccumulatedHashesOutput[] memory) {
        uint256 nHashes = hashesArr.length / 3;
        AccumulatedHashesOutput[] memory hashes = new AccumulatedHashesOutput[](
            nHashes
        );

        for (uint256 i = 0; i < hashesArr.length; i += 3) {
            uint32 chainId = uint32(hashesArr[i]);
            uint256 depositHash = hashesArr[i + 1];
            uint256 withdrawalHash = hashesArr[i + 2];

            hashes[i / 3] = AccumulatedHashesOutput({
                chainId: chainId,
                depositHash: depositHash,
                withdrawalHash: withdrawalHash
            });
        }

        return hashes;
    }

    // * ------------------------------------------------------
    function parseDepositsArray(
        uint256[] calldata depositsArr
    ) private pure returns (DepositTransactionOutput[] memory) {
        uint256 nDeposits = depositsArr.length / 2;
        DepositTransactionOutput[]
            memory deposits = new DepositTransactionOutput[](nDeposits);

        for (uint256 i = 0; i < depositsArr.length; i += 2) {
            uint256 batchedDepositInfo = depositsArr[i];
            uint256 pubKey = depositsArr[i + 1];

            deposits[i / 2] = DepositTransactionOutput({
                batchedDepositInfo: batchedDepositInfo,
                pubKey: pubKey
            });
        }

        return deposits;
    }

    // * ------------------------------------------------------
    function parseWithdrawalsArray(
        uint256[] calldata withdrawalsArr
    ) private pure returns (WithdrawalTransactionOutput[] memory) {
        uint256 nWithdrawals = withdrawalsArr.length / 2;
        WithdrawalTransactionOutput[]
            memory withdrawals = new WithdrawalTransactionOutput[](
                nWithdrawals
            );

        for (uint256 i = 0; i < withdrawalsArr.length; i += 2) {
            uint256 withdrawalInfo = withdrawalsArr[i];
            address recipient = address(uint160(withdrawalsArr[i + 1]));

            withdrawals[i / 2] = WithdrawalTransactionOutput({
                batchedWithdrawalInfo: withdrawalInfo,
                recipient: recipient
            });
        }

        return withdrawals;
    }

    // * ------------------------------------------------------
    function parseMMRegistrationsArray(
        uint256[] calldata registrationsArr
    ) private pure returns (MMRegistrationOutput[] memory) {
        uint256 nRegistrations = registrationsArr.length / 2;
        MMRegistrationOutput[]
            memory registrations = new MMRegistrationOutput[](nRegistrations);

        for (uint256 i = 0; i < registrationsArr.length; i += 2) {
            uint256 registrationInfo = registrationsArr[i];
            uint256 mmAddress = uint256(registrationsArr[i + 1]);

            registrations[i / 2] = MMRegistrationOutput({
                batchedRegistrationInfo: registrationInfo,
                mmAddress: mmAddress
            });
        }

        return registrations;
    }

    // * ------------------------------------------------------
    function parseEscapesArray(
        uint256[] calldata escapeArr
    ) private pure returns (EscapeOutput[] memory) {
        uint256 nEscapes = escapeArr.length / 2;
        EscapeOutput[] memory escapes = new EscapeOutput[](nEscapes);

        for (uint256 i = 0; i < escapeArr.length; i += 2) {
            uint256 batchedEscapeInfo = escapeArr[i];
            uint256 escapeMessageHash = escapeArr[i + 1];
            uint256 signatureR = escapeArr[i + 2];
            uint256 signatureS = escapeArr[i + 3];

            escapes[i / 2] = EscapeOutput(
                batchedEscapeInfo,
                escapeMessageHash,
                signatureR,
                signatureS
            );
        }

        return escapes;
    }

    // * ------------------------------------------------------
    function parsePositionEscapesArray(
        uint256[] calldata escapeArr
    ) private pure returns (PositionEscapeOutput[] memory) {
        uint256 nEscapes = escapeArr.length / 6;
        PositionEscapeOutput[] memory escapes = new PositionEscapeOutput[](
            nEscapes
        );

        for (uint256 i = 0; i < escapeArr.length; i += 6) {
            uint256 batchedEscapeInfo = escapeArr[i];
            uint256 escapeMessageHash = escapeArr[i + 1];
            uint256 signature_AR = escapeArr[i + 2];
            uint256 signature_AS = escapeArr[i + 3];
            uint256 signature_BR = escapeArr[i + 4];
            uint256 signature_BS = escapeArr[i + 5];

            escapes[i / 6] = PositionEscapeOutput(
                batchedEscapeInfo,
                escapeMessageHash,
                signature_AR,
                signature_AS,
                signature_BR,
                signature_BS
            );
        }

        return escapes;
    }

    // * —————————————————————————————————————————————————————————————————————
    // * —————————————————————————————————————————————————————————————————————
    // * ------------------------------------------------------
    function uncompressDepositOutput(
        DepositTransactionOutput memory deposit
    )
        internal
        pure
        returns (
            uint64 depositId,
            uint32 tokenId,
            uint64 amount,
            uint256 depositPubKey
        )
    {
        depositId = uint64(deposit.batchedDepositInfo >> 96);
        tokenId = uint32(deposit.batchedDepositInfo >> 64);
        amount = uint64(deposit.batchedDepositInfo);
        depositPubKey = deposit.pubKey;
    }

    function uncompressWithdrawalOutput(
        WithdrawalTransactionOutput memory withdrawal
    )
        internal
        pure
        returns (
            uint32 chainId,
            uint32 tokenId,
            uint64 amount,
            address recipient
        )
    {
        chainId = uint32(withdrawal.batchedWithdrawalInfo >> 96);
        tokenId = uint32(withdrawal.batchedWithdrawalInfo >> 64);
        amount = uint64(withdrawal.batchedWithdrawalInfo);
        recipient = withdrawal.recipient;
    }

    function uncompressRegistrationOutput(
        MMRegistrationOutput memory registration
    )
        internal
        pure
        returns (
            bool isPerp,
            uint32 vlpToken,
            uint64 maxVlpSupply,
            uint256 mmAddress
        )
    {
        // & batched_registration_info format: | is_perp (1 bits) | vlp_token (32 bits) | max_vlp_supply (64 bits) |

        isPerp = registration.batchedRegistrationInfo >> 96 == 1;
        vlpToken = uint32(registration.batchedRegistrationInfo >> 64);
        maxVlpSupply = uint64(registration.batchedRegistrationInfo);
        mmAddress = registration.mmAddress;
    }

    function uncompressEscapeOutput(
        EscapeOutput memory escapeOutput
    )
        internal
        pure
        returns (
            bool is_valid,
            EscapeType escape_type,
            uint32 escape_id,
            uint256 escape_message_hash,
            uint256 signature_r,
            uint256 signature_s
        )
    {
        // & | escape_id (32 bits) | is_valid (8 bits) | escape_type (8 bits) |
        escape_type;
        uint8 escapeType = uint8(escapeOutput.batched_escape_info);
        if (escapeType == 0) {
            escape_type = EscapeType.Note;
        } else if (escapeType == 1) {
            escape_type = EscapeType.OrderTab;
        }

        is_valid = uint8(escapeOutput.batched_escape_info >> 8) == 1;
        escape_id = uint32(escapeOutput.batched_escape_info >> 16);

        escape_message_hash = escapeOutput.escape_message_hash;
        signature_r = escapeOutput.signature_r;
        signature_s = escapeOutput.signature_s;
    }

    function uncompressEscapeOutput(
        PositionEscapeOutput memory escapeOutput
    )
        internal
        pure
        returns (
            bool is_valid,
            uint32 escape_id,
            uint64 escape_value,
            uint256 escape_message_hash,
            uint256 signature_a_r,
            uint256 signature_a_s,
            uint256 signature_b_r,
            uint256 signature_b_s
        )
    {
        // & escape_value (64 bits) | escape_id (32 bits) | is_valid (8 bits) |

        is_valid = uint8(escapeOutput.batched_escape_info) == 1;
        escape_id = uint32(escapeOutput.batched_escape_info >> 8);
        escape_value = uint64(escapeOutput.batched_escape_info >> 40);

        escape_message_hash = escapeOutput.escape_message_hash;
        signature_a_r = escapeOutput.signature_a_r;
        signature_a_s = escapeOutput.signature_a_s;
        signature_b_r = escapeOutput.signature_b_r;
        signature_b_s = escapeOutput.signature_b_s;
    }
}
