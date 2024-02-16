// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../libraries/ProgramOutputParser.sol";
import "../core/VaultManager.sol";
import "../storage/InteractionsStorage.sol";
import "../core/Interactions.sol";

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
        uint256 gasLimit = 80000; // TODO: Find out how much gas is required for a simple erc20 transfer
        uint256 gasPrice = tx.gasprice;

        uint256 gasFee = gasLimit * gasPrice;

        (uint8 tokenPriceDecimals, uint256 tokenPrice) = getTokenPrice(
            tokenAddress
        );
        (uint8 ethPriceDecimals, uint256 ethPrice) = getTokenPrice(address(0));

        uint8 ethDecimals = 18;
        uint8 tokenDecimals = uint8(IERC20Metadata(tokenAddress).decimals());

        uint8 decimalConversion = ethDecimals +
            ethPriceDecimals -
            tokenDecimals -
            tokenPriceDecimals;

        uint256 ercGasFee = (gasFee * ethPrice) /
            (tokenPrice * 10 ** decimalConversion);

        return ercGasFee;
    }
}

// * =================================================================================================
// * =================================================================================================

abstract contract Withdrawal is WithdrawalBase {
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
}
