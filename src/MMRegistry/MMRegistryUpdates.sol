// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../libraries/ProgramOutputParser.sol";
import "./MMRegistryManager.sol";

import "../storage/MMRegistryStorage.sol";
import "../core/VaultManager.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

abstract contract MMRegistryUpdates is MMRegistryStorage, VaultManager {
    // * UPDATE PENDING * //
    function updatePendingRegistrations(
        OnChainMMActionOutput[] memory registrations
    ) internal {
        for (uint256 i = 0; i < registrations.length; i++) {
            OnChainMMActionOutput memory registration = registrations[i];

            (
                uint32 vlpToken,
                uint64 vlpAmount,
                uint256 mmAddress
            ) = ProgramOutputParser.uncompressRegistrationOutput(registration);

            // ? isPerp
            PerpMMRegistration storage perpRegistration = s_perpRegistrations[
                mmAddress
            ];

            if (
                perpRegistration.vlpTokenId == vlpToken &&
                perpRegistration.positionAddress == mmAddress
            ) {
                perpRegistration.vlpAmount = vlpAmount;
            }
        }
    }

    // * ADD LIQUIDITY --------------------------------------------
    function updatePendingAddLiquidityUpdates(
        OnChainMMActionOutput[] memory addLiqOutputs
    ) internal {
        for (uint i = 0; i < addLiqOutputs.length; i++) {
            (
                uint64 initialAmount,
                uint64 vlpAmount,
                uint256 mmAddress,
                address depositor
            ) = ProgramOutputParser.uncompressAddLiquidityOutput(
                    addLiqOutputs[i]
                );

            // ? Update the pending request that was just processed
            s_pendingAddLiqudityRequests[depositor][mmAddress] -= vlpAmount;

            // ? If position is closed/closing we should prevent new deposits
            if (s_pendingCloseRequests[mmAddress] > 0) {
                s_pendingWithdrawals[depositor] += scaleUp(
                    initialAmount,
                    USDC_TOKEN_ID
                );

                continue;
            }

            // ? Update the active liquidity position
            s_activeLiqudity[depositor][mmAddress]
                .initialValue += initialAmount;
            s_activeLiqudity[depositor][mmAddress].vlpAmount += vlpAmount;

            // ? Keep track of the total liquidity provided to the mm (used when closing position)
            s_providedUsdcLiquidity[mmAddress] += initialAmount;
            s_aggregateVlpIssued[mmAddress] += vlpAmount;
        }

        for (uint i = s_pendingCancellations.length; i > 0; i--) {
            Cancelation memory cancelation = s_pendingCancellations[i - 1];

            uint64 pendingAmount = s_pendingAddLiqudityRequests[
                cancelation.depositor
            ][cancelation.mmAddress];
            uint256 scaledAmount = scaleUp(pendingAmount, USDC_TOKEN_ID);
            s_pendingWithdrawals[cancelation.depositor] += scaledAmount;

            s_pendingCancellations.pop();
        }
    }

    // * REMOVE LIQUIDITY --------------------------------------------
    function updatePendingRemoveLiquidityUpdates(
        OnChainMMActionOutput[] memory removeLiqOutputs
    ) internal {
        for (uint i = 0; i < removeLiqOutputs.length; i++) {
            (
                uint64 initialAmount,
                uint64 vlpAmount,
                uint64 returnCollateral,
                uint256 mmAddress,
                address depositor
            ) = ProgramOutputParser.uncompressRemoveLiquidityOutput(
                    removeLiqOutputs[i]
                );

            LiquidityInfo storage activeLiq = s_activeLiqudity[depositor][
                mmAddress
            ];

            // ? Update the active liquidity position
            activeLiq.initialValue -= initialAmount;
            activeLiq.vlpAmount -= vlpAmount;

            // ? Update the aggregate liquidity provided to the mm
            s_providedUsdcLiquidity[mmAddress] -= initialAmount;
            s_aggregateVlpIssued[mmAddress] -= vlpAmount;

            // ? Take 20% of the profit as a fee
            uint64 mmFee;
            if (returnCollateral > initialAmount) {
                mmFee = (returnCollateral - initialAmount) / 5;
            } else {
                mmFee = 0;
            }
            uint256 scaledFee = scaleUp(mmFee, USDC_TOKEN_ID);
            address mmOwner = s_perpRegistrations[mmAddress].mmOwner;
            s_pendingWithdrawals[mmOwner] += scaledFee;

            // ? The user can than call withdrawalLiquidity to withdraw the funds
            uint256 scaledAmount = scaleUp(
                returnCollateral - mmFee,
                USDC_TOKEN_ID
            );
            s_pendingWithdrawals[depositor] += scaledAmount;
        }
    }

    // * CLOSE MM POSITION --------------------------------------------
    function updatePendingCloseMMUpdates(
        OnChainMMActionOutput[] memory closeMMOutputs
    ) internal {
        for (uint i = 0; i < closeMMOutputs.length; i++) {
            (
                uint64 initialValueSum,
                uint64 vlpAmountSum,
                uint64 returnCollateral,
                uint256 mmAddress
            ) = ProgramOutputParser.uncompressCloseMMOutput(closeMMOutputs[i]);

            // ? Update the aggregate liquidity provided to the mm
            s_providedUsdcLiquidity[mmAddress] = 0;
            s_aggregateVlpIssued[mmAddress] = 0;

            // ? Take 20% of the profit as a fee
            uint64 mmFee;
            if (returnCollateral > initialValueSum) {
                mmFee = (returnCollateral - initialValueSum) / 5;
            } else {
                mmFee = 0;
            }
            uint256 scaledFee = scaleUp(mmFee, USDC_TOKEN_ID);
            address mmOwner = s_perpRegistrations[mmAddress].mmOwner;
            s_pendingWithdrawals[mmOwner] += scaledFee;

            // ? Store the liquidity info of the LPs
            // ? The LPs  can then claim by calling remove liquidity
            s_closedPositionLiqudity[mmAddress] = ClosedPositionLiquidityInfo(
                vlpAmountSum,
                returnCollateral - mmFee
            );

            delete s_perpRegistrations[mmAddress];
        }
    }
}
