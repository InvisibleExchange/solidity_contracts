// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../libraries/ProgramOutputParser.sol";

import "./Base.sol";

abstract contract L1Deposit is DepositBase {
    function updatePendingDeposits(
        DepositTransactionOutput[] memory depositOutputs,
        uint64 txBatchId
    ) internal {
        for (uint256 i = 0; i < depositOutputs.length; i++) {
            DepositTransactionOutput memory depositOutput = depositOutputs[i];
            (
                uint64 depositId,
                uint32 tokenId,
                uint64 depositAmount,
                uint256 depositPubKey
            ) = ProgramOutputParser.uncompressDepositOutput(depositOutput);

            require(
                s_pendingDeposits[depositPubKey][tokenId] >= depositAmount,
                "An invalid deposit was executed offchain"
            );
            s_pendingDeposits[depositPubKey][tokenId] -= depositAmount;
        }

        emit UpdatedPendingDepositsEvent(block.timestamp, txBatchId);

        // ? After updating the deposits update the cancellations as well
        cancelDeposits();
    }

    // ----------------------------------------------------------------------------
    // * cancellations
    function _startCancelDeposit(
        address tokenAddress,
        uint256 starkKey
    ) internal {
        require(starkKey < 2 ** 251 + 17 * 2 ** 192 + 1, "Invalid stark key");

        require(msg.sender != address(0), "msg.sender can't be 0");

        // ? Get the token id and scale the amount
        uint32 tokenId = getTokenId(tokenAddress);

        uint64 pendingAmount = s_pendingDeposits[starkKey][tokenId];
        if (pendingAmount == 0) return;

        s_depositCencelations.push(
            DepositCancellation(msg.sender, starkKey, tokenId, block.timestamp)
        );

        emit DepositCancelEvent(starkKey, tokenAddress, block.timestamp);
    }

    function cancelDeposits() private {
        if (s_depositCencelations.length <= 0) return;

        for (uint256 i = 0; i < s_depositCencelations.length; i++) {
            DepositCancellation storage cancellation = s_depositCencelations[i];
            uint64 pendingAmount = s_pendingDeposits[cancellation.pubKey][
                cancellation.tokenId
            ];

            if (pendingAmount == 0) continue;

            uint256 refundAmount = scaleUp(pendingAmount, cancellation.tokenId);

            s_pendingWithdrawals[cancellation.depositor][
                getTokenAddress(cancellation.tokenId)
            ] += refundAmount;
        }

        delete s_depositCencelations;
    }
}
