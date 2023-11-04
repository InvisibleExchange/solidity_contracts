// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IVaults.sol";

import "../helpers/tokenInfo.sol";
import "../helpers/parseProgramOutput.sol";
import "../vaults/VaultManager.sol";

import "forge-std/console.sol";

// Todo: instead of providing the starkKey, we could just provide the initial Ko from the off-chain state

abstract contract Deposit is TokenInfo, VaultManager {
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

    // Todo: figure this out
    mapping(address => uint256) public s_address2PubKey;

    uint64 CHAIN_ID = 9090909;

    uint64 private s_depositCount = 0;

    struct DepositCancelation {
        address depositor;
        uint256 pubKey;
        uint32 tokenId;
    }

    DepositCancelation[] public s_depositCencelations;

    function updatePendingDeposits(
        DepositTransactionOutput[] memory depositOutputs,
        uint64 txBatchId
    ) internal {
        for (uint256 i = 0; i < depositOutputs.length; i++) {
            DepositTransactionOutput memory depositOutput = depositOutputs[i];

            (
                uint64 depositId,
                uint32 tokenId,
                uint64 depositAmount,
                uint256 depositPubKey
            ) = ProgramOutputParser.uncompressDepositOutput(depositOutput);

            require(
                s_pendingDeposits[depositPubKey][tokenId] >= depositAmount,
                "An invalid deposit was executed offchain"
            );

            s_pendingDeposits[depositPubKey][tokenId] -= depositAmount;
        }
        emit UpdatedPendingDepositsEvent(block.timestamp, txBatchId);

        // ? After updating the deposits update the cancelations as well
        cancelDeposits();
    }

    //

    function _makeDeposit(
        address tokenAddress,
        uint256 amount,
        uint256 starkKey
    ) internal returns (uint64 newAmountDeposited) {
        // Todo: figure out how the stark key should fit into all this (should we just verify eth signatures in deposits)
        // todo: figure out if address-pubKey should be one to one or not
        require(starkKey < 2 ** 251 + 17 * 2 ** 192 + 1, "Invalid stark Key");
        require(starkKey > 0, "Invalid stark Key");

        require(msg.sender != address(0), "Invalid depositior address");

        if (msg.value > 0) {
            return _makeEthDeposit(starkKey);
        } else {
            return _makeErc20Deposit(tokenAddress, amount, starkKey);
        }
    }

    function _makeEthDeposit(
        uint256 starkKey
    ) private returns (uint64 newAmountDeposited) {
        //

        uint64 depositAmountScaled = scaleDown(msg.value, TokenInfo.ETH_ID);

        uint64 pendingAmount = s_pendingDeposits[starkKey][TokenInfo.ETH_ID];
        s_pendingDeposits[starkKey][TokenInfo.ETH_ID] =
            pendingAmount +
            depositAmountScaled;

        uint64 depositId = CHAIN_ID * 2 ** 32 + s_depositCount;
        s_depositCount += 1;

        emit DepositEvent(
            depositId,
            starkKey,
            TokenInfo.ETH_ID,
            depositAmountScaled,
            block.timestamp
        );

        return (pendingAmount + depositAmountScaled);
    }

    function _makeErc20Deposit(
        address tokenAddress,
        uint256 amount,
        uint256 starkKey
    ) private returns (uint64 newAmountDeposited) {
        //

        makeErc20VaultDeposit(tokenAddress, amount);

        uint32 tokenId = getTokenId(tokenAddress);
        uint64 depositAmountScaled = scaleDown(amount, tokenId);

        uint64 pendingAmount = s_pendingDeposits[starkKey][tokenId];
        s_pendingDeposits[starkKey][tokenId] =
            pendingAmount +
            depositAmountScaled;

        uint64 depositId = CHAIN_ID * 2 ** 32 + s_depositCount;
        s_depositCount += 1;

        emit DepositEvent(
            depositId,
            starkKey,
            tokenId,
            depositAmountScaled,
            block.timestamp
        );

        return (pendingAmount + depositAmountScaled);
    }

    // ----------------------------------------------------------------------------
    // Cancelations

    function _startCancelDeposit(
        address tokenAddress,
        uint256 starkKey
    ) internal {
        // Todo: figure out how the stark key should fit into all this (should we just verify eth signatures in deposits)
        // todo: figure out if address-pubKey should be one to one or not
        require(starkKey < 2 ** 251 + 17 * 2 ** 192 + 1, "Invalid stark key");

        require(msg.sender != address(0), "msg.sender can't be 0");

        // ? Get the token id and scale the amount
        uint32 tokenId = getTokenId(tokenAddress);

        uint64 pendingAmount = s_pendingDeposits[starkKey][tokenId];
        if (pendingAmount == 0) return;

        s_depositCencelations.push(
            DepositCancelation(msg.sender, starkKey, tokenId)
        );

        emit DepositCancelEvent(starkKey, tokenAddress, block.timestamp);
    }

    function cancelDeposits() private {
        if (s_depositCencelations.length == 0) return;

        for (uint256 i = 0; i < s_depositCencelations.length; i++) {
            DepositCancelation storage cancelation = s_depositCencelations[i];
            uint64 pendingAmount = s_pendingDeposits[cancelation.pubKey][
                cancelation.tokenId
            ];

            if (pendingAmount == 0) continue;

            uint256 refundAmount = scaleUp(pendingAmount, cancelation.tokenId);

            if (cancelation.tokenId == TokenInfo.ETH_ID) {} else {
                address tokenAddress = getTokenAddress(cancelation.tokenId);

                makeErc20VaultWithdrawal(
                    tokenAddress,
                    cancelation.depositor,
                    refundAmount,
                    0
                );
            }
        }

        delete s_depositCencelations;
    }

    // ----------------------------------------------------------------------------
    // View

    function _getPendingDepositAmount(
        uint256 starkKey,
        address tokenAddress
    ) internal view returns (uint256) {
        uint32 tokenId = getTokenId(tokenAddress);
        uint64 pendingAmount = s_pendingDeposits[starkKey][tokenId];
        return scaleUp(pendingAmount, tokenId);
    }
}
