// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../libraries/ProgramOutputParser.sol";

import "./Base.sol";

// * =================================================================================================
// * =================================================================================================

abstract contract L1Withdrawal is WithdrawalBase {
    function processBatchWithdrawalOutputs(
        WithdrawalTransactionOutput[] memory withdrawalOutputs,
        uint64 txBatchId
    ) internal {
        // ? the withdrawals should be grouped by token to make it easier to process

        // ? cache the lates token info (token, address, gas fee, etc.) after
        // ? each withdrawal to save on gas fees. (since the withdrawals are grouped by token)
        uint32 currentToken;
        address currentTokenAddress;
        uint256 gasFee;
        uint64 thisChainId = getChainId();
        for (uint256 i = 0; i < withdrawalOutputs.length; i++) {
            WithdrawalTransactionOutput
                memory withdrawalOutput = withdrawalOutputs[i];

            (
                uint32 chainId,
                uint32 tokenId,
                uint64 amount,
                address recipient
            ) = ProgramOutputParser.uncompressWithdrawalOutput(
                    withdrawalOutput
                );

            if (amount == 0) continue;

            if (thisChainId != chainId) continue;

            // ? Get the cached gasFee or recalculate it if the token has changed
            if (tokenId != currentToken) {
                currentToken = tokenId;
                if (tokenId == ETH_ID) {
                    currentTokenAddress = address(0);

                    gasFee = gasFeeForETHWithdrawal();
                } else {
                    currentTokenAddress = getTokenAddress(currentToken);

                    gasFee = gasFeeForERCWithdrawal(currentTokenAddress);
                }
            }

            uint256 amountScaled = scaleUp(amount, tokenId);

            _executeWithdrawal(
                currentTokenAddress,
                recipient,
                amountScaled,
                gasFee
            );
        }

        emit ProcessedWithdrawals(block.timestamp, txBatchId);
    }
}
