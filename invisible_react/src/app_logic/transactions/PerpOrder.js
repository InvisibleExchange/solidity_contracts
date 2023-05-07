const { getKeyPair, sign } = require("starknet/utils/ellipticCurve");
const { computeHashOnElements, pedersen } = require("../helpers/pedersen");

/* global BigInt */
class PerpOrder {
  constructor(
    expiration_timestamp,
    position,
    position_effect_type,
    order_side,
    synthetic_token,
    synthetic_amount,
    collateral_amount,
    price,
    fee_limit,
    open_order_fields,
    close_order_fields
  ) {
    this.expiration_timestamp = expiration_timestamp;
    this.position = position;
    this.position_effect_type = position_effect_type;
    this.order_side = order_side;
    this.synthetic_token = synthetic_token;
    this.synthetic_amount = synthetic_amount;
    this.collateral_amount = collateral_amount;
    this.price = price;
    this.fee_limit = fee_limit;
    // -------------------
    this.open_order_fields = open_order_fields;
    // -------------------
    this.close_order_fields = close_order_fields;
    // -------------------
    this.signature = null;
  }

  hashOrder() {
    let order_side;
    switch (this.order_side) {
      case "Long":
        order_side = 0n;
        break;
      case "Short":
        order_side = 1n;
        break;
      default:
        throw "invalid order side (should be binary)";
    }

    let pos_effect_type_int;
    switch (this.position_effect_type) {
      case "Open":
        pos_effect_type_int = 0n;
        break;
      case "Modify":
        pos_effect_type_int = 1n;
        break;
      case "Close":
        pos_effect_type_int = 2n;
        break;
      case "Liquidate":
        pos_effect_type_int = 3n;
        break;
      default:
        throw "invalid position effect type (should be 0-3)";
    }

    let position_address;
    switch (this.position_effect_type) {
      case "Open":
        position_address = this.open_order_fields.position_address;
        break;
      case "Modify":
        position_address = this.position.position_address;
        break;
      case "Close":
        position_address = this.position.position_address;
        break;
      case "Liquidate":
        position_address = this.position.position_address;
        break;
      default:
        throw "invalid position effect type (should be 0-3)";
    }

    let hash_inputs = [
      this.expiration_timestamp,
      position_address,
      pos_effect_type_int,
      order_side,
      this.synthetic_token,
      this.synthetic_amount,
      this.collateral_amount,
      this.fee_limit,
    ];

    let order_hash = computeHashOnElements(hash_inputs);

    if (pos_effect_type_int == 0) {
      if (!this.open_order_fields) {
        throw "Open order fields is not defined for open order";
      }
      let fields_hash = this.open_order_fields.hash();

      return pedersen([order_hash, fields_hash]);
    } else if (pos_effect_type_int == 2) {
      if (!this.close_order_fields) {
        throw "close_order_fields not defined in close order";
      }

      let fields_hash = this.close_order_fields.hash();

      return pedersen([order_hash, fields_hash]);
    } else {
      return order_hash;
    }
  }

  signOrder(privKeys, positionPrivKey) {
    let orderHash = this.hashOrder();

    if (this.position_effect_type == "Open") {
      let pkSum = 0n;
      for (const pk of privKeys) {
        pkSum += pk;
      }

      let keyPair = getKeyPair(pkSum);

      let sig = sign(keyPair, "0x" + orderHash.toString(16));

      this.signature = sig;
      return sig;
    }

    let keyPair = getKeyPair(positionPrivKey);
    let sig = sign(keyPair, "0x" + orderHash.toString(16));

    this.signature = sig;

    return sig;
  }

  toGrpcObject() {
    let position_effect_type;
    switch (this.position_effect_type) {
      case "Open":
        position_effect_type = 0;
        break;
      case "Modify":
        position_effect_type = 1;
        break;
      case "Close":
        position_effect_type = 2;
        break;
      case "Liquidate":
        position_effect_type = 3;
        break;

      default:
        throw "invalid position effect type";
    }

    let order_side;
    switch (this.order_side) {
      case "Long":
        order_side = 0;
        break;
      case "Short":
        order_side = 1;
        break;

      default:
        throw "invalid position effect type";
    }

    let open_order_fields = this.open_order_fields
      ? this.open_order_fields.toGrpcObject()
      : null;
    let close_order_fields = this.close_order_fields
      ? this.close_order_fields.toGrpcObject()
      : null;

    if (this.position) {
      this.position.order_side = this.position.order_side == "Long" ? 0 : 1;
    }

    return {
      expiration_timestamp: this.expiration_timestamp.toString(),
      position: this.position,
      position_effect_type,
      order_side,
      synthetic_token: this.synthetic_token.toString(),
      synthetic_amount: this.synthetic_amount.toString(),
      collateral_amount: this.collateral_amount.toString(),
      fee_limit: this.fee_limit.toString(),
      open_order_fields,
      close_order_fields,
      signature: this.signature
        ? {
            r: this.signature[0].toString(),
            s: this.signature[1].toString(),
          }
        : null,
    };
  }
}

class OpenOrderFields {
  constructor(
    initial_margin,
    collateral_token,
    notes_in,
    refund_note,
    position_address,
    blinding
  ) {
    this.initial_margin = initial_margin;
    this.collateral_token = collateral_token;
    this.notes_in = notes_in;
    this.refund_note = refund_note;
    this.position_address = position_address;
    this.blinding = blinding;
  }

  hash() {
    let hash_inputs = [];
    for (const note of this.notes_in) {
      hash_inputs.push(note.hash);
    }
    let refund_hash = this.refund_note ? this.refund_note.hash : 0n;
    hash_inputs.push(refund_hash);
    hash_inputs.push(this.initial_margin);
    hash_inputs.push(this.collateral_token);
    hash_inputs.push(BigInt(this.position_address));
    hash_inputs.push(this.blinding);

    return computeHashOnElements(hash_inputs);
  }

  toGrpcObject() {
    let grpcObject = {
      initial_margin: this.initial_margin.toString(),
      collateral_token: this.collateral_token.toString(),
      notes_in: this.notes_in.map((note) => note.toGrpcObject()),
      refund_note: this.refund_note ? this.refund_note.toGrpcObject() : null,
      position_address: this.position_address,
      blinding: this.blinding.toString(),
    };

    return grpcObject;
  }
}

class CloseOrderFields {
  constructor(dest_received_address, dest_received_blinding) {
    this.dest_received_address = dest_received_address;
    this.dest_received_blinding = dest_received_blinding;
  }

  hash() {
    return pedersen([
      BigInt(this.dest_received_address.getX()),
      this.dest_received_blinding,
    ]);
  }

  toGrpcObject() {
    return {
      dest_received_address: {
        x: this.dest_received_address.getX().toString(),
        y: this.dest_received_address.getY().toString(),
      },
      dest_received_blinding: this.dest_received_blinding.toString(),
    };
  }
}

module.exports = {
  PerpOrder,
  OpenOrderFields,
  CloseOrderFields,
};
