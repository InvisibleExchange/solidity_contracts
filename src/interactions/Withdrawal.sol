// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../libraries/ProgramOutputParser.sol";
import "../core/VaultManager.sol";
import "../storage/InteractionsStorage.sol";

abstract contract Withdrawal is VaultManager, InteractionsStorage {
    // * Withdrawals --------------------------------------------------------------------

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

        emit StoredNewWithdrawalsEvent(block.timestamp, txBatchId);
    }

    //

    function _executeWithdrawal(
        address _tokenAddress,
        address _recipient,
        uint256 _totalAmount,
        uint256 _gasFee
    ) private {
        //

        if (_tokenAddress == address(0)) {
            bool success = makeETHVaultWithdrawal(
                payable(_recipient),
                _totalAmount,
                _gasFee
            );

            if (!success) {
                s_failedWithdrawals[_recipient][address(0)] += _totalAmount;
            }
        } else {
            bool success = makeErc20VaultWithdrawal(
                _tokenAddress,
                _recipient,
                _totalAmount,
                _gasFee
            );

            if (!success) {
                s_failedWithdrawals[_recipient][_tokenAddress] += _totalAmount;
            }
        }
    }

    function claimFailedWithdrawal(address token) external nonReentrant {
        uint256 amount = s_failedWithdrawals[msg.sender][token];
        require(amount > 0, "No failed withdrawal to claim");

        s_failedWithdrawals[msg.sender][token] = 0;

        if (token == address(0)) {
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            require(success, "Transfer failed");
        } else {
            bool success = IERC20(token).transfer(msg.sender, amount);
            require(success, "Transfer failed");
        }
    }

    // * Helpers --------------------------------------------------------------------

    function gasFeeForETHWithdrawal() private view returns (uint256) {
        uint256 gasLimit = 21000; // Default gas limit for a simple transfer
        uint256 gasPrice = tx.gasprice;

        return gasLimit * gasPrice;
    }

    function gasFeeForERCWithdrawal(
        address tokenAddress
    ) private view returns (uint256) {
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
