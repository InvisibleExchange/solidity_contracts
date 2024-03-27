// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../libraries/ProgramOutputParser.sol";

import "./Base.sol";

// * =================================================================================================
// * =================================================================================================

event TestWithdrawal(
    bool isAutomatic,
    uint32 chainId,
    uint32 tokenId,
    uint64 amount,
    address recipient
);

abstract contract L1Withdrawal is WithdrawalBase {
    function processBatchWithdrawalOutputs(
        WithdrawalTransactionOutput[] memory withdrawalOutputs,
        uint64 txBatchId
    ) internal {
        uint64 thisChainId = getChainId();
        for (uint256 i = 0; i < withdrawalOutputs.length; i++) {
            WithdrawalTransactionOutput
                memory withdrawalOutput = withdrawalOutputs[i];

            (
                bool isAutomatic,
                uint32 chainId,
                uint32 tokenId,
                uint64 amount,
                address recipient
            ) = ProgramOutputParser.uncompressWithdrawalOutput(
                    withdrawalOutput
                );

            emit TestWithdrawal(
                isAutomatic,
                chainId,
                tokenId,
                amount,
                recipient
            );

            if (amount == 0) continue;

            if (thisChainId != chainId) continue;

            address tokenAddress = getTokenAddress(tokenId);

            uint256 amountScaled = scaleUp(amount, tokenId);

            if (isAutomatic) {
                _executeAutomaticWithdrawal(
                    tokenAddress,
                    recipient,
                    amountScaled
                );
            } else {
                _registerManualWithdrawal(
                    tokenAddress,
                    recipient,
                    amountScaled
                );
            }
        }

        emit ProcessedWithdrawals(block.timestamp, txBatchId);
    }
}
