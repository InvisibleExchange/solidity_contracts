// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../libraries/ProgramOutputParser.sol";
import "../core/VaultManager.sol";
import "../storage/InteractionsStorage.sol";

import "../core/MessageRelay.sol";

abstract contract DepositBase is VaultManager, InteractionsStorageBase {
    function _makeDeposit(
        address tokenAddress,
        uint256 amount,
        uint256 starkKey
    ) internal returns (uint64 newAmountDeposited, uint64 depositId) {
        require(starkKey < 2 ** 251 + 17 * 2 ** 192 + 1, "Invalid stark Key");
        require(starkKey > 0, "Invalid stark Key");

        if (msg.value > 0) {
            return _makeEthDeposit(starkKey);
        } else {
            return _makeErc20Deposit(tokenAddress, amount, starkKey);
        }
    }

    function _makeEthDeposit(
        uint256 starkKey
    ) private returns (uint64 newAmountDeposited, uint64 depositId) {
        //

        uint64 depositAmountScaled = scaleDown(msg.value, ETH_ID);

        uint64 pendingAmount = s_pendingDeposits[starkKey][ETH_ID];
        s_pendingDeposits[starkKey][ETH_ID] =
            pendingAmount +
            depositAmountScaled;

        uint64 chainId = getChainId();
        depositId = chainId * 2 ** 32 + s_depositCount;
        s_depositCount += 1;

        emit DepositEvent(
            depositId,
            starkKey,
            ETH_ID,
            depositAmountScaled,
            block.timestamp
        );

        return (pendingAmount + depositAmountScaled, depositId);
    }

    function _makeErc20Deposit(
        address tokenAddress,
        uint256 amount,
        uint256 starkKey
    ) private returns (uint64 newAmountDeposited, uint64 depositId) {
        //

        makeErc20VaultDeposit(tokenAddress, amount);

        uint32 tokenId = getTokenId(tokenAddress);
        uint64 depositAmountScaled = scaleDown(amount, tokenId);

        uint64 pendingAmount = s_pendingDeposits[starkKey][tokenId];
        s_pendingDeposits[starkKey][tokenId] =
            pendingAmount +
            depositAmountScaled;

        chainId = getChainId();
        depositId = chainId * 2 ** 32 + s_depositCount;
        s_depositCount += 1;

        emit DepositEvent(
            depositId,
            starkKey,
            tokenId,
            depositAmountScaled,
            block.timestamp
        );

        return (pendingAmount + depositAmountScaled, depositId);
    }

    // ----------------------------------------------------------------------------
    // View

    function _getPendingDepositAmount(
        uint256 starkKey,
        address tokenAddress
    ) internal view returns (uint256) {
        uint32 tokenId = getTokenId(tokenAddress);
        uint64 pendingAmount = s_pendingDeposits[starkKey][tokenId];
        return scaleUp(pendingAmount, tokenId);
    }
}

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
        if (s_depositCencelations.length == 0) return;

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

        bytes32 accumulatedDepositHash = L2MessageRelay(s_messageRelay)
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

        L2MessageRelay(s_messageRelay).processAccumulatedDepositHash(
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
        uint256 batchedDepositInfo = ((depositId * 2 ** 64) + tokenId) *
            2 ** 32 +
            amount;

        bytes32 depositHash = keccak256(
            abi.encodePacked([batchedDepositInfo, starkKey])
        );

        return depositHash;
    }
}
