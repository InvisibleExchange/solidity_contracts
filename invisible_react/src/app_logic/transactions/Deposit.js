const { getKeyPair, sign } = require("starknet/utils/ellipticCurve");
const { pedersen, computeHashOnElements } = require("../helpers/pedersen");



module.exports = class Deposit {
  constructor(
    deposit_id,
    deposit_token,
    deposit_amount,
    stark_key,
    notes,
    signature
  ) {
    this.deposit_id = deposit_id;
    this.deposit_token = deposit_token;
    this.deposit_amount = deposit_amount;
    this.stark_key = stark_key;
    this.notes = notes;
    this.signature = signature;
  }

  toGrpcObject() {
    return {
      deposit_id: this.deposit_id.toString(),
      deposit_token: this.deposit_token.toString(),
      deposit_amount: this.deposit_amount.toString(),
      stark_key: this.stark_key.toString(),
      notes: this.notes.map((n) => n.toGrpcObject()),
      signature: {
        r: this.signature[0].toString(),
        s: this.signature[1].toString(),
      },
    };
  }

  static signDeposit(deposit_id, notes, pk) {
    let hashes = notes.map((n) => n.hashNote());

    hashes.unshift(deposit_id);

    let deposit_hash = computeHashOnElements(hashes);

    let keyPair = getKeyPair(pk);

    let sig = sign(keyPair, deposit_hash.toString(16));

    return sig;
  }
};
