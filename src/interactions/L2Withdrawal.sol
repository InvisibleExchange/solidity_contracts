// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../storage/InteractionsStorage.sol";

import "./Base.sol";

// * =================================================================================================
// * =================================================================================================

abstract contract L2Withdrawal is WithdrawalBase, L2InteractionsStorage {
    function processAccumulatedWithdrawalOutputs(
        WithdrawalRequest[] calldata withdrawals,
        uint64 txBatchId
    ) internal {
        for (uint256 i = 0; i < withdrawals.length; i++) {
            address tokenAddress = getTokenAddress(withdrawals[i].tokenId);
            if (withdrawals[i].amount == 0) continue;

            uint256 amountScaled = scaleUp(
                withdrawals[i].amount,
                withdrawals[i].tokenId
            );

            _executeWithdrawal(
                tokenAddress,
                withdrawals[i].recipient,
                amountScaled,
                0 // TODO: Add gas fee
            );
        }

        emit ProcessedWithdrawals(block.timestamp, txBatchId);
    }

    function _getWithdrawalHash(
        uint32 chainId,
        uint32 tokenId,
        uint64 amount,
        address recipient_
    ) internal pure returns (bytes32) {
        uint256 batchedWithdrawalInfo = ((uint(chainId) * 2 ** 32) +
            uint(tokenId)) *
            2 ** 32 +
            uint(amount);
        uint256 recipient = uint256(uint160(recipient_));

        return keccak256(abi.encodePacked([batchedWithdrawalInfo, recipient]));
    }
}
