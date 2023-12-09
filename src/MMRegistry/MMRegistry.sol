// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/ProgramOutputParser.sol";
import "./MMRegistryManager.sol";

import "../core/VaultManager.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract MMRegistry is
    OwnableUpgradeable,
    MMRegistryManager,
    VaultManager
{
    // * ADD LIQUIDITY --------------------------------------------
    function provideLiquidity(
        uint32 syntheticToken,
        uint256 mmPositionAddress,
        uint256 usdcAmount
    ) external {
        require(isMarketRegistered(syntheticToken), "market isn't registered");
        require(
            isAddressRegistered(mmPositionAddress),
            "position address isn't registered"
        );

        // ? If position is closed/closing we should prevent new deposits
        require(!s_pendingCloseRequests[mmPositionAddress], "position closed");

        uint32 usdcTokenId = 55555;
        address usdcTokenAddress = s_tokenId2Address[usdcTokenId];
        bool success = IERC20(usdcTokenAddress).transfer(
            address(this),
            usdcAmount
        );
        require(success, "Transfer failed");

        // ? Store the pending request in the contract
        uint64 scaledAmount = scaleDown(usdcAmount, usdcTokenId);
        s_pendingAddLiqudityRequests[msg.sender][
            mmPositionAddress
        ] += scaledAmount;

        emit AddLiquidity(msg.sender, mmPositionAddress, scaledAmount);
    }

    function tryCancelAddLiquidity(uint256 mmPositionAddress) external {
        require(
            isAddressRegistered(mmPositionAddress),
            "position address isn't registered"
        );

        // ? store the cancellation request that will cancel the
        // ? add liquidity request if it hasn't been processed yet
        s_pendingCancellations.push(Cancelation(msg.sender, mmPositionAddress));
    }

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
            uint256 scaledAmount = scaleUp(pendingAmount, 55555);
            s_pendingWithdrawals[cancelation.depositor] += scaledAmount;

            s_pendingCancellations.pop();
        }
    }

    // * REMOVE LIQUIDITY --------------------------------------------
    function removeLiquidity(
        uint32 syntheticToken,
        uint256 mmPositionAddress
    ) external {
        require(isMarketRegistered(syntheticToken), "market isn't registered");
        require(
            isAddressRegistered(mmPositionAddress),
            "position address isn't registered"
        );

        // ? Get the active liquidity position of the user
        LiquidityInfo memory activeLiq = s_activeLiqudity[msg.sender][
            mmPositionAddress
        ];

        // ? If the position has been closed by the owner, we return the users share directly
        if (s_closedPositionLiqudity[mmPositionAddress].vlpAmountSum > 0) {
            // ? Get the user's share of the closed position liquidity
            uint64 userShare = (activeLiq.vlpAmount *
                s_closedPositionLiqudity[mmPositionAddress].returnCollateral) /
                s_closedPositionLiqudity[mmPositionAddress].vlpAmountSum;

            uint256 scaledAmount = scaleUp(userShare, 55555);

            s_pendingWithdrawals[msg.sender] += scaledAmount;

            s_closedPositionLiqudity[mmPositionAddress]
                .vlpAmountSum -= activeLiq.vlpAmount;
            s_closedPositionLiqudity[mmPositionAddress]
                .returnCollateral -= userShare;

            return;
        }

        // ? Store the hash of the withdrawal request (used to prevent censorship)
        bytes32 removeReqHash = keccak256(
            abi.encodePacked(msg.sender, activeLiq.vlpAmount)
        );
        s_pendingRemoveLiqudityRequests[removeReqHash] = true;

        emit RemoveLiquidity(
            msg.sender,
            mmPositionAddress,
            activeLiq.initialValue,
            activeLiq.vlpAmount
        );
    }

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
            s_mmFees[mmAddress] += mmFee;

            // ? The user can than call withdrawalLiquidity to withdraw the funds
            uint256 scaledAmount = scaleUp(returnCollateral - mmFee, 55555);
            s_pendingWithdrawals[depositor] += scaledAmount;
        }
    }

    // * CLOSE MM POSITION --------------------------------------------
    function closePerpMarketMaker(uint256 mmPositionAddress) external {
        PerpMMRegistration memory registration = s_perpRegistrations[
            mmPositionAddress
        ];

        require(
            registration.mmOwner == msg.sender,
            "Only the owner can close the position"
        );

        // ? Set the position as pending close
        s_pendingCloseRequests[mmPositionAddress] = true;

        // ? Get the aggregate value provided to the mm
        uint64 initialValueSum = s_providedUsdcLiquidity[mmPositionAddress];
        uint64 vlpAmountSum = s_aggregateVlpIssued[mmPositionAddress];

        emit ClosePositionEvent(
            mmPositionAddress,
            msg.sender,
            initialValueSum,
            vlpAmountSum
        );
    }

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
            s_mmFees[mmAddress] += mmFee;

            // ? Store the liquidity info of the LPs
            // ? The LPs  can then claim by calling remove liquidity
            s_closedPositionLiqudity[mmAddress] = ClosedPositionLiquidityInfo(
                vlpAmountSum,
                returnCollateral - mmFee
            );
        }
    }

    // * WITHDRAW FUNDS --------------------------------------------
    // TODO: NONREENTRANT
    function withdrawalLiquidity() external {
        // We send the event {depositor, amount} to the depositor
        uint256 amount = s_pendingWithdrawals[msg.sender];

        if (amount == 0) {
            return;
        }

        s_pendingWithdrawals[msg.sender] = 0;

        uint32 usdcTokenId = 55555;
        address usdcTokenAddress = s_tokenId2Address[usdcTokenId];
        bool success = IERC20(usdcTokenAddress).transfer(msg.sender, amount);
        require(success, "Transfer failed");
    }
}
