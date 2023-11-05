// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Deposit.sol";
import "./Withdrawal.sol";

abstract contract Interactions is Deposit, Withdrawal {
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

    //
}
