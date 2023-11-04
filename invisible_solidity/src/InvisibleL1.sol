// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "src/helpers/parseProgramOutput.sol";

import "src/interfaces/IVaults.sol";
import "src/interfaces/IPedersenHash.sol";

import "src/interactions/Deposit.sol";
import "src/interactions/Withdrawal.sol";

import "src/interactions/Interactions.sol";
import "src/interactions/MMRegistry.sol";

import "forge-std/console.sol";

contract InvisibleL1 is Interactions, MMRegistry {
    uint64 s_txBatchId;

    mapping(uint64 => uint256) public s_txBatchId2StateRoot;
    mapping(uint64 => uint256) public s_txBatchId2Timestamp;

    mapping(uint64 => bool) public s_accumulatedHashesRelayed; // txBatchId => wasRelayed

    address s_admin;
    address s_L1MessageRelay; // The contract that passes messages from the L1 contract

    uint256 constant INIT_STATE_ROOT =
        2450644354998405982022115704618884006901283874365176806194200773707121413423;

    constructor(
        address _admin,
        address _L1MessageRelay
    ) MMRegistry(address(1234)) {
        s_txBatchId = 0;
        s_txBatchId2StateRoot[0] = INIT_STATE_ROOT;
        s_admin = _admin;
        s_L1MessageRelay = _L1MessageRelay;
    }

    // modifier onlyAdmin() {
    //     require(msg.sender == s_admin, "Only admin");
    //     _;
    // }

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
            WithdrawalTransactionOutput[] memory withdrawals,
            MMRegistrationOutput[] memory registrations
        ) = ProgramOutputParser.parseProgramOutput(programOutput);

        // require(dexState.txBatchId == s_txBatchId, "invalid txBatchId");
        // require(
        //     dexState.initStateRoot == s_txBatchId2StateRoot[s_txBatchId],
        //     "Invalid state root"
        // );
        // require(
        //     dexState.globalExpirationTimestamp < block.timestamp,
        //     "Invalid expiration timestamp"
        // );
        //

        updatePendingDeposits(deposits, s_txBatchId);
        storeNewBatchWithdrawalOutputs(withdrawals, s_txBatchId);
        updatePendingRegistrations(registrations, s_txBatchId);

        s_txBatchId += 1;
        s_txBatchId2StateRoot[s_txBatchId] = dexState.finalStateRoot;
        s_txBatchId2Timestamp[s_txBatchId] = block.timestamp;
    }

    function relayAccumulatedHashes(
        uint64 txBatchId,
        AccumulatedHashesOutput[] memory accumulatedHashOutputs
    ) public {
        require(
            !s_accumulatedHashesRelayed[txBatchId],
            "Hashes Already Relayed"
        );

        for (uint256 i = 0; i < accumulatedHashOutputs.length; i++) {
            uint32 chainId = accumulatedHashOutputs[i].chainId;
            uint256 depositHash = accumulatedHashOutputs[i].depositHash;
            uint256 withdrawalHash = accumulatedHashOutputs[i].withdrawalHash;

            // Todo: Relay the hashes to the relevant L2s
        }

        s_accumulatedHashesRelayed[txBatchId] = true;
    }
}
