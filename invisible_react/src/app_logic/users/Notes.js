const { pedersen, computeHashOnElements } = require("../helpers/pedersen");
const bigInt = require("big-integer");
const { ec, getKeyPair } = require("starknet/utils/ellipticCurve.js");
const BN = require("bn.js");

//* =============================================================================
//* CLASSES

/* global BigInt */

class Note {
  constructor(K, T, amount, blinding_factor, idx = 0) {
    this.index = idx;
    this.address = K;
    this.token = T;
    this.amount = amount;
    this.blinding = blinding_factor;
    this.commitment = this.getCommitment();
    this.hash = this.hashNote();
  }

  hashNote() {
    if (this.amount == 0) {
      return 0;
    }

    return BigInt(
      computeHashOnElements([
        BigInt(this.address.getX()),
        this.token,
        this.commitment,
      ]),
      16
    );
  }

  toGrpcObject() {
    return {
      address: {
        x: this.address.getX().toString(),
        y: this.address.getY().toString(),
      },
      token: this.token.toString(),
      amount: this.amount.toString(),
      blinding: this.blinding.toString(),
      index: this.index.toString(),
    };
  }

  getCommitment() {
    return pedersen([BigInt(this.amount), this.blinding]);
  }

  static fromGrpcObject(noteObject) {
    let address = ec
      .keyFromPublic({
        x: new BN(noteObject.address.x),
        y: new BN(noteObject.address.y),
      })
      .getPublic();

    return new Note(
      address,
      BigInt(noteObject.token),
      BigInt(noteObject.amount),
      BigInt(noteObject.blinding),
      BigInt(noteObject.index)
    );
  }
}

//* =============================================================================
//* HELPER FUNCTIONS

function split(num) {
  const BASE = bigInt(2).pow(86).value;

  num = BigInt(num);
  let a = [];
  for (let i = 0; i < 3; i++) {
    let res = bigInt(num).divmod(BASE);
    num = res.quotient;
    a.push(res.remainder.value);
  }
  if (num != 0) {
    throw new Error("num is not 0");
  }

  return a;
}

function splitUint256(num) {
  let divRem = bigInt(num).divmod(bigInt(2).pow(128));

  return { high: divRem.quotient.value, low: divRem.remainder.value };
}

function trimHash(hash, n_bits = 128) {
  // returns the last n_bits number of the number as bigInt
  return bigInt(hash).and(bigInt(1).shiftLeft(n_bits).prev()).value;
}

module.exports = {
  trimHash,
  Note,
  split,
  splitUint256,
};
