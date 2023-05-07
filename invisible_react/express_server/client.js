const express = require("express");
const app = express();
const port = 4000;

const cors = require("cors");
const {
  listenToLiquidtiyUpdates,
  initDb,
  storeSpotOrder,
  storePerpOrder,
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

const SERVER_URL = "localhost:50052";

let client = new engine.Engine(SERVER_URL, grpc.credentials.createInsecure());

const db = initDb();

// ORDER BOOKS AND LIQUIDITY ====================================================================================

let W3CWebSocket = require("websocket").w3cwebsocket;
let wsClient = new W3CWebSocket("ws://localhost:50053/");

wsClient.onopen = function () {
  console.log("WebSocket Client Connected");
  wsClient.send("1234567654321");
};

wsClient.onmessage = function (e) {
  listenToLiquidtiyUpdates(e, db);
};

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

// *  CGANGE POSITION MARGIN -----------------------------------------------------------
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
