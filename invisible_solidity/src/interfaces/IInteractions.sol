// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IInteractions {
    // Deposits
    function makeDeposit(
        address tokenAddress,
        uint256 amount,
        uint256 starkKey
    ) external returns (uint64 newAmountDeposited);

    function startCancelDeposit(
        address tokenAddress,
        uint256 starkKey
    ) external;

    function startCancelETHDeposit(uint256 starkKey) external;

    function getPendingDepositAmount(
        uint256 starkKey,
        address tokenAddress
    ) external view returns (uint256);

    function getPendingETHDepositAmount(
        uint256 starkKey
    ) external view returns (uint256);
}
