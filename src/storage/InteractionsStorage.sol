// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract InteractionsStorage {
    // * DEPOSITS ----------------------------------------------

    // make depositId indexed
    event DepositEvent(
        uint64 depositId,
        uint256 pubKey,
        uint32 tokenId,
        uint64 depositAmountScaled,
        uint256 timestamp
    );
    event DepositCancelEvent(
        uint256 pubKey,
        address tokenAddress,
        uint256 timestamp
    );

    event UpdatedPendingDepositsEvent(uint256 timestamp, uint64 txBatchId);

    mapping(uint256 => mapping(uint32 => uint64)) public s_pendingDeposits; // pubKey => tokenId => amountScaled

    uint64 s_depositCount;

    struct DepositCancelation {
        address depositor;
        uint256 pubKey;
        uint32 tokenId;
    }

    DepositCancelation[] s_depositCencelations;

    // * WITHDRAWALS -------------------------------------------

    event WithdrawalEvent(
        address withdrawer,
        address tokenAddress,
        uint256 withdrawalAmount,
        uint256 timestamp
    );
    event StoredNewWithdrawalsEvent(uint256 timestamp, uint64 txBatchId);

    mapping(address => mapping(address => uint256)) public s_failedWithdrawals; // recipient => tokenAddress => amount
}
