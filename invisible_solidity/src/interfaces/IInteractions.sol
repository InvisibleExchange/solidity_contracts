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

    function getPendingDepositAmount(
        uint256 starkKey,
        address tokenAddress
    ) external view returns (uint256);

    // Withdrawals

    function makeWithdrawal(address tokenAddress) external;

    function getWithdrawableAmount(
        address userAddress,
        address tokenAddress
    ) external view returns (uint256);

    function getETHWithdrawableAmount(
        address depositor
    ) external view returns (uint256);

    // txBatchUpdates
    function updateStateAfterTxBatch(uint256[] calldata programOutput) external;
}
