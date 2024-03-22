// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../core/VaultManager.sol";
import "../storage/InteractionsStorage.sol";

abstract contract DepositBase is VaultManager, InteractionsStorageBase {
    function _makeDeposit(
        address tokenAddress,
        uint256 amount,
        uint256 starkKey,
        uint64 chainId
    ) internal returns (uint64 newAmountDeposited, uint64 depositId) {
        require(starkKey < 2 ** 251 + 17 * 2 ** 192 + 1, "Invalid stark Key");
        require(starkKey > 0, "Invalid stark Key");

        if (msg.value > 0) {
            return _makeEthDeposit(starkKey, chainId);
        } else {
            return _makeErc20Deposit(tokenAddress, amount, starkKey, chainId);
        }
    }

    function _makeEthDeposit(
        uint256 starkKey,
        uint64 chainId
    ) private returns (uint64 newAmountDeposited, uint64 depositId) {
        //

        uint64 depositAmountScaled = scaleDown(msg.value, ETH_ID);

        uint64 pendingAmount = s_pendingDeposits[starkKey][ETH_ID];
        s_pendingDeposits[starkKey][ETH_ID] =
            pendingAmount +
            depositAmountScaled;

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
        uint256 starkKey,
        uint64 chainId
    ) private returns (uint64 newAmountDeposited, uint64 depositId) {
        //

        makeErc20VaultDeposit(tokenAddress, amount);

        uint32 tokenId = getTokenId(tokenAddress);
        uint64 depositAmountScaled = scaleDown(amount, tokenId);

        uint64 pendingAmount = s_pendingDeposits[starkKey][tokenId];
        s_pendingDeposits[starkKey][tokenId] =
            pendingAmount +
            depositAmountScaled;

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

abstract contract WithdrawalBase is VaultManager, InteractionsStorageBase {
    function _executeAutomaticWithdrawal(
        address _tokenAddress,
        address _recipient,
        uint256 _totalAmount
    ) internal {
        //

        if (_tokenAddress == address(0)) {
            bool success = makeETHVaultWithdrawal(
                payable(_recipient),
                _totalAmount
            );

            if (!success) {
                s_pendingWithdrawals[_recipient][address(0)] += _totalAmount;
            }
        } else {
            bool success = makeErc20VaultWithdrawal(
                _tokenAddress,
                _recipient,
                _totalAmount
            );

            if (!success) {
                s_pendingWithdrawals[_recipient][_tokenAddress] += _totalAmount;
            }
        }
    }

    function _registerManualWithdrawal(
        address _tokenAddress,
        address _recipient,
        uint256 _totalAmount
    ) internal {
        s_pendingWithdrawals[_recipient][_tokenAddress] += _totalAmount;
    }

    function claimPendingWithdrawal(
        address recipient,
        address token
    ) external nonReentrant {
        uint256 amount = s_pendingWithdrawals[recipient][token];
        require(amount > 0, "No pending withdrawal to claim");

        s_pendingWithdrawals[recipient][token] = 0;

        if (token == address(0)) {
            // ? ETH Withdrawal
            (bool success, ) = payable(recipient).call{value: amount}("");
            require(success, "Transfer failed");
        } else {
            // ? ERC20 Withdrawal
            bool success = makeErc20VaultWithdrawal(token, recipient, amount);
            require(success, "Transfer failed");
        }
    }

    // ----------------------------------------------------------------------------
    // View

    function _getWithdrawableAmount(
        address recipient,
        address tokenAddress
    ) internal view returns (uint256) {
        return s_pendingWithdrawals[recipient][tokenAddress];
    }
}
