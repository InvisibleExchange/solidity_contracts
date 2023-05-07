// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IVaults.sol";

import "../helpers/tokenInfo.sol";
import "../helpers/parseProgramOutput.sol";
import "../vaults/VaultRegistry.sol";

// Todo: instead of providing the starkKey, we could just provide the initial Ko from the off-chain state

contract Deposit is TokenInfo, ProgramOutputParser, VaultRegistry {
    event DepositEvent(
        uint64 indexed depositId,
        uint256 indexed pubKey,
        uint64 tokenId,
        uint64 depositAmountScaled,
        uint256 timestamp
    );
    event DepositCancelEvent(
        uint256 pubKey,
        address tokenAddress,
        uint256 timestamp
    );
    event UpdatedPendingDepositsEvent(uint256 timestamp, uint64 txBatchId);

    mapping(uint256 => mapping(uint64 => uint64)) public s_pendingDeposits; // pubKey => tokenId => amountScaled

    mapping(address => mapping(address => uint256)) public s_pendingRefunds; // userAddress => tokenAddress => amount  (amounts from cancelled deposits to be claimed)

    // Todo: figure this out
    mapping(address => uint256) public s_address2PubKey;

    uint64 private s_depositId = 0;

    struct DepositCancelation {
        address depositor;
        uint256 pubKey;
        uint64 tokenId;
    }

    DepositCancelation[] public s_depositCencelations;

    // todo: Only allow the backend to call this function
    function updatePendingDeposits(
        DepositTransactionOutput[] memory depositOutputs,
        uint64 txBatchId
    ) internal {
        for (uint256 i = 0; i < depositOutputs.length; i++) {
            DepositTransactionOutput memory depositOutput = depositOutputs[i];

            (
                uint64 depositId,
                uint64 tokenId,
                uint64 depositAmount,
                uint256 depositPubKey
            ) = uncompressDepositOutput(depositOutput);

            require(
                s_pendingDeposits[depositPubKey][tokenId] >= depositAmount,
                "Offchain deposit > Onchain deposit "
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

        require(msg.sender != address(0), "Invalid stark Key");

        if (msg.value > 0) {
            return makeEthDeposit(starkKey);
        }

        address vaultAddress = getAssetVaultAddress(tokenAddress);
        IERC20 token = IERC20(tokenAddress);
        bool success = token.transferFrom(msg.sender, vaultAddress, amount);

        require(success, "Transfer failed");

        // ? Get the token id and scale factor
        uint64 tokenId = getTokenId(tokenAddress);
        uint64 depositAmountScaled = scaleDown(amount, tokenId);

        // ? Add the amount to the pending deposits
        uint64 pendingAmount = s_pendingDeposits[starkKey][tokenId];
        s_pendingDeposits[starkKey][tokenId] =
            pendingAmount +
            depositAmountScaled;

        uint64 depositId = uint64(
            uint256(keccak256(abi.encodePacked(s_depositId)))
        );
        s_depositId = depositId + 1;

        emit DepositEvent(
            depositId,
            starkKey,
            tokenId,
            depositAmountScaled,
            block.timestamp
        );

        return (pendingAmount + depositAmountScaled);
    }

    function makeEthDeposit(
        uint256 starkKey
    ) private returns (uint64 newAmountDeposited) {
        address payable vaultAddress = payable(getETHVaultAddress());

        (bool sent, bytes memory _data) = vaultAddress.call{value: msg.value}(
            ""
        );
        require(sent, "Failed to send Ether");

        // ? Get the scale factor
        uint64 depositAmountScaled = scaleDown(msg.value, TokenInfo.ETH_ID);

        // ? Add the amount to the pending deposits
        uint64 pendingAmount = s_pendingDeposits[starkKey][TokenInfo.ETH_ID];
        s_pendingDeposits[starkKey][TokenInfo.ETH_ID] =
            pendingAmount +
            depositAmountScaled;

        uint64 depositId = uint64(
            uint256(keccak256(abi.encodePacked(s_depositId)))
        );
        s_depositId = depositId + 1;

        emit DepositEvent(
            depositId,
            starkKey,
            TokenInfo.ETH_ID,
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
        uint64 tokenId = getTokenId(tokenAddress);

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

            if (cancelation.tokenId == TokenInfo.ETH_ID) {
                address vaultAddress = getETHVaultAddress();
                IETHVault vault = IETHVault(vaultAddress);

                vault.increaseWithdrawableAmount(
                    cancelation.depositor,
                    refundAmount
                );
            } else {
                address tokenAddress = getTokenAddress(cancelation.tokenId);

                address vaultAddress = getAssetVaultAddress(tokenAddress);
                IAssetVault vault = IAssetVault(vaultAddress);

                vault.increaseWithdrawableAmount(
                    cancelation.depositor,
                    tokenAddress,
                    refundAmount
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
        uint64 tokenId = getTokenId(tokenAddress);
        uint64 pendingAmount = s_pendingDeposits[starkKey][tokenId];
        return scaleUp(pendingAmount, tokenId);
    }
}
