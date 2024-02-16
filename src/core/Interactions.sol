// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../interactions/Deposit.sol";
import "../interactions/Withdrawal.sol";
import "./MessageRelay.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

abstract contract L1Interactions is
    ReentrancyGuardUpgradeable,
    L1Deposit,
    Withdrawal
{
    // Deposits
    function makeDeposit(
        address tokenAddress,
        uint256 amount,
        uint256 starkKey
    )
        external
        payable
        nonReentrant
        returns (uint64 newAmountDeposited, uint64 depositId)
    {
        return _makeDeposit(tokenAddress, amount, starkKey);
    }

    function startCancelDeposit(
        address tokenAddress,
        uint256 starkKey
    ) external nonReentrant {
        return _startCancelDeposit(tokenAddress, starkKey);
    }

    function startCancelETHDeposit(uint256 starkKey) external nonReentrant {
        return _startCancelDeposit(address(0), starkKey);
    }

    function getPendingDepositAmount(
        uint256 starkKey,
        address tokenAddress
    ) public view returns (uint256) {
        return _getPendingDepositAmount(starkKey, tokenAddress);
    }

    function getPendingETHDepositAmount(
        uint256 starkKey
    ) public view returns (uint256) {
        return _getPendingDepositAmount(starkKey, address(0));
    }

    //
}

// * NEW DEPOSIT FLOW:
// * 1. User makes a deposit on the L2
// * 2. The L2MessageRelay maps(stores) the depositId to the depositHash
// * 3. After every batch is finalized we receive the accumulated deposit/withdrawal hashes from the L1MessageRelay
// * 4. We store the accumulated deposit/withdrawal hashes in the L2MessageRelay
// * 5. The accDepHash we receive is the hash of the hashes of all deposits that were claimed in the batch
// * 6. We can then verify the accDepHash we received from the L1MessageRelay with the accDepHash we have stored in the L2MessageRelay
// * We do this by providing the real deposits and hashing them and verifying the hash against the stored hash for that depositId

// * 7. If the user wants to cancell the deposit he can initiate the cancellation process
// * 8. The cancellation will be valid after a time delay of 3 days (for example)
// * 9. The user can reclaim the funds back to his account after the time delay

abstract contract L2Interactions is
    ReentrancyGuardUpgradeable,
    L2Deposit,
    L2Withdrawal
{
    // Deposits
    function makeDeposit(
        address tokenAddress,
        uint256 amount,
        uint256 starkKey
    )
        external
        payable
        nonReentrant
        returns (
            uint64 newAmountDeposited,
            uint64 depositId,
            bytes32 depositHash
        )
    {
        (newAmountDeposited, depositId) = _makeDeposit(
            tokenAddress,
            amount,
            starkKey
        );

        // ? Hash the deposit info
        uint32 tokenId = getTokenId(tokenAddress);
        uint64 amountScaled;
        if (tokenAddress != address(0)) {
            amountScaled = scaleDown(amount, tokenId);
        } else {
            amountScaled = scaleDown(msg.value, ETH_ID);
        }

        depositHash = _getDepositHash(
            depositId,
            tokenId,
            amountScaled,
            starkKey
        );

        // ? Store the deposit hash
        s_depositHashes[depositId] = depositHash;

        return (newAmountDeposited, depositId, depositHash);
    }

    function startCancelDeposit(
        address tokenAddress,
        uint64 depositId,
        uint256 starkKey
    ) external nonReentrant {
        return _startCancelDeposit(tokenAddress, depositId, starkKey);
    }

    function startCancelETHDeposit(
        uint64 depositId,
        uint256 starkKey
    ) external nonReentrant {
        return _startCancelDeposit(address(0), depositId, starkKey);
    }

    function getPendingDepositAmount(
        uint256 starkKey,
        address tokenAddress
    ) public view returns (uint256) {
        return _getPendingDepositAmount(starkKey, tokenAddress);
    }

    function getPendingETHDepositAmount(
        uint256 starkKey
    ) public view returns (uint256) {
        return _getPendingDepositAmount(starkKey, address(0));
    }

    // * Process Accumulated Deposits/Withdrawals --------------------------------------------------------------------

    function processDepositHashes(
        uint32 txBatchId,
        DepositRequest[] calldata deposits
    ) external {
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
            .accumulatedDepositHashes(txBatchId);
        require(
            depositsHash == accumulatedDepositHash,
            "Invalid accumulated deposit hash"
        );

        // ? remove the deposits from the pending deposits
        for (uint256 i = 0; i < deposits.length; i++) {
            s_depositHashes[deposits[i].depositId] = 0;
        }

        L2MessageRelay(s_messageRelay).processAccumulatedDepositHash(
            txBatchId,
            accumulatedDepositHash
        );
    }

    function processWithdrawals(
        uint32 txBatchId,
        WithdrawalRequest[] calldata withdrawals
    ) external {
        bytes32 withdrawalsHash = 0;
        // ? Hash the withdrawals
        for (uint256 i = 0; i < withdrawals.length; i++) {
            bytes32 withHash = _getWithdrawalHash(
                withdrawals[i].chainId,
                withdrawals[i].tokenId,
                withdrawals[i].amount,
                withdrawals[i].recipient
            );

            withdrawalsHash = keccak256(
                abi.encodePacked([withdrawalsHash, withHash])
            );
        }

        // ? Compare to the received withdrawal hash
        bytes32 newAccumulatedWithdrawalHash = L2MessageRelay(s_messageRelay)
            .accumulatedWithdrawalHashes(txBatchId);
        require(
            withdrawalsHash == newAccumulatedWithdrawalHash,
            "Invalid accumulated withdrawal hash"
        );

        // ? Process the withdrawals (send the funds to the recipients)
        processAccumulatedWithdrawalOutputs(withdrawals, txBatchId);

        L2MessageRelay(s_messageRelay).processAccumulatedWithdrawalHash(
            txBatchId,
            withdrawalsHash
        );
    }

    // * Helpers --------------------------------------------------------------------

    function _getWithdrawalHash(
        uint32 chainId,
        uint32 tokenId,
        uint64 amount,
        address recipient_
    ) private pure returns (bytes32) {
        uint256 batchedWithdrawalInfo = ((chainId * 2 ** 32) + tokenId) *
            2 ** 32 +
            amount;
        uint256 recipient = uint256(uint160(recipient_));

        return keccak256(abi.encodePacked([batchedWithdrawalInfo, recipient]));
    }

    function setMessageRelay(address _relay) external onlyOwner {
        s_messageRelay = _relay;
    }

    //
}
