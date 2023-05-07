// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./programOutputStructs.sol";

contract ProgramOutputParser {
    uint64 s_txBatchId;
    uint256 s_stateRoot;
    uint256 s_perpetualStateRoot;

    function parseProgramOutput(uint256[] calldata cairoProgramOutput)
        internal
        view
        returns (
            GlobalDexState memory dexState,
            DepositTransactionOutput[] memory deposits,
            WithdrawalTransactionOutput[] memory withdrawals
        )
    {
        dexState = parseDexState(cairoProgramOutput[:14]);

        // Todo:
        // assert(dexState.txBatchId == s_txBatchId);
        // assert(dexState.initStateRoot == s_stateRoot);
        // assert(dexState.initPerpStateRoot == s_perpetualStateRoot);

        deposits = parseDepositsArray(
            cairoProgramOutput[14:14 + dexState.nDeposits * 2]
        );

        withdrawals = parseWithdrawalsArray(
            cairoProgramOutput[14 + dexState.nDeposits * 2:14 +
                dexState.nDeposits *
                2 +
                dexState.nWithdrawals *
                2]
        );

        return (dexState, deposits, withdrawals);
    }

    function parseDexState(uint256[] calldata dexStateArr)
        private
        pure
        returns (GlobalDexState memory)
    {
        uint64 txBatchId = uint64(dexStateArr[0]); // todo: change to txBatchId (and verify against s_txBatchId)
        uint256 initStateRoot = dexStateArr[1];
        uint256 finalStateRoot = dexStateArr[2];
        uint256 initPerpStateRoot = dexStateArr[3];
        uint256 finalPerpStateRoot = dexStateArr[4];
        uint32 stateTreeDepth = uint32(dexStateArr[5]);
        uint32 perpTreeDepth = uint32(dexStateArr[6]);
        uint32 globalExpirationTimestamp = uint32(dexStateArr[7]);
        uint32 nDeposits = uint32(dexStateArr[8]);
        uint32 nWithdrawals = uint32(dexStateArr[9]);
        uint32 nOutputPositions = uint32(dexStateArr[10]);
        uint32 nEmptyPositions = uint32(dexStateArr[11]);
        uint32 nOutputNotes = uint32(dexStateArr[12]);
        uint32 nZeroNotes = uint32(dexStateArr[13]);

        GlobalDexState memory dexState = GlobalDexState({
            txBatchId: txBatchId,
            initStateRoot: initStateRoot,
            finalStateRoot: finalStateRoot,
            initPerpStateRoot: initPerpStateRoot,
            finalPerpStateRoot: finalPerpStateRoot,
            stateTreeDepth: stateTreeDepth,
            perpTreeDepth: perpTreeDepth,
            globalExpirationTimestamp: globalExpirationTimestamp,
            nDeposits: nDeposits,
            nWithdrawals: nWithdrawals,
            nOutputPositions: nOutputPositions,
            nEmptyPositions: nEmptyPositions,
            nOutputNotes: nOutputNotes,
            nZeroNotes: nZeroNotes
        });

        return dexState;
    }

    function parseDepositsArray(uint256[] calldata depositsArr)
        private
        pure
        returns (DepositTransactionOutput[] memory)
    {
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

    function parseWithdrawalsArray(uint256[] calldata withdrawalsArr)
        private
        pure
        returns (WithdrawalTransactionOutput[] memory)
    {
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

    // -------------------------------------------------------------------------

    function uncompressDepositOutput(DepositTransactionOutput memory deposit)
        internal
        pure
        returns (
            uint64 depositId,
            uint64 tokenId,
            uint64 amount,
            uint256 depositPubKey
        )
    {
        depositId = uint64(deposit.batchedDepositInfo >> 128);
        tokenId = uint64(deposit.batchedDepositInfo >> 64);
        amount = uint64(deposit.batchedDepositInfo);
        depositPubKey = deposit.pubKey;
    }

    function uncompressWithdrawalOutput(
        WithdrawalTransactionOutput memory withdrawal
    )
        internal
        pure
        returns (
            uint64 tokenId,
            uint64 amount,
            address recipient
        )
    {
        tokenId = uint64(withdrawal.batchedWithdrawalInfo >> 64);
        amount = uint64(withdrawal.batchedWithdrawalInfo);
        recipient = withdrawal.recipient;
    }
}
