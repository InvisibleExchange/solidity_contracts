const grpc = require("@grpc/grpc-js");
const protoLoader = require("@grpc/proto-loader");

const path = require("path");
const packageDefinition = protoLoader.loadSync(
  path.join(__dirname, "../../../invisible_backend/proto/engine.proto"),
  { keepCase: true, longs: String, enums: String, defaults: true, oneofs: true }
);
const engine = grpc.loadPackageDefinition(packageDefinition).engine;

const SERVER_URL = "localhost:50052";

const client = new engine.Engine(SERVER_URL, grpc.credentials.createInsecure());

// const path = require("path");
// let db = new sqlite3.Database(
//   path.join(__dirname, "../orderBooks.db"),
//   (err) => {
//     if (err) {
//       console.error(err.message);
//     }
//   }
// );

// TODO: ONLY RESTORE THE ORDERS THAT HAVE NOT EXPIRED YET

async function restoreOrderbooks(db) {
  let completedCount = 0;

  let spotOrders = {}; // {orderId: orderObject}
  let perpOrders = {}; // {orderId: orderObject}
  let spotLiquidity = {}; // {marketId: {bidQueue, askQueue}}
  let perpLiquidity = {}; // {marketId: {bidQueue, askQueue}}

  db.all("SELECT * FROM spotOrders", [], (err, rows) => {
    if (err) {
      console.error(err.message);
    }
    rows.forEach((row) => {
      let orderObject = {
        expiration_timestamp: row.expiration_timestamp,
        token_spent: row.token_spent,
        token_received: row.token_received,
        amount_spent: row.amount_spent,
        amount_received: row.amount_received,
        fee_limit: row.fee_limit,
        dest_received_address: JSON.parse(row.dest_received_address),
        dest_received_blinding: row.dest_received_blinding,
        dest_spent_blinding: row.dest_spent_blinding,
        notes_in: JSON.parse(row.notes_in),
        refund_note: JSON.parse(row.refund_note),
        signature: JSON.parse(row.signature),
        user_id: row.user_id,
      };

      spotOrders[row.order_id] = orderObject;
    });

    completedCount += 1;
    if (completedCount == 4) {
      sendOrder(spotOrders, perpOrders, spotLiquidity, perpLiquidity);
    }
  });

  db.all("SELECT * FROM perpOrders", [], (err, rows) => {
    if (err) {
      console.error(err.message);
    }

    rows.forEach((row) => {
      let orderObject = {
        expiration_timestamp: row.expiration_timestamp,
        position: row.position ? JSON.parse(row.position) : null,
        position_effect_type: row.position_effect_type,
        order_side: row.order_side,
        synthetic_token: row.synthetic_token,
        collateral_token: row.collateral_token,
        synthetic_amount: row.synthetic_amount,
        collateral_amount: row.collateral_amount,
        fee_limit: row.fee_limit,
        open_order_fields: row.open_order_fields
          ? JSON.parse(row.open_order_fields)
          : null,
        close_order_fields: row.close_order_fields
          ? JSON.parse(row.close_order_fields)
          : null,
        signature: JSON.parse(row.signature),
        is_market: row.is_market,
        user_id: row.user_id,
      };

      perpOrders[row.order_id] = orderObject;
    });

    completedCount += 1;
    if (completedCount == 4) {
      sendOrder(spotOrders, perpOrders, spotLiquidity, perpLiquidity);
    }
  });

  db.all("SELECT * FROM spotLiquidity", [], (err, rows) => {
    if (err) {
      console.error(err.message);
    }

    if (rows && rows.length > 0) {
      rows.forEach((row) => {
        let market_id = row.market_id;
        let bidQueue = JSON.parse(row.bidQueue);
        let askQueue = JSON.parse(row.askQueue);

        spotLiquidity[market_id] = { bidQueue, askQueue };
      });
    }

    completedCount += 1;
    if (completedCount == 4) {
      sendOrder(spotOrders, perpOrders, spotLiquidity, perpLiquidity);
    }
  });

  db.all("SELECT * FROM perpLiquidity", [], (err, rows) => {
    if (err) {
      console.error(err.message);
    }

    if (rows && rows.length > 0) {
      rows.forEach((row) => {
        let market_id = row.market_id;
        let bidQueue = JSON.parse(row.bidQueue);
        let askQueue = JSON.parse(row.askQueue);

        perpLiquidity[market_id] = { bidQueue, askQueue };
      });
    }

    completedCount += 1;
    if (completedCount == 4) {
      sendOrder(spotOrders, perpOrders, spotLiquidity, perpLiquidity);
    }
  });
}

async function sendOrder(spotOrders, perpOrders, spotLiquidity, perpLiquidity) {
  let spot_order_restore_messages = [];
  for (let [market_id, { bidQueue, askQueue }] of Object.entries(
    spotLiquidity
  )) {
    let bid_order_restore_messages = [];
    let ask_order_restore_messages = [];
    for (let val of bidQueue) {
      let price = val[0];
      let amount = val[1];
      let timestamp = val[2];
      let order_id = val[3];

      let order = spotOrders[order_id];

      let message = {
        order_id,
        price,
        amount,
        timestamp,
        order,
      };

      bid_order_restore_messages.push(message);
    }
    for (let val of askQueue) {
      let price = val[0];
      let amount = val[1];
      let timestamp = val[2];
      let order_id = val[3];

      let order = spotOrders[order_id];

      let message = {
        order_id,
        price,
        amount,
        timestamp,
        order,
      };

      ask_order_restore_messages.push(message);
    }

    let message = {
      market_id,
      bid_order_restore_messages,
      ask_order_restore_messages,
    };

    spot_order_restore_messages.push(message);
  }

  let perp_order_restore_messages = [];
  for (let [market_id, { bidQueue, askQueue }] of Object.entries(
    perpLiquidity
  )) {
    let bid_order_restore_messages = [];
    let ask_order_restore_messages = [];
    for (let val of bidQueue) {
      let price = val[0];
      let amount = val[1];
      let timestamp = val[2];
      let order_id = val[3];

      let order = perpOrders[order_id];

      let message = {
        order_id,
        price,
        amount,
        timestamp,
        order,
      };

      bid_order_restore_messages.push(message);
    }
    for (let val of askQueue) {
      let price = val[0];
      let amount = val[1];
      let timestamp = val[2];
      let order_id = val[3];

      let order = perpOrders[order_id];

      let message = {
        order_id,
        price,
        amount,
        timestamp,
        order,
      };

      ask_order_restore_messages.push(message);
    }

    let message = {
      market_id,
      bid_order_restore_messages,
      ask_order_restore_messages,
    };

    perp_order_restore_messages.push(message);
  }

  let restoreOrderBookMessage = {
    spot_order_restore_messages,
    perp_order_restore_messages,
  };

  console.log(restoreOrderBookMessage);

  client.restore_orderbook(restoreOrderBookMessage, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      console.log(response);
    }
  });
}

module.exports = {
  restoreOrderbooks,
};
