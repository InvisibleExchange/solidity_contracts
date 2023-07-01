const express = require("express");
const app = express();
const port = 4000;

const amqp = require("amqplib/callback_api");

const cors = require("cors");
const { initDb } = require("./helpers/helpers");
const { initServer, initFundingInfoInterval } = require("./helpers/initServer");

const corsOptions = {
  origin: "*",
  credentials: true, //access-control-allow-credentials:true
  optionSuccessStatus: 200,
};

app.use(cors(corsOptions));
app.use(express.json());

const db = initDb();

const SERVER_URL = "54.212.28.196";

let spot24hVolumes = {};
let spot24hTrades = {};
function updateSpot24hInfo(volumes, trades) {
  spot24hVolumes = volumes;
  spot24hTrades = trades;
}
let perp24hVolumes = {};
let perp24hTrades = {};
function updatePerp24hInfo(volumes, trades) {
  perp24hVolumes = volumes;
  perp24hTrades = trades;
}
let fundingRates = {};
let fundingPrices = {};
function updateFundingInfo(rates, prices) {
  fundingRates = rates;
  fundingPrices = prices;
}

initServer(db, updateSpot24hInfo, updatePerp24hInfo);

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

        if (correlationId.startsWith("get_funding_info")) {
          let response = JSON.parse(msg.content);
          if (response.successful) {
            let rates = {};
            let prices = {};
            for (const fundingInfo of response.fundings) {
              rates[fundingInfo.token] = fundingInfo.funding_rates;
              prices[fundingInfo.token] = fundingInfo.funding_prices;
            }

            console.log("Funding info updated");
            console.log(rates);
            console.log(prices);
            updateFundingInfo(rates, prices);
          }
        } else {
          const res = correlationIdToResolve.get(correlationId);
          if (res) {
            correlationIdToResolve.delete(correlationId);

            res.send({ response: JSON.parse(msg.content) });
          }
        }
      },
      { noAck: true }
    );

    initFundingInfoInterval(
      channel,
      queue,
      correlationIdToResolve,
      delegateRequest
    );

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

    // * EXECUTE PERPETUAL SWAP -----------------------------------------------------------
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

    // * EXECUTE PERPETUAL SWAP -----------------------------------------------------------
    app.post("/submit_liquidation_order", (req, res) => {
      delegateRequest(
        req.body,
        "liquidation_order",
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

    // *  CHANGE POSITION MARGIN -----------------------------------------------------------
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

    // * GET ORDERS ------------------------------------------------------------------------
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

    // * UPDATE INDEX PRICE ---------------------------------------------------------------
    app.post("/update_index_price", (req, res) => {
      delegateRequest(
        req.body,
        "update_index_price",
        channel,
        res,
        queue,
        correlationIdToResolve
      );
    });

    // * FINALIZE TRANSACTION BATCH  -------------------------------------------------------
    app.post("/finalize_batch", (req, res) => {
      delegateRequest(
        req.body,
        "finalize_batch",
        channel,
        res,
        queue,
        correlationIdToResolve
      );
    });

    // * GET FUNDING INFO -----------------------------------------------------------------
    app.post("/get_market_info", (req, res) => {
      res.send({
        response: {
          fundingPrices,
          fundingRates,
          spot24hVolumes,
          spot24hTrades,
          perp24hVolumes,
          perp24hTrades,
        },
      });
    });

    //
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
