const { storeOrderId } = require("../helpers/firebase/firebaseConnection");
const { handlePerpSwapResult, handleSwapResult } = require("../helpers/utils");
const LimitOrder = require("../transactions/LimitOrder");
const { PerpOrder } = require("../transactions/PerpOrder");
const User = require("./Invisibl3User");
const { Note, trimHash } = require("./Notes");

class MarketMaker extends User {
  constructor(_privViewKey, _privSpendKey) {
    super(_privViewKey, _privSpendKey);
  }
}

const grpc = require("@grpc/grpc-js");
const protoLoader = require("@grpc/proto-loader");

const packageDefinition = protoLoader.loadSync(
  "../../invisible_backend/proto/engine.proto",
  { keepCase: true, longs: String, enums: String, defaults: true, oneofs: true }
);
const engine = grpc.loadPackageDefinition(packageDefinition).engine;

const grpcClient = new engine.Engine(
  "localhost:50052",
  grpc.credentials.createInsecure()
);

let marketMaker = new MarketMaker(12345, 54321);

let W3CWebSocket = require("websocket").w3cwebsocket;
let wsClient = new W3CWebSocket("ws://localhost:50053/");

const SPOT_MARKETS = { 11: "BTC-USDC", 12: "ETH-USDC" }; // maps market_id to market name
const PERP_MARKETS = { 21: "BTC-USDC", 22: "ETH-USDC" }; // maps market_id to market name

const tokenIds = { BTC: 12345, ETH: 54321, USDC: 55555 }; // maps token name to token id
const tokenDecimals = { BTC: 6, ETH: 6, USDC: 6 }; // maps token name to token decimals
const priceDecimals = { BTC: 6, ETH: 6, USDC: 6 }; // maps token name to price decimals

const spotMarketIds = { 12345: 11, 54321: 12 }; // maps market name to market id
const perpMarketIds = { 12345: 21, 54321: 22 }; // maps market name to market id

wsClient.onopen = function () {
  wsClient.send(trimHash(marketMaker.userId, 64));
};

wsClient.onmessage = function (e) {
  let msg = JSON.parse(e.data);

  console.log("meassage received: ", msg);

  switch (msg.message_id) {
    case "LIQUIDITY_UPDATE":
      // & msg format:
      // {
      //     "message_id": u64,
      //     "type": "spot/perpetual",
      //     "market": u16,
      //     "ask_liquidity": [[f64, u64, u64], ..., [f64, u64, u64]],  // [[price, amount, timestamp], ...]
      //     "bid_liquidity": [[f64, u64, u64], ..., [f64, u64, u64]],  // [[price, amount, timestamp], ...]
      // }

      let isPerp = msg.type == "perpetual";
      let market = isPerp ? PERP_MARKETS[msg.market] : SPOT_MARKETS[msg.market];

      // Amount is multiplied by 10^token_decimals, price is not
      let ask_queue = msg.ask_liquidity.map((x) => {
        return { price: x[0], amount: x[1], timestamp: x[2] };
      });
      let bid_queue = msg.bid_liquidity.map((x) => {
        return { price: x[0], amount: x[1], timestamp: x[2] };
      });

      // Todo: =========> Market maker logic here <==========

      // Todo: =========> Market maker logic here <==========

      break;

    // TODO: When receiving a swap result, if partially filled update the users order data and reduce the qty_left !!!!!!!!!!!!!!!!!!
    case "SWAP_RESULT":
      // & msg format:
      // {
      //     "message_id": u64,
      //     "order_id": u64,
      //     "swap_response":  {
      //          swap_note: Note
      //          new_pfr_note: Note or null,
      //          new_amount_filled: u64,
      //      }
      // }

      handleSwapResult(marketMaker, msg.swap_response);
      break;

    case "PERPETUAL_SWAP":
      // & msg format:
      // {
      //   "message_id": "PERPETUAL_SWAP",
      //   "order_id": u64,
      //   "swap_response": {
      //       position: PerpPosition/null,
      //       new_pfr_info: [Note, u64,u64]>/null,
      //       return_collateral_note: Note/null,
      // }

      handlePerpSwapResult(marketMaker, msg.swap_response);
      break;

    default:
      break;
  }
};

