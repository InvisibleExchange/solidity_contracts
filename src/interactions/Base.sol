// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../core/VaultManager.sol";
import "../storage/InteractionsStorage.sol";

abstract contract DepositBase is VaultManager, InteractionsStorageBase {
    function _makeDeposit(
        address tokenAddress,
        uint256 amount,
        uint256 starkKey,
        uint32 chainId
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
        uint32 chainId 
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
        uint32 chainId 
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
    function _executeWithdrawal(
        address _tokenAddress,
        address _recipient,
        uint256 _totalAmount,
        uint256 _gasFee
    ) internal {
        //

        if (_tokenAddress == address(0)) {
            bool success = makeETHVaultWithdrawal(
                payable(_recipient),
                _totalAmount,
                _gasFee
            );

            if (!success) {
                s_pendingWithdrawals[_recipient][address(0)] += _totalAmount;
            }
        } else {
            bool success = makeErc20VaultWithdrawal(
                _tokenAddress,
                _recipient,
                _totalAmount,
                _gasFee
            );

            if (!success) {
                s_pendingWithdrawals[_recipient][_tokenAddress] += _totalAmount;
            }
        }
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
            bool success = makeErc20VaultWithdrawal(
                token,
                recipient,
                amount,
                0
            );
            require(success, "Transfer failed");
        }
    }

    // * Helpers --------------------------------------------------------------------

    function gasFeeForETHWithdrawal() internal view returns (uint256) {
        uint256 gasLimit = 21000; // Default gas limit for a simple transfer
        uint256 gasPrice = tx.gasprice;

        return gasLimit * gasPrice;
    }

    function gasFeeForERCWithdrawal(
        address tokenAddress
    ) internal view returns (uint256) {
        // TODO: Figure out what this should be

        return 0;
        // uint256 gasLimit = 80000; // TODO: Find out how much gas is required for a simple erc20 transfer
        // uint256 gasPrice = tx.gasprice;

        // uint256 gasFee = gasLimit * gasPrice;

        // (uint8 tokenPriceDecimals, uint256 tokenPrice) = getTokenPrice(
        //     tokenAddress
        // );
        // (uint8 ethPriceDecimals, uint256 ethPrice) = getTokenPrice(address(0));

        // uint8 ethDecimals = 18;
        // uint8 tokenDecimals = uint8(IERC20Metadata(tokenAddress).decimals());

        // uint8 decimalConversion = ethDecimals +
        //     ethPriceDecimals -
        //     tokenDecimals -
        //     tokenPriceDecimals;

        // uint256 ercGasFee = (gasFee * ethPrice) /
        //     (tokenPrice * 10 ** decimalConversion);

        // return ercGasFee;
    }
}
