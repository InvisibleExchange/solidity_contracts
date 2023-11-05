// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../helpers/TokenInfo.sol";
import "../helpers/FlashLender.sol";

abstract contract VaultManager is FlashLender, TokenInfo, OwnableUpgradeable {
    event VaultRegisteredEvent(address tokenAddress);

    address payable public s_gasFeeCollector;
    mapping(address => bool) s_vaults; // maps token address to vault

    address[] public addresses;

    function __VaultManager_init(address payable _gasCollector) internal {
        s_gasFeeCollector = _gasCollector;

        __tokenInfo_init();
    }

    // ---------------------------------------------------------

    function registerToken(
        address tokenAddress,
        uint32 tokenId,
        uint8 offchainDecimals
    ) external onlyOwner {
        _registerToken(tokenAddress, tokenId, offchainDecimals);
        _registerNewAssetVault(tokenAddress);
    }

    function _registerNewAssetVault(address tokenAddress) private {
        require(!s_vaults[tokenAddress], "Vault already registered");
        require(tokenAddress != address(0), "Token address cannot be 0");

        s_vaults[tokenAddress] = true;
        emit VaultRegisteredEvent(tokenAddress);
    }

    // TODO : THIS CONTRACT SHOULD BE THE ONLY ONE TO INTERACT WITH THE FUNDS
    // TODO: ALL THESE FUNCTIONS SHOULD BE NON-REENTRANT

    function isVaultRegistered(
        address tokenAddress
    ) external view returns (bool) {
        return s_vaults[tokenAddress];
    }

    // ---------------------------------------------------------

    // * ERC20 Vault Deposit
    function makeErc20VaultDeposit(
        address tokenAddress,
        uint256 amount
    ) internal {
        require(s_vaults[tokenAddress], "Vault is not registered");

        IERC20 token = IERC20(tokenAddress);
        bool success = token.transferFrom(msg.sender, address(this), amount);

        require(success, "Transfer failed");
    }

    // * ERC20 Vault Withdrawal
    function makeErc20VaultWithdrawal(
        address tokenAddress,
        address recipient,
        uint256 totalAmount,
        uint256 gasFee
    ) internal {
        require(s_vaults[tokenAddress], "Vault is not registered");

        // ? Get the withdrawable amount pending for the recipient
        uint256 withdrawalAmount = totalAmount - gasFee;
        require(withdrawalAmount > 0, "No pending withdrawals");

        IERC20 token = IERC20(tokenAddress);

        // ? Transfer the fee to the gasFeeCollector
        if (gasFee > 0) {
            bool success = token.transfer(s_gasFeeCollector, gasFee);
            require(success, "Transfer failed");
        }

        bool success2 = token.transfer(recipient, withdrawalAmount);
        require(success2, "Transfer failed");
    }

    // ---------------------------------------------------------

    function makeETHVaultWithdrawal(
        address payable recipient,
        uint256 totalAmount,
        uint256 gasFee
    ) internal {
        // ? Get the withdrawable amount pending for the recipient
        uint256 withdrawalAmount = totalAmount - gasFee;
        require(withdrawalAmount > 0, "No pending withdrawals");

        // ? Transfer the fee to the gasFeeCollector
        if (gasFee > 0) {
            (bool sent, ) = s_gasFeeCollector.call{value: gasFee}("");
            require(sent, "Failed to send Ether to gasCollector");
        }

        // ? Transfer the rest to the recipient
        (bool sent2, ) = recipient.call{value: withdrawalAmount}("");
        require(sent2, "Failed to send Ether");
    }

    // ---------------------------------------------------------
}