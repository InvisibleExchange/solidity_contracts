module.exports = class PerpSwap {
  constructor(
    order_a,
    order_b,
    signature_a,
    signature_b,
    spent_collateral,
    spent_synthetic,
    fee_taken_a,
    fee_taken_b
  ) {
    this.order_a = order_a;
    this.order_b = order_b;
    this.signature_a = signature_a;
    this.signature_b = signature_b;
    this.spent_collateral = spent_collateral;
    this.spent_synthetic = spent_synthetic;
    this.fee_taken_a = fee_taken_a;
    this.fee_taken_b = fee_taken_b;
  }

  toGrpcObject() {
    return {
      order_a: this.order_a.toGrpcObject(),
      order_b: this.order_b.toGrpcObject(),
      signature_a: {
        r: this.signature_a[0].toString(),
        s: this.signature_a[1].toString(),
      },
      signature_b: {
        r: this.signature_b[0].toString(),
        s: this.signature_b[1].toString(),
      },
      spent_collateral: this.spent_collateral.toString(),
      spent_synthetic: this.spent_synthetic.toString(),
      fee_taken_a: this.fee_taken_a.toString(),
      fee_taken_b: this.fee_taken_b.toString(),
    };
  }
};
