const express = require("express");
const app = express();
const port = 4000;

const amqp = require("amqplib/callback_api");

const cors = require("cors");
const {
  listenToLiquidityUpdates,
  initDb,
  compileLiqUpdateMessage,
  initOrderBooks,
} = require("./helpers");

const corsOptions = {
  origin: "*",
  credentials: true, //access-control-allow-credentials:true
  optionSuccessStatus: 200,
};

app.use(cors(corsOptions));
app.use(express.json());

const db = initDb();

const CONFIG_CODE = "1234567890";
const RELAY_SERVER_ID = "43147634234";
const SERVER_URL = "localhost";
// const SERVER_URL = "54.212.28.196";

// * ORDER BOOKS AND LIQUIDITY ====================================================================================

const orderBooks = initOrderBooks();
let fillUpdates = [];
let wsConnections = [];

// & WEBSOCKET CLIENT
let W3CWebSocket = require("websocket").w3cwebsocket;
let wsClient = new W3CWebSocket(`ws://${SERVER_URL}:50053/`);

wsClient.onopen = function () {
  console.log("WebSocket Client Connected");
  wsClient.send({ user_id: RELAY_SERVER_ID, config_code: CONFIG_CODE });
};

wsClient.onmessage = function (e) {
  listenToLiquidityUpdates(e, db, orderBooks, fillUpdates);
};

// & WEBSOCKET SERVER
const WebSocket = require("ws");
const wss = new WebSocket.Server({ port: 4040 });
const SEND_LIQUIDITY_PERIOD = 2000;