/**
 * Constructs a Spot limit order (generates all the notes/addresses/blindings) and returns the new Order along with the signature
 * @param  {string} market  "BTC-USDC" or "ETH-USDC" (base-quote)
 * @param  {string} side  "buy" or "sell"
 * @param  {bigInt} price  Price of base token in quote token
 * @param  {bigInt} baseAmount  amount of base token to buy/sell
 * @param  {bigInt} expirationTimestamp  timestamp of order expiration
 * @param  {bigInt} feeLimit  fee limit for order
 * @return {LimitOrder} order    Newly generated and signed order.
 */
function constructSpotOrder(
  market,
  side,
  price,
  baseAmount,
  expirationTimestamp,
  feeLimit
) {
  let [baseToken, quoteToken] = market.split("-");

  let baseTokenId = tokenIds[baseToken];
  let quoteTokenId = tokenIds[quoteToken];

  let tokenSpent;
  let amountSpent;
  let tokenReceived;
  let amountReceived;
  if (side == "buy") {
    tokenSpent = quoteTokenId;
    amountSpent = baseAmount * price;
    tokenReceived = baseTokenId;
    amountReceived = baseAmount;
  } else {
    tokenSpent = baseTokenId;
    amountSpent = baseAmount;
    tokenReceived = quoteTokenId;
    amountReceived = baseAmount * price;
  }

  let order = marketMaker.makeLimitOrder(
    expirationTimestamp,
    tokenSpent,
    tokenReceived,
    amountSpent,
    amountReceived,
    price,
    feeLimit
  );

  return order;
}

/**
 * Constructs a Perpetual limit order (generates all the notes/addresses/blindings) and returns the new Order along with the signature
 * @param  {string} market  "BTC-USDC" or "ETH-USDC" (base-quote)
 * @param  {string} side  "buy" or "sell"
 * @param  {bigInt} price  Price of base token in quote token
 * @param  {bigInt} syntheticAmount  amount of synthetic token to buy/sell
 * @param  {string} positionAddress  address of position to modify/close
 * @param  {string} positionEffectType   "Open/Modify/Close/Liquidate"
 * @param  {bigInt} initialMargin  initial margin for position (or none if modifying)
 * @param  {bigInt} expirationTimestamp  timestamp of order expiration
 * @param  {bigInt} feeLimit  fee limit for order
 * @return {LimitOrder} order    Newly generated and signed order.
 */
function constructPerpOrder(
  market,
  side,
  price,
  syntheticAmount,
  positionAddress,
  positionEffectType,
  initialMargin,
  expirationTimestamp,
  feeLimit
) {
  let [syntheticToken, collateralToken] = market.split("-");

  syntheticToken = tokenIds[syntheticToken];
  collateralToken = tokenIds[collateralToken];

  let collateralAmount = syntheticAmount * price;

  let order = marketMaker.makePerpetualOrder(
    expirationTimestamp,
    positionAddress,
    positionEffectType,
    side == "buy" ? 0 : 1,
    syntheticToken,
    collateralToken,
    syntheticAmount,
    collateralAmount,
    price,
    feeLimit,
    initialMargin
  );

  return order;
}

/**
 * Sends a spot limit order to the backend to get executed. If the order is placed successfully, the order with the new order id is saved.
 * @param  {LimitOrder} order  The limit order to submit to the backend.
 * @return {BigInt} orderId    Newly generated 64bit order id.
 */
function submitSpotOrder(order) {
  // Todo: Maybe verify some consistencies

  grpcClient.submit_limit_order(req.body, function (err, order_response) {
    if (err) {
      console.log(err);
    } else {
      if (order_response.successful) {
        storeOrderId(marketMaker.userId, order_response.order_id, false);

        // {base_asset,expiration_timestamp,fee_limit,notes_in,order_id,order_side,price,qty_left,quote_asset,refund_note}

        let order_side = order.order_side == "Bid" ? 0 : 1;
        let orderData = {
          base_asset: order_side ? order.token_received : order.token_spent,
          quote_asset: order_side ? order.token_spent : order.token_received,
          expiration_timestamp: order.expiration_timestamp,
          fee_limit: order.fee_limit,
          notes_in: order.notesIn,
          order_id: order_response.order_id,
          order_side,
          price: order.price,
          qty_left: order_side ? order.amount_received : order.amount_spent,
          refund_note: order.refund_note,
        };

        marketMaker.orders.push(orderData);

        return order_response.order_id;
      } else {
        let msg =
          "Failed to submit order with error: \n" +
          order_response.error_message;
        console.log(msg);
      }
    }
  });
}

