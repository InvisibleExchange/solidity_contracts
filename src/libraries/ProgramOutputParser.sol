// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../utils/ProgramOutputStructs.sol";

library ProgramOutputParser {
    function parseProgramOutput(
        uint256[] calldata cairoProgramOutput
    )
        internal
        pure
        returns (
            GlobalDexState memory dexState,
            AccumulatedHashesOutput[] memory hashes,
            DepositTransactionOutput[] memory deposits,
            WithdrawalTransactionOutput[] memory withdrawals,
            OnChainMMActionOutput[] memory registrationsArr,
            OnChainMMActionOutput[] memory addLiquidityArr,
            OnChainMMActionOutput[] memory removeLiquidityArr,
            OnChainMMActionOutput[] memory closeMMArr,
            EscapeOutput[] memory escapes,
            PositionEscapeOutput[] memory positionEscapes
        )
    {
        dexState = parseDexState(cairoProgramOutput[:4]);

        cairoProgramOutput = cairoProgramOutput[4:];
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
        (
            registrationsArr,
            addLiquidityArr,
            removeLiquidityArr,
            closeMMArr
        ) = parseOnchainMMActionsArray(
            cairoProgramOutput[:dexState.nOnchainMMActions * 3]
        );

        cairoProgramOutput = cairoProgramOutput[dexState.nOnchainMMActions *
            3:];
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

    // * ===========================================================================================================
    function parseDexState(
        uint256[] calldata dexStateArr
    ) private pure returns (GlobalDexState memory) {
        uint256 initStateRoot = dexStateArr[0];
        uint256 finalStateRoot = dexStateArr[1];

        uint256 batchedInfo = dexStateArr[2];
        uint8 stateTreeDepth = uint8(batchedInfo >> 64);
        uint32 globalExpirationTimestamp = uint32(batchedInfo >> 32);
        uint32 txBatchId = uint32(batchedInfo);

        // & n_output_notes (32 bits) | n_output_positions (16 bits) | n_output_tabs (16 bits) | n_zero_indexes (32 bits) | n_deposits (16 bits) | n_withdrawals (16 bits) |
        // & n_onchain_mm_actions (16 bits) | n_note_escapes (16 bits) | n_position_escapes (16 bits) | n_tab_escapes (16 bits) |
        batchedInfo = dexStateArr[3];
        uint16 nDeposits = uint16(batchedInfo >> 80);
        uint16 nWithdrawals = uint16(batchedInfo >> 64);
        uint16 nOnchainMMActions = uint16(batchedInfo >> 48);
        uint16 nNoteEscapes = uint16(batchedInfo >> 32);
        uint16 nTabEscapes = uint16(batchedInfo >> 16);
        uint16 nPositionEscapes = uint16(batchedInfo);

        GlobalDexState memory dexState = GlobalDexState({
            txBatchId: txBatchId,
            initStateRoot: initStateRoot,
            finalStateRoot: finalStateRoot,
            stateTreeDepth: stateTreeDepth,
            globalExpirationTimestamp: globalExpirationTimestamp,
            nDeposits: nDeposits,
            nWithdrawals: nWithdrawals,
            nOnchainMMActions: nOnchainMMActions,
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
    function parseOnchainMMActionsArray(
        uint256[] calldata mmActionOutputs
    )
        private
        pure
        returns (
            OnChainMMActionOutput[] memory registrationsArr,
            OnChainMMActionOutput[] memory addLiquidityArr,
            OnChainMMActionOutput[] memory removeLiquidityArr,
            OnChainMMActionOutput[] memory closeMMArr
        )
    {
        uint32 nRegistrations = 0;
        uint32 nAddLiq = 0;
        uint32 nRemoveLiq = 0;
        uint32 nCloseMm = 0;
        for (uint256 idx = 0; idx < mmActionOutputs.length; idx += 3) {
            uint8 actionType = uint8(mmActionOutputs[idx + 2]);

            if (actionType == 0) {
                nRegistrations += 1;
            } else if (actionType == 1) {
                nAddLiq += 1;
            } else if (actionType == 2) {
                nRemoveLiq += 1;
            } else if (actionType == 3) {
                nCloseMm += 1;
            }
        }

        registrationsArr = new OnChainMMActionOutput[](nRegistrations);
        addLiquidityArr = new OnChainMMActionOutput[](nAddLiq);
        removeLiquidityArr = new OnChainMMActionOutput[](nRemoveLiq);
        closeMMArr = new OnChainMMActionOutput[](nCloseMm);

        for (uint256 idx = 0; idx < mmActionOutputs.length; idx += 3) {
            uint256 mmPositionAddress = mmActionOutputs[idx];
            uint256 depositor = mmActionOutputs[idx + 1];
            uint256 batchedActionInfo = uint256(mmActionOutputs[idx + 2]);

            OnChainMMActionOutput memory actionOutput = OnChainMMActionOutput({
                mmPositionAddress: mmPositionAddress,
                depositor: depositor,
                batchedActionInfo: batchedActionInfo
            });

            uint8 actionType = uint8(batchedActionInfo);

            if (actionType == 0) {
                registrationsArr[
                    registrationsArr.length - nRegistrations
                ] = actionOutput;
                nRegistrations -= 1;
            } else if (actionType == 1) {
                addLiquidityArr[
                    addLiquidityArr.length - nAddLiq
                ] = actionOutput;
                nAddLiq -= 1;
            } else if (actionType == 2) {
                removeLiquidityArr[
                    removeLiquidityArr.length - nRemoveLiq
                ] = actionOutput;
                nRemoveLiq -= 1;
            } else if (actionType == 3) {
                closeMMArr[closeMMArr.length - nCloseMm] = actionOutput;
                nCloseMm -= 1;
            }
        }
    }

    // * ------------------------------------------------------
    function parseEscapesArray(
        uint256[] calldata escapeArr
    ) private pure returns (EscapeOutput[] memory) {
        uint256 nEscapes = escapeArr.length / 4;
        EscapeOutput[] memory escapes = new EscapeOutput[](nEscapes);

        for (uint256 i = 0; i < escapeArr.length; i += 4) {
            uint256 batchedEscapeInfo = escapeArr[i];
            uint256 escapeMessageHash = escapeArr[i + 1];
            uint256 signatureR = escapeArr[i + 2];
            uint256 signatureS = escapeArr[i + 3];

            escapes[i / 4] = EscapeOutput(
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
            address recipient = address(uint160(escapeArr[i + 1]));
            uint256 escapeMessageHash = escapeArr[i + 2];
            uint256 signature_AR = escapeArr[i + 3];
            uint256 signature_AS = escapeArr[i + 4];
            uint256 signature_BR = escapeArr[i + 5];
            uint256 signature_BS = escapeArr[i + 6];

            escapes[i / 7] = PositionEscapeOutput(
                batchedEscapeInfo,
                recipient,
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

    // * ------------------------------------------------------

    function uncompressRegistrationOutput(
        OnChainMMActionOutput memory output
    )
        internal
        pure
        returns (
            uint32 vlpToken,
            uint64 maxVlpSupply,
            uint64 vlpAmount,
            uint256 mmAddress
        )
    {
        // & batched_registration_info format: | vlp_token (32 bits) | max_vlp_supply (64 bits) | vlp_amount (64 bits) | action_type (8 bits) |

        vlpToken = uint32(output.batchedActionInfo >> 136);
        maxVlpSupply = uint64(output.batchedActionInfo >> 72);
        vlpAmount = uint64(output.batchedActionInfo >> 8);
        mmAddress = output.mmPositionAddress;
    }

    function uncompressAddLiquidityOutput(
        OnChainMMActionOutput memory addLiq
    )
        internal
        pure
        returns (
            uint64 initialAmount,
            uint64 vlpAmount,
            uint256 mmAddress,
            address depositor
        )
    {
        // & batched_add_liq_info format: | usdcAmount (64 bits) | vlp_amount (64 bits) | action_type (8 bits) |

        initialAmount = uint64(addLiq.batchedActionInfo >> 72);
        vlpAmount = uint64(addLiq.batchedActionInfo >> 8);
        depositor = address(uint160(addLiq.depositor));
        mmAddress = addLiq.mmPositionAddress;
    }

    function uncompressRemoveLiquidityOutput(
        OnChainMMActionOutput memory removeLiq
    )
        internal
        pure
        returns (
            uint64 initialAmount,
            uint64 vlpAmount,
            uint64 returnCollateral,
            uint256 mmAddress,
            address depositor
        )
    {
        // & batched_remove_liq_info format:  | initialValue (64 bits) | vlpAmount (64 bits) | returnAmount (64 bits) | action_type (8 bits) |

        initialAmount = uint64(removeLiq.batchedActionInfo >> 136);
        vlpAmount = uint64(removeLiq.batchedActionInfo >> 72);
        returnCollateral = uint64(removeLiq.batchedActionInfo >> 8);

        depositor = address(uint160(removeLiq.depositor));
        mmAddress = removeLiq.mmPositionAddress;
    }

    function uncompressCloseMMOutput(
        OnChainMMActionOutput memory closeMM
    )
        internal
        pure
        returns (
            uint64 initialValueSum,
            uint64 vlpAmountSum,
            uint64 returnCollateral,
            uint256 mmAddress
        )
    {
        // & batched_remove_liq_info format:  | initialValue (64 bits) | vlpAmount (64 bits) | returnAmount (64 bits) | action_type (8 bits) |

        initialValueSum = uint64(closeMM.batchedActionInfo >> 136);
        vlpAmountSum = uint64(closeMM.batchedActionInfo >> 72);
        returnCollateral = uint64(closeMM.batchedActionInfo >> 8);

        mmAddress = closeMM.mmPositionAddress;
    }

    // * ------------------------------------------------------

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
            address recipient,
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

        recipient = escapeOutput.recipient;
        escape_message_hash = escapeOutput.escape_message_hash;
        signature_a_r = escapeOutput.signature_a_r;
        signature_a_s = escapeOutput.signature_a_s;
        signature_b_r = escapeOutput.signature_b_r;
        signature_b_s = escapeOutput.signature_b_s;
    }
}
