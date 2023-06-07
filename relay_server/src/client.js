const express = require("express");
const app = express();
const port = 4000;

const cors = require("cors");
const {
  initDb,
  storeSpotOrder,
  storePerpOrder,
  initOrderBooks,
  compileLiqUpdateMessage,
  listenToLiquidityUpdates,
  getLiquidatablePositions,
} = require("./helpers");

const grpc = require("@grpc/grpc-js");
const protoLoader = require("@grpc/proto-loader");

const corsOptions = {
  origin: "*",
  credentials: true, //access-control-allow-credentials:true
  optionSuccessStatus: 200,
};

app.use(cors(corsOptions));
app.use(express.json());

const packageDefinition = protoLoader.loadSync(
  "../../invisible_backend/proto/engine.proto",
  { keepCase: true, longs: String, enums: String, defaults: true, oneofs: true }
);
const engine = grpc.loadPackageDefinition(packageDefinition).engine;

const CONFIG_CODE = "1234567890";
const RELAY_SERVER_ID = "43147634234";
const SERVER_URL = "localhost:50052";

let client = new engine.Engine(SERVER_URL, grpc.credentials.createInsecure());

const db = initDb();

// * ORDER BOOKS AND LIQUIDITY ====================================================================================

const orderBooks = initOrderBooks();
let fillUpdates = [];
let wsConnections = [];

// & WEBSOCKET CLIENT
let W3CWebSocket = require("websocket").w3cwebsocket;
let wsClient = new W3CWebSocket(`ws://localhost:50053/`);

wsClient.onopen = function () {
  console.log("WebSocket Client Connected");
  wsClient.send(
    JSON.stringify({ user_id: RELAY_SERVER_ID, config_code: CONFIG_CODE })
  );
};

wsClient.onmessage = function (e) {
  listenToLiquidityUpdates(e, db, orderBooks, fillUpdates);
};

// & WEBSOCKET SERVER
const WebSocket = require("ws");
const wss = new WebSocket.Server({ port: 4040 });
const SEND_LIQUIDITY_PERIOD = 1000;

wss.on("connection", (ws) => {
  ws.on("message", (message) => {});

  wsConnections.push(ws);
});

// ? Send the update to all connected clients
setInterval(() => {
  let updates = compileLiqUpdateMessage(orderBooks);
  let message = JSON.stringify({
    message_id: "LIQUIDITY_UPDATE",
    liquidity_updates: updates,
  });

  let fillMessage = fillUpdates.length
    ? JSON.stringify({
        message_id: "SWAP_FILLED",
        fillUpdates: fillUpdates,
      })
    : null;

  fillUpdates = [];

  for (const ws of wsConnections) {
    ws.send(message);
    if (fillMessage) {
      ws.send(fillMessage);
    }
  }
}, SEND_LIQUIDITY_PERIOD);

console.log("WebSocket server started on port 4040");

/// =============================================================================

// * EXECUTE DEPOSIT -----------------------------------------------------------------
app.post("/execute_deposit", (req, res) => {
  client.execute_deposit(req.body, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      res.send({ response: response });
    }
  });
});

// * SUBMIT LIMIT ORDER ---------------------------------------------------------------------
app.post("/submit_limit_order", (req, res) => {
  client.submit_limit_order(req.body, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      storeSpotOrder(db, response.order_id, req.body);

      res.send({ response: response });
    }
  });
});

// * EXECUTE WITHDRAWAL ---------------------------------------------------------------
app.post("/execute_withdrawal", (req, res) => {
  client.execute_withdrawal(req.body, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      res.send({ response: response });
    }
  });
});

// * EXECUTE PERPETUAL SWAP -----------------------------------------------------------
app.post("/submit_perpetual_order", (req, res) => {
  client.submit_perpetual_order(req.body, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      storePerpOrder(db, response.order_id, req.body);

      res.send({ response: response });
    }
  });
});

// * EXECUTE LIQUIDATION ORDER -----------------------------------------------------------
app.post("/submit_liquidation_order", (req, res) => {
  client.submit_liquidation_order(req.body, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      res.send({ response: response });
    }
  });
});

// * GET LIQUIDATABLE POSITIONS -----------------------------------------------------------
app.post("/get_liquidatable_positions", (req, res) => {
  let { token, price } = req.body;
  getLiquidatablePositions(db, token, price).then((response) => {
    res.send({ response: response });
  });
});

// * CANCEL ORDER ---------------------------------------------------------------------
app.post("/cancel_order", (req, res) => {
  client.cancel_order(req.body, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      res.send({ response: response });
    }
  });
});

// * AMEND ORDER ---------------------------------------------------------------------
app.post("/amend_order", (req, res) => {
  client.amend_order(req.body, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      res.send({ response: response });
    }
  });
});

// *  SPLIT NOTES -----------------------------------------------------------
app.post("/split_notes", (req, res) => {
  client.split_notes(req.body, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      res.send({ response: response });
    }
  });
});

// *  CHANGE POSITION MARGIN -----------------------------------------------------------
app.post("/change_position_margin", (req, res) => {
  client.change_position_margin(req.body, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      res.send({ response: response });
    }
  });
});

// * GET LIQUIDITY ---------------------------------------------------------------------
app.post("/get_liquidity", (req, res) => {
  client.get_liquidity(req.body, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      res.send({ response: response });
    }
  });
});

// * GET ORDERS ---------------------------------------------------------------------
app.post("/get_orders", (req, res) => {
  client.get_orders(req.body, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      res.send({ response: response });
    }
  });
});

// ===================================================================

// * FINALIZE TRANSACTION BATCH
app.post("/finalize_batch", (req, res) => {
  client.finalize_batch(req.body, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      res.send({ response: response });
    }
  });
});

// ===================================================================

// * APPLY FUNDING UPDATE
app.post("/apply_funding", (req, res) => {
  client.apply_funding(req.body, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      res.send({ response: response });
    }
  });
});

// ===================================================================

// * UPDATE INDEX PRICE
app.post("/update_index_price", (req, res) => {
  client.update_index_price(req.body, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      res.send({ response: response });
    }
  });
});

// ===================================================================

app.listen(port, () => {
  console.log(`Example app listening on port ${port}`);
});
