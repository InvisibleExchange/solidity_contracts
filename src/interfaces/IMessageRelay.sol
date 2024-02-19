// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";

interface IL1MessageRelay {
    function storeAccumulatedHashes(
        uint32 _dstEid,
        uint32 txBatchId,
        bytes32 accumulatedDepositHash,
        bytes32 accumulatedWithdrawalHash
    ) external;

    function estimateMessageFee(
        uint32 _dstEid,
        uint32 txBatchId,
        bytes calldata _options
    ) external view returns (MessagingFee memory fee, bytes memory options);

    function sendAccumulatedHashes(
        uint32 _dstEid,
        uint32 txBatchId,
        bytes calldata _options
    ) external payable;
}

interface IL2MessageRelay {
    function sendAcknowledgment(uint32 _txBatchId) external;

    function processAccumulatedDepositHash(
        uint32 processedTxBatchId,
        bytes32 accDepositHash
    ) external;

    function processAccumulatedWithdrawalHash(
        uint32 processedTxBatchId,
        bytes32 accWithdrawalHash
    ) external;

    function latestAccumulatedDepositHash() external view returns (bytes32);

    function accumulatedDepositHashes(uint32) external view returns (bytes32);
    function accumulatedWithdrawalHashes(
        uint32
    ) external view returns (bytes32);
}
