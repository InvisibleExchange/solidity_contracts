// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

abstract contract InteractionsStorageBase {
    address public s_messageRelay;

    // * DEPOSITS ----------------------------------------------

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

    struct DepositCancellation {
        address depositor;
        uint256 pubKey;
        uint32 tokenId;
        uint256 timestamp;
    }
    DepositCancellation[] s_depositCencelations;

    // * WITHDRAWALS -------------------------------------------

    event WithdrawalEvent(
        address withdrawer,
        address tokenAddress,
        uint256 withdrawalAmount,
        uint256 timestamp
    );
    event ProcessedWithdrawals(uint256 timestamp, uint64 txBatchId);

    mapping(address => mapping(address => uint256)) s_pendingWithdrawals; // recipient => tokenAddress => amount
}

abstract contract L2InteractionsStorage is InteractionsStorageBase {
    mapping(uint64 depositId => bytes32) public s_depositHashes;

    mapping(uint64 depositId => DepositCancellation) s_L2DepositCencellations;

    struct WithdrawalRequest {
        uint32 chainId;
        uint32 tokenId;
        uint64 amount;
        address recipient;
        bool isAutomatic;
    }

    struct DepositRequest {
        uint64 depositId;
        uint32 tokenId;
        uint64 amount;
        uint256 starkKey;
    }
}
