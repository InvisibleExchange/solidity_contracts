// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../interactions/Deposit.sol";
import "../interactions/Withdrawal.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

abstract contract Interactions is
    ReentrancyGuardUpgradeable,
    Deposit,
    Withdrawal
{
    // Deposits
    function makeDeposit(
        address tokenAddress,
        uint256 amount,
        uint256 starkKey
    ) external payable nonReentrant returns (uint64 newAmountDeposited) {
        return _makeDeposit(tokenAddress, amount, starkKey);
    }

    function startCancelDeposit(
        address tokenAddress,
        uint256 starkKey
    ) external nonReentrant {
        return _startCancelDeposit(tokenAddress, starkKey);
    }

    function startCancelETHDeposit(uint256 starkKey) external nonReentrant {
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

    //
}
