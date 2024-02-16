// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import {OAppSender, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import {OAppReceiver, Origin} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppReceiver.sol";
import {OAppCore} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppCore.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./MessageRelay.sol";

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

    mapping(uint32 => mapping(uint32 => bool)) public s_depositAcknowledgments; // senderEid -> txBatchId -> depositsAcknowledged
    mapping(uint32 => mapping(uint32 => bool))
        public s_withdrawalAcknowledgments; // senderEid -> txBatchId -> depositsAcknowledged

    uint64 constant chainId = 1; // TODO:

    address public s_invisibleAddress;

    constructor(
        address _endpoint,
        address _owner
    ) OAppCore(_endpoint, _owner) Ownable(_owner) {}

    function setInvisibleAddress(address _invAddress) external onlyOwner {
        s_invisibleAddress = _invAddress;
    }

    // * ================== * //

    function sendAccumulatedHash(
        uint32 _dstEid,
        uint32 txBatchId,
        bytes32 accumulatedDepositHash,
        bytes32 accumulatedWithdrawalHash,
        bytes calldata _options
    ) external payable {
        require(msg.sender == s_invisibleAddress, "Invalid sender");

        AccumulatedHashesMessage memory message = AccumulatedHashesMessage(
            txBatchId,
            accumulatedDepositHash,
            accumulatedWithdrawalHash
        );

        bytes memory _payload = abi.encode(message);

        MessagingFee memory fee = _quote(_dstEid, _payload, _options, false);

        // TODO: Verify the balance is sufficient to send the transaction. If it isn't, store the message and send it later.

        // MessagingReceipt memory _receipt =
        _lzSend(_dstEid, _payload, _options, fee, payable(msg.sender));

        // TODO: Do we need to store the message?

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

// * DEPOSIT FLOW:
// * 1. User makes a deposit on the L2
// * 2. The L2MessageRelay maps(stores) the depositId to the depositHash
// * 3. After every batch is finalized we receive the accumulated deposit/withdrawal hashes from the L1MessageRelay
// * 4. We store the accumulated deposit/withdrawal hashes in the L2MessageRelay
// * 5. The accDepHash we receive is the hash of hashes of all deposits that were claimed in the batch
// * 6. We can then verify the accDepHash we received from the L1MessageRelay with the accDepHash we have stored in the L2MessageRelay
// * We do this by providing the real deposits and hashing them and verifying the hash against the stored hash for that depositId

// * 7. If the user wants to cancell the deposit he can initiate the cancellation process
// * 8. The cancellation will be valid after a time delay of 3 days (for example)
// * 9. The user can reclaim the funds back to his account after the time delay

// * SEND/RECEIVE FLOW:
// * 1. The L1 sends a message to the L2 after every batch
// * 2. The L2 receives the message and updates the accumulated deposit/withdrawal hashes
// * 3. The L2 checks if the hashes from the previous batch have been verified
// * 4. If the hashes have been verified the L2 send back and acknowledgement to the L1

contract L2MessageRelay is OAppSender, OAppReceiver {
    uint32 txBatchId = 0;
    uint32 public totalDepositCount = 0;

    mapping(uint32 => bytes32) public accumulatedDepositHashes; // txBatchId -> accumulatedHash
    mapping(uint32 => bytes32) public accumulatedWithdrawalHashes; // txBatchId -> accumulatedHash

    mapping(uint32 => bool) public processedDeposits; // txBatchId -> isProcessed
    mapping(uint32 => bool) public processedWithdrawals; // txBatchId -> isProcessed

    uint32 L1DestEid = 123; // TODO

    event UpdateAccumulatedDepositHash(
        uint32 totalDepositCount,
        bytes32 accumulatedDepositHash,
        uint256 timestamp
    );

    address s_invisibleAddress;

    constructor(
        address _endpoint,
        address _owner
    ) OAppCore(_endpoint, _owner) Ownable(_owner) {}

    function setInvisibleAddress(address _invAddress) external onlyOwner {
        s_invisibleAddress = _invAddress;
    }

    /* @dev Receive a message from the L1MessageRelay contract containing the
    accumulated withdrawal hash and txBatchId: The transaction batch ID. It updates the 
    stored accumulated withdrawal hashes for the txBatchId and moves to a new batch.
    */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata payload,
        address,
        bytes calldata
    ) internal override {
        // Extract the sender's EID from the origin
        uint32 senderEid = _origin.srcEid;
        bytes32 sender = _origin.sender;

        require(senderEid == L1DestEid, "Invalid sender");
        // TODO: Do we need to verify the sender is a registered peer?

        AccumulatedHashesMessage memory message = abi.decode(
            payload,
            (AccumulatedHashesMessage)
        );
        accumulatedDepositHashes[message.txBatchId] = message
            .accumulatedDepositHash;
        accumulatedWithdrawalHashes[message.txBatchId] = message
            .accumulatedWithdrawalHash;

        // TODO: Verify that the previous accumulated hashes have been verified
        bool prevDepositsVerified = processedDeposits[message.txBatchId - 1];
        bool prevWithdrawalsVerified = processedWithdrawals[
            message.txBatchId - 1
        ];

        L2AcknowledgmentMessage memory ack = L2AcknowledgmentMessage(
            message.txBatchId - 1,
            prevDepositsVerified,
            prevWithdrawalsVerified
        );

        bytes memory options = "0x123"; // TODO: Add options and msg.value
        _sendAcknowledgment(ack, options);

        txBatchId = message.txBatchId;
    }

    /* @dev Used to send the acknowledgment message manually, if necessary.
     */
    function sendAcknowledgment(uint32 _txBatchId) external {
        bool prevDepositsVerified = processedDeposits[_txBatchId];
        bool prevWithdrawalsVerified = processedWithdrawals[_txBatchId];

        L2AcknowledgmentMessage memory ack = L2AcknowledgmentMessage(
            _txBatchId,
            prevDepositsVerified,
            prevWithdrawalsVerified
        );

        bytes memory options = "0x123"; // TODO: Add options and msg.value
        _sendAcknowledgment(ack, options);
    }

    function _sendAcknowledgment(
        L2AcknowledgmentMessage memory _message,
        bytes memory _options
    ) private {
        bytes memory _payload = abi.encode(_message);

        MessagingFee memory fee = _quote(L1DestEid, _payload, _options, false);

        _lzSend(L1DestEid, _payload, _options, fee, payable(msg.sender));
    }

    // *

    function processAccumulatedDepositHash(
        uint32 processedTxBatchId,
        bytes32 accDepositHash
    ) external {
        require(msg.sender == s_invisibleAddress, "Invalid caller");

        require(
            !processedDeposits[processedTxBatchId],
            "Deposits already processed"
        );
        require(
            accumulatedDepositHashes[processedTxBatchId] == accDepositHash,
            "Invalid accumulated deposit hash"
        );

        processedDeposits[processedTxBatchId] = true;
    }

    function processAccumulatedWithdrawalHash(
        uint32 processedTxBatchId,
        bytes32 accWithdrawalHash
    ) external {
        require(msg.sender == s_invisibleAddress, "Invalid caller");

        require(
            !processedWithdrawals[processedTxBatchId],
            "Withdrawal already processed"
        );
        require(
            accumulatedWithdrawalHashes[processedTxBatchId] ==
                accWithdrawalHash,
            "Invalid accumulated withdrawal hash"
        );

        processedWithdrawals[processedTxBatchId] = true;
    }

    // * View functions --------------------------------
    function latestAccumulatedDepositHash() public view returns (bytes32) {
        return accumulatedDepositHashes[txBatchId];
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
