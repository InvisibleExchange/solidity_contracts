// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./interfaces/IPedersenHash.sol";
import "./interfaces/IEscapeVerifier.sol";

import "./libraries/ProgramOutputParser.sol";

import "./core/VaultManager.sol";
import "./core/Interactions.sol";
import "./core/EscapeVerifier.sol";
import "./core/MMRegistry.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract Invisible is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    VaultManager,
    Interactions,
    MMRegistry
{
    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        __VaultManager_init(payable(initialOwner));

        s_txBatchId = 0;
        s_txBatchId2StateRoot[s_txBatchId] = INIT_STATE_ROOT;

        version = 1;
    }

    function setEscapeVerifier(address newVerirfier) external onlyOwner {
        s_escapeVerifier = newVerirfier;

        _VMsetEscapeVerifier(newVerirfier);
    }

    /// @notice Processes a new L1 update
    /// @dev After the proof is verified on L1 this will be called to update the state and process deposits/withdrawals. The contract will
    /// then send the accumulated deposit/withdrawal hashes to the relevant L2s. This function is available only on the L1.
    /// @param programOutput the output of the cairo program
    function updateStateAfterTxBatch(
        uint256[] calldata programOutput
    ) external onlyOwner nonReentrant {
        (
            GlobalDexState memory dexState,
            AccumulatedHashesOutput[] memory hashes,
            DepositTransactionOutput[] memory deposits,
            WithdrawalTransactionOutput[] memory withdrawals,
            OnChainMMActionOutput[] memory registrationsArr,
            OnChainMMActionOutput[] memory addLiquidityArr,
            OnChainMMActionOutput[] memory removeLiquidityArr,
            OnChainMMActionOutput[] memory closeMMArr,
            EscapeOutput[] memory escapes,
            PositionEscapeOutput[] memory positionEscapes
        ) = ProgramOutputParser.parseProgramOutput(programOutput);

        require(dexState.txBatchId == s_txBatchId, "invalid txBatchId");
        require(
            dexState.initStateRoot == s_txBatchId2StateRoot[s_txBatchId],
            "Invalid state root"
        );
        require(
            dexState.globalExpirationTimestamp < block.timestamp,
            "Invalid expiration timestamp"
        );

        updatePendingDeposits(deposits, s_txBatchId);
        processBatchWithdrawalOutputs(withdrawals, s_txBatchId);

        updatePendingRegistrations(registrationsArr);
        updatePendingAddLiquidityUpdates(addLiquidityArr);
        updatePendingRemoveLiquidityUpdates(removeLiquidityArr);
        updatePendingCloseMMUpdates(closeMMArr);

        IEscapeVerifier(s_escapeVerifier).updatePendingEscapes(escapes);
        IEscapeVerifier(s_escapeVerifier).updatePendingPositionEscapes(
            positionEscapes
        );

        s_txBatchId += 1;
        s_txBatchId2StateRoot[s_txBatchId] = dexState.finalStateRoot;
        s_txBatchId2Timestamp[s_txBatchId] = block.timestamp;
    }

    function relayAccumulatedHashes(
        uint64 txBatchId,
        AccumulatedHashesOutput[] memory accumulatedHashOutputs
    ) internal {
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

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
