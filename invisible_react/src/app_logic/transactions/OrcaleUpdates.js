const { getKeyPair, sign } = require("starknet/utils/ellipticCurve");
const { pedersen, computeHashOnElements } = require("../helpers/pedersen");

module.exports = class OracleUpdate {
  constructor(token, price, timestamp) {
    this.token = token;
    this.price = price;
    this.timestamp = timestamp;
  }

  signOracleUpdate(privKey) {
    let msg =
      (BigInt(this.price) * 2n ** 64n + BigInt(this.token)) * 2n ** 64n +
      BigInt(this.timestamp);

    let keyPair = getKeyPair(privKey);

    let sig = sign(keyPair, msg.toString(16));

    return { r: sig[0], s: sig[1] };
  }
};
