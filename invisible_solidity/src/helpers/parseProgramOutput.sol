// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./programOutputStructs.sol";

contract ProgramOutputParser {
    function parseProgramOutput(
        uint256[] calldata cairoProgramOutput
    )
        internal
        view
        returns (
            GlobalDexState memory dexState,
            AccumulatedHashesOutput[] memory hashes,
            DepositTransactionOutput[] memory deposits,
            WithdrawalTransactionOutput[] memory withdrawals
        )
    {
        dexState = parseDexState(cairoProgramOutput[:14]);

        cairoProgramOutput = cairoProgramOutput[14:];
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

        return (dexState, hashes, deposits, withdrawals);
    }

    // * ------------------------------------------------------
    function parseDexState(
        uint256[] calldata dexStateArr
    ) private pure returns (GlobalDexState memory) {
        uint64 txBatchId = uint64(dexStateArr[0]); // todo: change to txBatchId (and verify against s_txBatchId)
        uint256 initStateRoot = dexStateArr[1];
        uint256 finalStateRoot = dexStateArr[2];

        uint256 batchedInfo1 = dexStateArr[3];
        uint8 stateTreeDepth = uint8(batchedInfo1 >> 160);
        uint32 globalExpirationTimestamp = uint32(batchedInfo1 >> 128);
        uint128 configCode = uint128(batchedInfo1);

        uint256 batchedInfo2 = dexStateArr[4];
        uint32 nDeposits = uint32(batchedInfo2 >> 160);
        uint32 nWithdrawals = uint32(batchedInfo2 >> 128);
        // uint32 nOutputPositions = uint32(batchedInfo2[2]>>96);
        // uint32 nEmptyPositions = uint32(batchedInfo2[3] >>64);
        // uint32 nOutputNotes = uint32(batchedInfo2[4] >> 32);
        // uint32 nZeroNotes = uint32(batchedInfo2[5]);

        GlobalDexState memory dexState = GlobalDexState({
            configCode: configCode,
            initStateRoot: initStateRoot,
            finalStateRoot: finalStateRoot,
            stateTreeDepth: stateTreeDepth,
            globalExpirationTimestamp: globalExpirationTimestamp,
            nDeposits: nDeposits,
            nWithdrawals: nWithdrawals
            // nOutputPositions: nOutputPositions,
            // nEmptyPositions: nEmptyPositions,
            // nOutputNotes: nOutputNotes,
            // nZeroNotes: nZeroNotes
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
}
