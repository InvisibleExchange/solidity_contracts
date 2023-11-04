// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "forge-std/console.sol";

import "../helpers/tokenInfo.sol";
import "../helpers/parseProgramOutput.sol";
import "../vaults/VaultManager.sol";

abstract contract Withdrawal is TokenInfo, VaultManager {
    event WithdrawalEvent(
        address withdrawer,
        address tokenAddress,
        uint256 withdrawalAmount,
        uint256 timestamp
    );
    event StoredNewWithdrawalsEvent(uint256 timestamp, uint64 txBatchId);

    function storeNewBatchWithdrawalOutputs(
        WithdrawalTransactionOutput[] memory withdrawalOutputs,
        uint64 txBatchId
    ) internal {
        // ? the deposits should be grouped by token to make it easier to process

        // ? cache the lates token info (token, address, gas fee, etc.) after
        // ? each withdrawal to save on gas fees. (since the deposits are grouped by token)
        uint32 currentToken;
        address currentTokenAddress;
        uint256 gasFee;
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

            // TODO: Check chain id

            if (amount == 0) continue;

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
            return
                makeETHVaultWithdrawal(
                    payable(_recipient),
                    _totalAmount,
                    _gasFee
                );
        } else {
            return
                makeErc20VaultWithdrawal(
                    _tokenAddress,
                    _recipient,
                    _totalAmount,
                    _gasFee
                );
        }
    }

    // * Helpers --------------------------------------------------------------------

    function gasFeeForETHWithdrawal() private view returns (uint256) {
        uint256 gasLimit = 21000; // Default gas limit for a simple transfer
        uint256 gasPrice = tx.gasprice; // Get gas price of the transaction

        return gasLimit * gasPrice;
    }

    function gasFeeForERCWithdrawal(
        address tokenAddress
    ) private view returns (uint256) {
        uint256 gasLimit = 55000; // TODO: Find out how much gas is required for a simple erc20 transfer
        uint256 gasPrice = tx.gasprice; // Get gas price of the transaction

        uint256 gasFee = gasLimit * gasPrice;

        // TODO: Calculate the gas price- must account for the decimal places ...
        uint256 tokenPrice = getTokenPrice(tokenAddress);
        uint256 ethPrice = getTokenPrice(address(0));
        uint256 ercGasFee = (gasFee * ethPrice) / tokenPrice;

        return ercGasFee;
    }
}
