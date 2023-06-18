const ffi = require("ffi-napi");
const ref = require("ref-napi");
const ArrayType = require("ref-array-napi");
const StructType = require("ref-struct-napi");

const FfiNoteType = StructType({
  index: ref.types.uint64,
  address_x: ref.types.CString,
  address_y: ref.types.CString,
  token: ref.types.uint64,
  amount: ref.types.uint64,
  blinding: ref.types.CString,
});

const SignatureType = StructType({
  sig_r: ref.types.CString,
  sig_s: ref.types.CString,
});

const NoteArray = ArrayType(FfiNoteType);
const StringArray = ArrayType(ref.types.CString);

const FfiOrderType = StructType({
  order_id: ref.types.uint64,
  expiration_timestamp: ref.types.uint64,
  token_spent: ref.types.uint64,
  token_received: ref.types.uint64,
  amount_spent: ref.types.uint64,
  amount_received: ref.types.uint64,
  fee_limit: ref.types.uint64,
  // addresses
  dest_spent_address_x: ref.types.CString,
  dest_spent_address_y: ref.types.CString,
  dest_received_address_x: ref.types.CString,
  dest_received_address_y: ref.types.CString,
  // blindings
  dest_spent_blinding: ref.types.CString,
  dest_received_blinding: ref.types.CString,
  // notes
  notes_in: NoteArray,
  notes_in_len: ref.types.size_t,
  refund_note: FfiNoteType,
});

const path = "../../invisible_backend/target/debug/libinvisible_backend.so";
let lib = ffi.Library(path, {
  test_func: ["void", ["string"]],
  new_note: [
    "pointer",
    ["uint64", "string", "string", "uint64", "uint64", "string"],
  ],
  new_limit_order: [
    "pointer",
    [
      ref.types.uint64,
      ref.types.uint64,
      ref.types.uint64,
      ref.types.uint64,
      ref.types.uint64,
      ref.types.uint64,
      ref.types.uint64,
      ref.types.CString,
      ref.types.CString,
      ref.types.CString,
      ref.types.CString,
      ref.types.CString,
      ref.types.CString,
      NoteArray,
      ref.types.size_t,
      FfiNoteType,
    ],
  ],
  sign_limit_order: [SignatureType, ["pointer", StringArray, ref.types.size_t]],
  verify_limit_order_sig: ["void", ["pointer", "string", "string"]],
  convert_limit_order: [FfiOrderType, ["pointer"]],
});

function LimitOrderToFfiPointer(limitOrderObject) {
  // limitOrderObject is already a json/grpc object not LimitOrder type
  let dest_spent_address_x = limitOrderObject.dest_spent_address.x;
  let dest_spent_address_y = limitOrderObject.dest_spent_address.y;
  let dest_received_address_x = limitOrderObject.dest_received_address.x;
  let dest_received_address_y = limitOrderObject.dest_received_address.y;

  let dest_spent_blinding = limitOrderObject.dest_spent_blinding;
  let dest_received_blinding = limitOrderObject.dest_received_blinding;

  let notes_in = limitOrderObject.notes_in.map((note) => noteToFfi(note));

  let order_ptr = lib.new_limit_order(
    limitOrderObject.order_id,
    limitOrderObject.expiration_timestamp,
    limitOrderObject.token_spent,
    limitOrderObject.token_received,
    limitOrderObject.amount_spent,
    limitOrderObject.amount_received,
    limitOrderObject.fee_limit,
    dest_spent_address_x,
    dest_spent_address_y,
    dest_received_address_x,
    dest_received_address_y,
    dest_spent_blinding,
    dest_received_blinding,
    notes_in,
    notes_in.length,
    noteToFfi(limitOrderObject.refund_note)
  );

  return order_ptr;
}

function signLimitOrderFfi(order_ptr, priv_keys) {
  let signature = lib.sign_limit_order(
    order_ptr,
    priv_keys.map((key) => key.toString()),
    priv_keys.length
  );
  return { sig_r: signature.sig_r, sig_s: signature.sig_s };
}

function verifyLimitOrderSigFfi(order_ptr, sig_r, sig_s) {
  lib.verify_limit_order_sig(order_ptr, sig_r, sig_s);
}

function pointerToLimitOrderObject(order_ptr) {
  let limitOrder = lib.convert_limit_order(order_ptr);

  return limitOrder;
}

module.exports = {
  LimitOrderToFfiPointer,
  verifyLimitOrderSigFfi,
  signLimitOrderFfi,
  //   pointerToLimitOrderObject,
};

function noteToFfi(noteObject) {
  return new FfiNoteType({
    index: noteObject.index,
    address_x: noteObject.address.x,
    address_y: noteObject.address.y,
    token: noteObject.token,
    amount: noteObject.amount,
    blinding: noteObject.blinding,
  });
}
