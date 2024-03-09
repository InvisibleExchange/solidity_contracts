// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../interfaces/IMessageRelay.sol";

import "../../interactions/L2Deposit.sol";
import "../../interactions/L2Withdrawal.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

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

        uint64 chainId = getChainId();
        (newAmountDeposited, depositId) = _makeDeposit(
            tokenAddress,
            amount,
            starkKey,
            chainId
        );


        depositHash = _updateDepositHashes(
            depositId,
            tokenAddress,
            amount,
            starkKey
        );

        return (newAmountDeposited, depositId, depositHash);
    }





    function _updateDepositHashes(
        uint64 depositId,
        address tokenAddress,
        uint256 amount,
        uint256 starkKey
        ) private returns (bytes32 depositHash) {

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

        return depositHash;
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

        if (deposits.length == 0) return;

        _processDepositHashes(txBatchId, deposits);
    }

    function processWithdrawals(
        uint32 txBatchId,
        WithdrawalRequest[] calldata withdrawals
    ) external {

        if (withdrawals.length == 0) return;

        uint256 P = 2 ** 251 + 17 * 2 ** 192 + 1;

        bytes32 withdrawalsHash = 0;
        // ? Hash the withdrawals
        for (uint256 i = 0; i < withdrawals.length; i++) {
            bytes32 withHash = _getWithdrawalHash(
                withdrawals[i].chainId,
                withdrawals[i].tokenId,
                withdrawals[i].amount,
                withdrawals[i].recipient
            );

            bytes memory data = abi.encodePacked(withdrawalsHash, withHash);
            uint256 newWithHash = uint256(keccak256(data)) % P;
            withdrawalsHash = bytes32(newWithHash);
        }

        // ? Compare to the received withdrawal hash
        bytes32 newAccumulatedWithdrawalHash = IL2MessageRelay(s_messageRelay)
            .accumulatedWithdrawalHashes(txBatchId);
        require(
            withdrawalsHash == newAccumulatedWithdrawalHash,
            "Invalid accumulated withdrawal hash"
        );

        // ? Process the withdrawals (send the funds to the recipients)
        processAccumulatedWithdrawalOutputs(withdrawals, txBatchId);

        IL2MessageRelay(s_messageRelay).processAccumulatedWithdrawalHash(
            txBatchId,
            withdrawalsHash
        );
    }

    //
}
