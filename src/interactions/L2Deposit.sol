// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../storage/InteractionsStorage.sol";
import "../interfaces/IMessageRelay.sol";

import "./Base.sol";

abstract contract L2Deposit is DepositBase, L2InteractionsStorage {
    function _processDepositHashes(
        uint32 txBatchId,
        DepositRequest[] calldata deposits
    ) internal {
        bytes32 depositsHash = 0;
        for (uint256 i = 0; i < deposits.length; i++) {
            bytes32 depHash = _getDepositHash(
                deposits[i].depositId,
                deposits[i].tokenId,
                deposits[i].amount,
                deposits[i].starkKey
            );

            depositsHash = keccak256(abi.encodePacked([depositsHash, depHash]));
        }

        bytes32 accumulatedDepositHash = IL2MessageRelay(s_messageRelay)
            .accumulatedDepositHashes(txBatchId - 1);
        require(
            depositsHash == accumulatedDepositHash,
            "Invalid accumulated deposit hash"
        );

        // ? remove the deposits from the pending deposits
        for (uint256 i = 0; i < deposits.length; i++) {
            s_depositHashes[deposits[i].depositId] = 0;

            // ? Decrease pending deposits account
            require(
                s_pendingDeposits[deposits[i].starkKey][deposits[i].tokenId] >=
                    deposits[i].amount,
                "An invalid deposit was executed offchain"
            );
            s_pendingDeposits[deposits[i].starkKey][
                deposits[i].tokenId
            ] -= deposits[i].amount;
        }

        IL2MessageRelay(s_messageRelay).processAccumulatedDepositHash(
            txBatchId - 1,
            accumulatedDepositHash
        );
    }

    // ----------------------------------------------------------------------------
    // * cancellations
    function _startCancelDeposit(
        address tokenAddress,
        uint64 depositId,
        uint256 starkKey
    ) internal {
        // TODO: Add nonReentrant modifier

        require(starkKey < 2 ** 251 + 17 * 2 ** 192 + 1, "Invalid stark key");
        require(msg.sender != address(0), "msg.sender can't be 0");

        // ? Get the token id and scale the amount
        uint32 tokenId = getTokenId(tokenAddress);

        uint64 pendingAmount = s_pendingDeposits[starkKey][tokenId];
        if (pendingAmount == 0) return;

        s_L2DepositCencellations[depositId] = DepositCancellation(
            msg.sender,
            starkKey,
            tokenId,
            block.timestamp
        );
        emit DepositCancelEvent(starkKey, tokenAddress, block.timestamp);
    }

    function reclaimDeposit(address depositor, uint32 depositId) external {
        DepositCancellation storage cancellation = s_L2DepositCencellations[
            depositId
        ];
        require(cancellation.depositor != depositor, "Invalid depositor");

        uint64 pendingAmount = s_pendingDeposits[cancellation.pubKey][
            cancellation.tokenId
        ];
        require(pendingAmount > 0, "No pending amount");

        uint64 elapsed = uint64(block.timestamp - cancellation.timestamp);
        require(elapsed > 5 days, "Deposit is not yet reclaimable"); // Have a delay period before you can reclaim the deposit

        uint256 refundAmount = scaleUp(pendingAmount, cancellation.tokenId);

        if (cancellation.tokenId == ETH_ID) {
            (bool success, ) = payable(cancellation.depositor).call{
                value: refundAmount
            }("");
            require(success, "Transfer failed");
        } else {
            address tokenAddress = getTokenAddress(cancellation.tokenId);

            bool success = makeErc20VaultWithdrawal(
                tokenAddress,
                cancellation.depositor,
                refundAmount,
                0
            );
            require(success, "Transfer failed");
        }

        delete s_depositCencelations;
    }

    // ----------------------------------------------------------------------------

    function _getDepositHash(
        uint64 depositId,
        uint32 tokenId,
        uint64 amount,
        uint256 starkKey
    ) internal pure returns (bytes32) {
        uint256 batchedDepositInfo = ((uint(depositId) * 2 ** 32) +
            uint(tokenId)) *
            2 ** 64 +
            uint(amount);

        bytes32 depositHash = keccak256(
            abi.encodePacked([batchedDepositInfo, starkKey])
        );

        return depositHash;
    }
}
