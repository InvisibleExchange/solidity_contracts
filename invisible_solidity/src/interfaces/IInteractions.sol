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

// cast send --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --rpc-url http://127.0.0.1:8545/ 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 "registerToken(address,uint32,uint8)" 0xA405a2D4Ae49dA2978311F2c710b5E48699816Ec 55555 6
