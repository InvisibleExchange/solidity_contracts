// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../libraries/ProgramOutputParser.sol";
import "../../MMRegistry/MMRegistryManager.sol";
import "../../MMRegistry/MMRegistryUpdates.sol";

import "../VaultManager.sol";

import "../../storage/MainStorage.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

abstract contract MMRegistry is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    MMRegistryManager,
    MainStorage
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
        require(
            s_pendingCloseRequests[mmPositionAddress].txBatchId == 0,
            "position closed"
        );

        uint32 usdcTokenId = USDC_TOKEN_ID;
        address usdcTokenAddress = s_tokenId2Address[usdcTokenId];

        // ? Transfer the usdc from the user to the vault
        VaultManager.makeErc20VaultDeposit(usdcTokenAddress, usdcAmount);

        // ? Store the pending request in the contract
        uint64 scaledAmount = scaleDown(usdcAmount, usdcTokenId);

        s_pendingAddLiqudityRequests[msg.sender][
            mmPositionAddress
        ] += scaledAmount;

        uint32 mmActionId = s_mmActionId;
        s_mmActionId++;

        emit AddLiquidity(
            msg.sender,
            mmPositionAddress,
            scaledAmount,
            mmActionId
        );
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
    // * REMOVE LIQUIDITY --------------------------------------------
    function removeLiquidity(
        uint32 syntheticToken,
        uint256 mmPositionAddress
    ) external {
        require(isMarketRegistered(syntheticToken), "market is not registered");
        require(
            isAddressRegistered(mmPositionAddress),
            "position address is not registered"
        );
        require(
            s_pendingCloseRequests[mmPositionAddress].txBatchId == 0,
            "position closed"
        );

        // ? Get the active liquidity position of the user
        LiquidityInfo memory activeLiq = s_activeLiqudity[msg.sender][
            mmPositionAddress
        ];

        address usdcTokenAddress = s_tokenId2Address[USDC_TOKEN_ID];

        // ? If the position has been closed by the owner, we return the users share directly
        if (s_closedPositionLiqudity[mmPositionAddress].vlpAmountSum > 0) {
            // ? Get the user's share of the closed position liquidity
            uint64 userShare = (activeLiq.vlpAmount *
                s_closedPositionLiqudity[mmPositionAddress].returnCollateral) /
                s_closedPositionLiqudity[mmPositionAddress].vlpAmountSum;

            uint256 scaledAmount = scaleUp(userShare, USDC_TOKEN_ID);

            s_pendingWithdrawals[msg.sender][usdcTokenAddress] += scaledAmount;
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
        require(
            s_pendingRemoveLiqudityRequests[removeReqHash] == 0,
            "request already pending"
        );

        s_pendingRemoveLiqudityRequests[removeReqHash] = block.timestamp;

        uint32 mmActionId = s_mmActionId;
        s_mmActionId++;

        emit RemoveLiquidity(
            msg.sender,
            mmPositionAddress,
            activeLiq.initialValue,
            activeLiq.vlpAmount,
            mmActionId
        );
    }
    // * CLOSE MM POSITION --------------------------------------------
    function initiateMMClose(uint256 mmPositionAddress) external {
        PerpMMRegistration memory registration = s_perpRegistrations[
            mmPositionAddress
        ];

        require(
            registration.mmOwner == msg.sender,
            "Only the owner can close the position"
        );

        // ? Set the position as pending close
        s_pendingCloseRequests[mmPositionAddress] = CloseRequest(
            block.timestamp,
            s_txBatchId,
            registration.mmOwner
        );
    }

    function closePerpMarketMaker(uint256 mmPositionAddress) external {
        require(
            s_pendingCloseRequests[mmPositionAddress].txBatchId > 0,
            "Initiate close first"
        );
        require(
            s_txBatchId > s_pendingCloseRequests[mmPositionAddress].txBatchId,
            "Wait for the next batch to close the position"
        );
        require(
            s_pendingCloseRequests[mmPositionAddress].mmOwner == msg.sender
        );

        // ? Get the aggregate value provided to the mm
        uint64 initialValueSum = s_providedUsdcLiquidity[mmPositionAddress];
        uint64 vlpAmountSum = s_aggregateVlpIssued[mmPositionAddress];

        uint32 mmActionId = s_mmActionId;
        s_mmActionId++;
        emit ClosePositionEvent(
            mmPositionAddress,
            msg.sender,
            initialValueSum,
            vlpAmountSum,
            mmActionId
        );
    }
    // * WITHDRAW FUNDS --------------------------------------------
    function withdrawalLiquidity() external nonReentrant {
        uint32 usdcTokenId = USDC_TOKEN_ID;
        address usdcTokenAddress = s_tokenId2Address[usdcTokenId];
        // We send the event {depositor, amount} to the depositor
        uint256 amount = s_pendingWithdrawals[msg.sender][usdcTokenAddress];
        if (amount == 0) {
            return;
        }
        s_pendingWithdrawals[msg.sender][usdcTokenAddress] = 0;
        // ? Make withdrawal from the vault
        VaultManager.makeErc20VaultWithdrawal(
            usdcTokenAddress,
            msg.sender,
            amount
        );
    }
}
