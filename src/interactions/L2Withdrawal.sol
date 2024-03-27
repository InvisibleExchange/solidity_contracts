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

            if (withdrawals[i].isAutomatic) {
                _executeAutomaticWithdrawal(
                    tokenAddress,
                    withdrawals[i].recipient,
                    amountScaled
                );
            } else {
                _registerManualWithdrawal(
                    tokenAddress,
                    withdrawals[i].recipient,
                    amountScaled
                );
            }
        }

        emit ProcessedWithdrawals(block.timestamp, txBatchId);
    }

    function _getWithdrawalHash(
        bool isAutomatic_,
        uint32 chainId,
        uint32 tokenId,
        uint64 amount,
        address recipient_
    ) internal pure returns (bytes32) {
        uint isAutomatic = isAutomatic_ ? 1 : 0;

        uint i1 = isAutomatic * 2 ** 32 + chainId;
        uint i2 = i1 * 2 ** 32 + tokenId;
        uint batchedWithdrawalInfo = i2 * 2 ** 64 + amount;
        uint256 recipient = uint256(uint160(recipient_));

        uint256 P = 2 ** 251 + 17 * 2 ** 192 + 1;

        bytes memory data = abi.encodePacked(batchedWithdrawalInfo, recipient);
        uint256 withdrawalHash = uint256(keccak256(data)) % P;

        return bytes32(withdrawalHash);
    }
}
