// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import {OAppSender, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import {OAppReceiver, Origin} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppReceiver.sol";
import {OAppCore} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppCore.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

struct AccumulatedHashesMessage {
    uint32 txBatchId;
    bytes32 accumulatedDepositHash;
    bytes32 accumulatedWithdrawalHash;
}

struct L2AcknowledgmentMessage {
    uint32 txBatchId;
    bool depositsVerified;
    bool withdrawalsVerified;
}

contract L1MessageRelay is OAppSender, OAppReceiver {
    event MessageSent(bytes message, uint32 dstEid);
    event MessageReceived(string message, uint32 senderEid, bytes32 sender);

    // xyz: 0x00030100110100000000000000000000000000030d40

    mapping(uint32 => mapping(uint32 => bytes32))
        public s_accumulatedDepositHashes; // senderEid -> txBatchId -> depositsAcknowledged
    mapping(uint32 => mapping(uint32 => bytes32))
        public s_accumulatedWithdrawalHashes; // senderEid -> txBatchId -> depositsAcknowledged

    mapping(uint32 => mapping(uint32 => bool)) public s_depositAcknowledgments; // senderEid -> txBatchId -> depositsAcknowledged
    mapping(uint32 => mapping(uint32 => bool))
        public s_withdrawalAcknowledgments; // senderEid -> txBatchId -> depositsAcknowledged

    address s_invisibleAddress;

    constructor(
        address _endpoint,
        address _owner
    ) OAppCore(_endpoint, _owner) Ownable(_owner) {}

    function setInvisibleAddress(address _invAddress) external onlyOwner {
        s_invisibleAddress = _invAddress;
    }

    // * ================== * //

    function storeAccumulatedHashes(
        uint32 _dstEid,
        uint32 txBatchId,
        bytes32 accumulatedDepositHash,
        bytes32 accumulatedWithdrawalHash
    ) external {
        require(msg.sender == s_invisibleAddress, "Invalid sender");

        s_accumulatedDepositHashes[_dstEid][txBatchId] = accumulatedDepositHash;
        s_accumulatedWithdrawalHashes[_dstEid][
            txBatchId
        ] = accumulatedWithdrawalHash;
    }

    function estimateMessageFee(
        uint32 _dstEid,
        uint32 txBatchId,
        bytes calldata _options
    ) public view returns (MessagingFee memory, bytes memory) {
        bytes32 accumulatedDepositHash = s_accumulatedDepositHashes[_dstEid][
            txBatchId
        ];
        bytes32 accumulatedWithdrawalHash = s_accumulatedWithdrawalHashes[
            _dstEid
        ][txBatchId];

        AccumulatedHashesMessage memory message = AccumulatedHashesMessage(
            txBatchId,
            accumulatedDepositHash,
            accumulatedWithdrawalHash
        );

        bytes memory _payload = abi.encode(message);

        MessagingFee memory fee = _quote(_dstEid, _payload, _options, false);

        return (fee, _payload);
    }

    function sendAccumulatedHashes(
        uint32 _dstEid,
        uint32 txBatchId,
        bytes calldata _options
    ) external payable {
        (MessagingFee memory fee, bytes memory _payload) = estimateMessageFee(
            _dstEid,
            txBatchId,
            _options
        );

        // ? Verify the balance is sufficient to send the transaction
        require(msg.value >= fee.nativeFee, "Insufficient balance");

        // MessagingReceipt memory _receipt =
        _lzSend(_dstEid, _payload, _options, fee, payable(msg.sender));

        emit MessageSent(_payload, _dstEid);
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata payload,
        address,
        bytes calldata
    ) internal override {
        L2AcknowledgmentMessage memory message = abi.decode(
            payload,
            (L2AcknowledgmentMessage)
        );

        // Extract the sender's EID from the origin
        uint32 senderEid = _origin.srcEid;
        bytes32 sender = _origin.sender;

        // TODO: Do we need to verify the sender is a registered peer?

        if (message.depositsVerified) {
            s_depositAcknowledgments[senderEid][message.txBatchId] = true;
        }
        if (message.withdrawalsVerified) {
            s_withdrawalAcknowledgments[senderEid][message.txBatchId] = true;
        }
        // TODO: What do we do if the deposits/withdrawals are not verified?

        // TODO: What do we do with this information?
    }

    function oAppVersion()
        public
        pure
        virtual
        override(OAppSender, OAppReceiver)
        returns (uint64 senderVersion, uint64 receiverVersion)
    {
        return (SENDER_VERSION, RECEIVER_VERSION);
    }
}