wss.on("connection", (ws) => {
  ws.on("message", (message) => {});

  wsConnections.push(ws);

  ws.on("close", () => {});
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

//

// setInterval(async () => {
//   // Call an API here

//   let updates = [];
//   for (let token of [12345, 54321]) {
//     let update = await getOracleUpdate(token);
//     updates.push(update);
//   }

//   client.update_index_price(
//     { oracle_price_updates: updates },
//     function (err, response) {
//       if (err) {
//         console.log(err);
//       } else {
//         console.log(response);
//       }
//     }
//   );
// }, 3000);

// * RABBITMQ CONFIG ====================================================================================

const rabbitmqConfig = {
  protocol: "amqp",
  hostname: SERVER_URL,
  port: 5672,
  username: "Snojj25",
  password: "123456790",
  vhost: "relay_server",
};

// const cluster = require("cluster");
// const numCPUs = require("os").cpus().length;

// if (cluster.isMaster) {
//   // Master process forks worker processes
//   for (let i = 0; i < numCPUs; i++) {
//     cluster.fork();
//   }
// } else {

amqp.connect(rabbitmqConfig, (error0, connection) => {
  if (error0) {
    throw error0;
  } else {
    console.log("Connected to RabbitMQ");
  }

  connection.createChannel((error1, channel) => {
    if (error1) {
      throw error1;
    } else {
      console.log("Created channel");
    }

    const queue = "orders";

    channel.assertQueue(queue, {
      durable: true,
    });

    const correlationIdToResolve = new Map();

    channel.consume(
      "amq.rabbitmq.reply-to",
      (msg) => {
        const correlationId = msg.properties.correlationId;
        const res = correlationIdToResolve.get(correlationId);
        if (res) {
          correlationIdToResolve.delete(correlationId);

          res.send({ response: JSON.parse(msg.content) });
        }
      },
      { noAck: true }
    );

    // TODO

    // * EXECUTE DEPOSIT -----------------------------------------------------------------
    app.post("/execute_deposit", (req, res) => {
      delegateRequest(
        req.body,
        "deposit",
        channel,
        res,
        queue,
        correlationIdToResolve
      );
    });

    // * EXECUTE WITHDRAWAL ---------------------------------------------------------------
    app.post("/execute_withdrawal", (req, res) => {
      delegateRequest(
        req.body,
        "withdrawal",
        channel,
        res,
        queue,
        correlationIdToResolve
      );
    });

    // * SUBMIT LIMIT ORDER --------------------------------------------------------------
    app.post("/submit_limit_order", (req, res) => {
      delegateRequest(
        req.body,
        "spot_order",
        channel,
        res,
        queue,
        correlationIdToResolve
      );
    });

    // // * EXECUTE PERPETUAL SWAP -----------------------------------------------------------
    app.post("/submit_perpetual_order", (req, res) => {
      delegateRequest(
        req.body,
        "perp_order",
        channel,
        res,
        queue,
        correlationIdToResolve
      );
    });

    // * CANCEL ORDER ---------------------------------------------------------------------
    app.post("/cancel_order", (req, res) => {
      delegateRequest(
        req.body,
        "cancel",
        channel,
        res,
        queue,
        correlationIdToResolve
      );
    });

    // * CANCEL ORDER ---------------------------------------------------------------------
    app.post("/amend_order", (req, res) => {
      delegateRequest(
        req.body,
        "amend",
        channel,
        res,
        queue,
        correlationIdToResolve
      );
    });

    // *  SPLIT NOTES -----------------------------------------------------------
    app.post("/split_notes", (req, res) => {
      delegateRequest(
        req.body,
        "split_notes",
        channel,
        res,
        queue,
        correlationIdToResolve
      );
    });

    // *  CGANGE POSITION MARGIN -----------------------------------------------------------
    app.post("/change_position_margin", (req, res) => {
      delegateRequest(
        req.body,
        "change_margin",
        channel,
        res,
        queue,
        correlationIdToResolve
      );
    });

    // * GET LIQUIDITY ---------------------------------------------------------------------
    app.post("/get_liquidity", (req, res) => {
      delegateRequest(
        req.body,
        "get_liquidity",
        channel,
        res,
        queue,
        correlationIdToResolve
      );
    });

    // * GET ORDERS ---------------------------------------------------------------------

    app.post("/get_orders", (req, res) => {
      delegateRequest(
        req.body,
        "get_orders",
        channel,
        res,
        queue,
        correlationIdToResolve
      );
    });

    // // ===================================================================

    // // * FINALIZE TRANSACTION BATCH
    // // app.post("/finalize_batch", (req, res) => {
    // //   console.log("finalize_batch");

    // //   client.finalize_batch(req.body, function (err, response) {
    // //     if (err) {
    // //       console.log(err);
    // //     } else {
    // //       res.send({ response: response });
    // //     }
    // //   });
    // // });

    // // ===================================================================

    // // * APPLY FUNDING UPDATE
    // app.post("/start_funding", (req, res) => {
    //   client.start_funding(req.body, function (err, response) {
    //     if (err) {
    //       console.log(err);
    //     } else {
    //       res.send({ response: response });
    //     }
    //   });
    // });

    // // ===================================================================

    // // * UPDATE INDEX PRICE
    // app.post("/update_index_price", (req, res) => {
    //   console.log("update_index_price");

    //   client.update_index_price(req.body, function (err, response) {
    //     if (err) {
    //       console.log(err);
    //     } else {
    //       res.send({ response: response });
    //     }
    //   });
    // });

    // TODO
  });
});

app.listen(port, () => {
  console.log(`App listening on port ${port}`);
});

/**
 *
 * @param {*} reqBody the json order to send to backend
 * @param {*} orderType "deposit"/"withdrawal"/"spot_order"/"perp_order"
 * @param {*} channel The channel to delegate the execution to the worker
 * @param {*} res the express res object to return a response to the user
 * @param {*} queue the queue to send the order to
 */
function delegateRequest(
  reqBody,
  orderType,
  channel,
  res,
  queue,
  correlationIdToResolve
) {
  const order = JSON.stringify(reqBody);

  // "deposit" + "withdrawal" + "spot_order" + "perp_order + "cancel" + "amend
  const correlationId =
    orderType.toString() +
    Math.random().toString() +
    Math.random().toString() +
    Math.random().toString();

  correlationIdToResolve.set(correlationId, res);

  channel.sendToQueue(queue, Buffer.from(order), {
    correlationId: correlationId,
    replyTo: "amq.rabbitmq.reply-to",
  });
}