/**
 * Sends a perpetual limit order to the backend to get executed. If the order is placed successfully, the order with the new order id is saved.
 * @param  {PerpOrder} perpOrder  The perpetual order to submit to the backend.
 * @return {BigInt}   orderId    Newly generated 64bit order id.
 */
function submitPerpOrder(perpOrder) {
  // Todo: Maybe verify some consistencies

  grpcClient.submit_perpetual_order(order, function (err, order_response) {
    if (err) {
      console.log(err);
    } else {
      if (order_response.successful) {
        alert("Order submitted successful!");

        storeOrderId(marketMaker.userId, order_response.order_id, true);

        // {order_id,expiration_timestamp,qty_left,price,synthetic_token,order_side,position_effect_type,fee_limit,position_address,notes_in,refund_note,initial_margin}

        let pos_effect_type_int;
        switch (perpOrder.position_effect_type) {
          case "Open":
            pos_effect_type_int = 0;
            break;
          case "Modify":
            pos_effect_type_int = 1;
            break;
          case "Close":
            pos_effect_type_int = 2;
            break;
          case "Liquidate":
            pos_effect_type_int = 3;
            break;
          default:
            throw "invalid position effect type (should be 0-3)";
        }

        let orderData = {
          synthetic_token: perpOrder.synthetic_token,
          expiration_timestamp: perpOrder.expiration_timestamp,
          fee_limit: perpOrder.fee_limit,
          order_id: order_response.order_id,
          position_effect_type: pos_effect_type_int,
          order_side: perpOrder.order_side == "Long",
          price: perpOrder.price,
          position_address: perpOrder.position
            ? perpOrder.position.position_address
            : null,
          qty_left: perpOrder.synthetic_amount,
          notes_in:
            pos_effect_type_int == 0
              ? perpOrder.open_order_fields.notes_in
              : [],
          refund_note:
            pos_effect_type_int == 0 && perpOrder.open_order_fields.refund_note
              ? perpOrder.open_order_fields.refund_note
              : null,
          initial_margin:
            pos_effect_type_int == 0
              ? perpOrder.open_order_fields.initial_margin
              : 0,
        };

        marketMaker.perpetualOrders.push(orderData);

        return order_response.order_id;
      } else {
        let msg =
          "Failed to submit order with error: \n" +
          order_response.error_message;
        console.log(msg);
      }
    }
  });
}

/**
 * Cancel an order with the given order id.
 * @param  order  The order to cancel to the backend.
 * - Order structure: {base_asset, expiration_timestamp, fee_limit, notes_in, order_id, order_side, price, qty_left, quote_asset, refund_note}
 * - Perp order structure: {order_id, expiration_timestamp, qty_left, price, synthetic_token, order_side, position_effect_type, fee_limit, position_address, notes_in, refund_note, initial_margin}
 * @param  {bool} isPerp  If the order is a parpetual.
 */
function cancelOrder(order, isPerp) {
  let marketId;
  if (isPerp) {
    marketId = perpMarketIds[order.synthetic_token];
  } else {
    marketId =
      order.order_side == "Bid"
        ? spotMarketIds[order.quote_asset]
        : spotMarketIds[order.base_asset];
  }

  let cancelationRequest = {
    marketId: marketId,
    order_id: order.order_id,
    order_side: order.order_side == "Bid" ? true : false,
    user_id: trimHash(marketMaker.userId, 64),
    is_perp: isPerp,
  };

  // Send cancelation request to server
  grpcClient.cancel_order(cancelationRequest, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      if (response.successful) {
        console.log("order cancelled successfully");

        if (isPerp) {
          marketMaker.perpetualOrders = marketMaker.perpetualOrders.filter(
            (o) => o.order_id != order.order_id
          );
        } else {
          marketMaker.orders = marketMaker.orders.filter(
            (o) => o.order_id != order.order_id
          );
        }

        if (response.pfr_note) {
          marketMaker.pfrNotes.filter(
            (n) => n.index != response.pfr_note.index
          );
        }
      } else {
        console.log("error: ", response.error_message);
      }
    }
  });
}

/// =============================================================================
