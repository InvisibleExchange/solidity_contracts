// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "../utils/TokenInfo.sol";
import "../utils/FlashLender.sol";

import "../storage/VaultManagerStorage.sol";

abstract contract VaultManager is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    VaultManagerStorage,
    FlashLender,
    TokenInfo
{
    function __VaultManager_init(
        address payable _gasCollector,
        uint32 _chainId
    ) internal {
        s_gasFeeCollector = _gasCollector;

        __tokenInfo_init();

        s_vaults[address(0)] = true; // Eth vault
        chainId = _chainId;
    }

    function _VMsetEscapeVerifier(address newVerirfier) internal {
        escapeVerifier = newVerirfier;
    }

    function setClAggregators(
        address[] calldata tokenAddress,
        address[] calldata aggregatorAddresses
    ) external onlyOwner {
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            _setClAggregator(tokenAddress[i], aggregatorAddresses[i]);
        }
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
    ) internal returns (bool) {
        if (!s_vaults[tokenAddress]) return true;

        // ? Get the withdrawable amount pending for the recipient
        uint256 withdrawalAmount = totalAmount - gasFee;
        if (withdrawalAmount <= 0) return true;

        IERC20 token = IERC20(tokenAddress);

        // ? Transfer the fee to the gasFeeCollector
        if (gasFee > 0) {
            bool success_ = token.transfer(s_gasFeeCollector, gasFee);
            if (!success_) return false;
        }

        bool success = token.transfer(recipient, withdrawalAmount);
        return success;
    }

    // ---------------------------------------------------------

    function makeETHVaultWithdrawal(
        address payable recipient,
        uint256 totalAmount,
        uint256 gasFee
    ) internal returns (bool) {
        // ? Get the withdrawable amount pending for the recipient
        uint256 withdrawalAmount = totalAmount - gasFee;
        if (withdrawalAmount <= 0) return true;

        // ? Transfer the fee to the gasFeeCollector
        if (gasFee > 0) {
            (bool sent, ) = s_gasFeeCollector.call{value: gasFee}("");
            require(sent, "Failed to send Ether to gasCollector");
        }

        // ? Transfer the rest to the recipient
        (bool sent2, ) = recipient.call{value: withdrawalAmount}("");
        return sent2;
    }

    // ---------------------------------------------------------
    function executeEscape(
        address tokenAddress,
        address payable recipient,
        uint256 escapeAmount
    ) external nonReentrant {
        require(s_vaults[tokenAddress], "Vault is not registered");
        require(
            escapeVerifier == msg.sender,
            "Only escapeVerifier can call this function"
        );

        require(escapeAmount > 0, "No pending withdrawals");

        if (tokenAddress == address(0)) {
            // Eth escape

            // ? Transfer the rest to the recipient
            (bool sent2, ) = recipient.call{value: escapeAmount}("");
            require(sent2, "Failed to send Ether");
        } else {
            // Erc escape

            bool success = IERC20(tokenAddress).transfer(
                recipient,
                escapeAmount
            );
            require(success, "Transfer failed");
        }
    }

    // ---------------------------------------------------------

    function getChainId() internal view returns (uint32) {
        return chainId;
    }
}
