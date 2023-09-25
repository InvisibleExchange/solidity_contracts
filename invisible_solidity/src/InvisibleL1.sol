// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "src/interfaces/IVaults.sol";

import "src/interactions/Deposit.sol";
import "src/interactions/Withdrawal.sol";

contract Interactions is Interactions, MMRegistry {
    uint64 s_txBatchId;

    mapping(uint64 => uint256) public s_txBatchId2StateRoot;
    mapping(uint64 => uint256) public s_txBatchId2Timestamp;

    mapping(uint64 => uint256) public s_txBatchId2AccumulatedDepositHashes;
    mapping(uint64 => bool) public s_txBatchId2AccumulatedDepositsProcessed;
    mapping(uint64 => uint256) public s_txBatchId2AccumulatedWithdrawalHashes;
    mapping(uint64 => bool) public s_txBatchId2AccumulatedWithdrawalsProcessed;

    address s_admin;
    address s_L1MessagePasser; // The contract that passes messages from the L1 contract

    constructor(address _admin) {
        s_txBatchId = 0;
        s_admin = _admin;
    }

    modifier onlyAdmin() {
        require(msg.sender == s_admin, "Only admin");
        _;
    }

    /// @notice Processes a new L1 update
    /// @dev After the proof is verified on L1 this will be called to update the state and process deposits/withdrawals. The contract will
    /// then send the accumulated deposit/withdrawal hashes to the relevant L2s. This function is available only on the L1.
    /// @param programOutput the output of the cairo program
    function updateStateAfterTxBatch(
        uint256[] calldata programOutput
    ) external {
        // Todo: only privileged address can call this function

        (
            GlobalDexState memory dexState,
            AccumulatedHashesOutput[] memory hashes,
            DepositTransactionOutput[] memory deposits,
            WithdrawalTransactionOutput[] memory withdrawals
        ) = parseProgramOutput(programOutput);

        // Todo:
        // assert(dexState.txBatchId == s_txBatchId);
        require(
            dexState.initStateRoot == s_txBatchId2StateRoot[s_txBatchId],
            "Invalid initial state root"
        );

        updatePendingDeposits(deposits, 11111111); // todo: txBatchId
        storeNewBatchWithdrawalOutputs(withdrawals, 11111111);
    }

    /// @notice Registers a new L1 update
    /// @dev After each transaction batch the L1 will notify each L2 of the new state and the
    /// relevant deposits/withdrawals. This function is available for L2 contracts
    /// @param newStateRoot the new state root
    /// @param accumulatedDepositHash the accumulated hash of all deposits that happend on this chain since the last update
    /// @param accumulateWithdrawalHash the accumulated hash of all withdrawals that happend on this chain since the last update
    function registerL1Update(
        uint64 txBatchId,
        uint256 newStateRoot,
        uint256 accumulatedDepositHash,
        uint256 accumulateWithdrawalHash
    ) external  {
        require(txBatchId > s_txBatchId, "Invalid txBatchId");
        require(newStateRoot != s_stateRoot, "Invalid state root");

        s_txBatchId = txBatchId;
        s_txBatchId2StateRoot[txBatchId] = newStateRoot;
        s_txBatchId2Timestamp[txBatchId] = block.timestamp;

        s_txBatchId2AccumulatedDepositHashes[
            txBatchId
        ] = accumulatedDepositHash;
        s_txBatchId2AccumulatedWithdrawalHashes[
            txBatchId
        ] = accumulateWithdrawalHash;
    }


    function processL1Update() external {
        
    }



}
