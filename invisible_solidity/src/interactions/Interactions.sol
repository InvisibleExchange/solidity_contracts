// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../interfaces/IVaults.sol";

import "./Deposit.sol";
import "./Withdrawal.sol";

contract Interactions is Deposit, Withdrawal {
    // TODO: For testing purposes only !!!
    receive() external payable {
        uint256 starkKey = 775866413365693995389455817999955458452590009573650990406301639026116962377;
        _makeDeposit(address(0), 0, starkKey);
    }

    // Deposits
    function makeDeposit(
        address tokenAddress,
        uint256 amount,
        uint256 starkKey
    ) external payable returns (uint64 newAmountDeposited) {
        return _makeDeposit(tokenAddress, amount, starkKey);
    }

    function startCancelDeposit(
        address tokenAddress,
        uint256 starkKey
    ) external {
        return _startCancelDeposit(tokenAddress, starkKey);
    }

    function startCancelETHDeposit(uint256 starkKey) external {
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

    // Withdrawals
    function makeWithdrawal(address tokenAddress, address _recipient) external {
        return _makeWithdrawal(tokenAddress, _recipient);
    }

    function makeETHWithdrawal(
        address _recipient,
        address _approvedProxy
    ) external {
        return _makeWithdrawal(address(0), _recipient);
    }

    function getWithdrawableAmount(
        address depositor,
        address tokenAddress
    ) public view returns (uint256) {
        address vaultAddress = getAssetVaultAddress(tokenAddress);
        IAssetVault vault = IAssetVault(vaultAddress);

        return vault.getWithdrawableAmount(depositor);
    }

    function getETHWithdrawableAmount(
        address depositor
    ) public view returns (uint256) {
        address vaultAddress = getETHVaultAddress();
        IETHVault vault = IETHVault(vaultAddress);

        return vault.getWithdrawableAmount(depositor);
    }

    // Token info
    function registerToken(
        address tokenAddress,
        uint32 tokenId,
        uint8 offchainDecimals
    ) external {
        _registerToken(tokenAddress, tokenId, offchainDecimals);
        addNewAssetVault(tokenAddress);
    }

    //
}
