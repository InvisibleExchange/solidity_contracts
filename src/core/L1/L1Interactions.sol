// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../interfaces/IMessageRelay.sol";

import "../../interactions/L1Deposit.sol";
import "../../interactions/L1Withdrawal.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

abstract contract L1Interactions is
    ReentrancyGuardUpgradeable,
    L1Deposit,
    L1Withdrawal
{
    // Deposits
    function makeDeposit(
        address tokenAddress,
        uint256 amount,
        uint256 starkKey
    )
        external
        payable
        nonReentrant
        returns (uint64 newAmountDeposited, uint64 depositId)
    {
        uint64 chainId = getChainId();
        return _makeDeposit(tokenAddress, amount, starkKey, chainId);
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

    function getWithdrawableAmount(
        address recipient,
        address tokenAddress
    ) public view returns (uint256) {
        return _getWithdrawableAmount(recipient, tokenAddress);
    }

    function getETHWithdrawableAmount(
        address recipient
    ) public view returns (uint256) {
        return _getWithdrawableAmount(recipient, address(0));
    }

    //
}
