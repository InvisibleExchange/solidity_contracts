// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IVaults.sol";

import "../helpers/tokenInfo.sol";
import "../helpers/parseProgramOutput.sol";
import "../vaults/VaultRegistry.sol";

contract Withdrawal is TokenInfo, ProgramOutputParser, VaultRegistry {
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
        for (uint256 i = 0; i < withdrawalOutputs.length; i++) {
            WithdrawalTransactionOutput
                memory withdrawalOutput = withdrawalOutputs[i];

            (
                uint64 tokenId,
                uint64 amount,
                address recipient
            ) = uncompressWithdrawalOutput(withdrawalOutput);

            if (amount == 0) continue;

            uint256 amountScaled = scaleUp(amount, tokenId);

            if (tokenId == TokenInfo.ETH_ID) {
                address vaultAddress = getETHVaultAddress();
                IETHVault vault = IETHVault(vaultAddress);

                vault.increaseWithdrawableAmount(recipient, amountScaled);
            } else {
                address tokenAddress = getTokenAddress(tokenId);

                address vaultAddress = getAssetVaultAddress(tokenAddress);
                IAssetVault vault = IAssetVault(vaultAddress);

                vault.increaseWithdrawableAmount(
                    recipient,
                    tokenAddress,
                    amountScaled
                );
            }
        }

        emit StoredNewWithdrawalsEvent(block.timestamp, txBatchId);
    }

    //

    function _makeWithdrawal(address tokenAddress) internal {
        require(msg.sender != address(0), "msg.sender is address(zero)");

        if (tokenAddress == address(0)) {
            return withdrawEth();
        }

        address vaultAddress = getAssetVaultAddress(tokenAddress);
        IAssetVault vault = IAssetVault(vaultAddress);

        uint256 withdrawableAmount = vault.getWithdrawableAmount(msg.sender);

        vault.makeErc20VaultWithdrawal(msg.sender, tokenAddress);

        emit WithdrawalEvent(
            msg.sender,
            tokenAddress,
            withdrawableAmount,
            block.timestamp
        );
    }

    function withdrawEth() private {
        address vaultAddress = getETHVaultAddress();
        IETHVault vault = IETHVault(vaultAddress);

        uint256 withdrawableAmount = vault.getWithdrawableAmount(msg.sender);

        vault.makeETHVaultWithdrawal(payable(msg.sender));

        emit WithdrawalEvent(
            msg.sender,
            address(0),
            withdrawableAmount,
            block.timestamp
        );
    }
}
