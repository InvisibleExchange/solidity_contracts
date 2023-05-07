const { getKeyPair, sign } = require("starknet/utils/ellipticCurve");
const { pedersen, computeHashOnElements } = require("../helpers/pedersen");

/* global BigInt */

module.exports = class Withdrawal {
  constructor(
    withdrawal_token,
    withdrawal_amount,
    stark_key,
    notes_in,
    refund_note,
    signature
  ) {
    this.withdrawal_token = withdrawal_token;
    this.withdrawal_amount = withdrawal_amount;
    this.stark_key = stark_key;
    this.notes_in = notes_in;
    this.refund_note = refund_note;
    this.signature = signature;
  }

  toGrpcObject() {
    return {
      withdrawal_token: this.withdrawal_token.toString(),
      withdrawal_amount: this.withdrawal_amount.toString(),
      stark_key: this.stark_key.toString(),
      notes_in: this.notes_in.map((n) => n.toGrpcObject()),
      refund_note: this.refund_note.toGrpcObject(),
      signature: {
        r: this.signature[0].toString(),
        s: this.signature[1].toString(),
      },
    };
  }

  static signWithdrawal(notes, pks, refund_note, starkKey) {
    let hashes = notes.map((n) => n.hashNote());
    let refundNoteHash = refund_note.hashNote();

    hashes.unshift(refundNoteHash);
    hashes.unshift(starkKey);

    let withdrawal_hash = computeHashOnElements(hashes);

    let pkSum = 0n;
    for (let i = 0; i < pks.length; i++) {
      pkSum += BigInt(pks[i]);
    }

    let keyPair = getKeyPair(pkSum);

    let sig = sign(keyPair, withdrawal_hash.toString(16));

    return sig;
  }
};
