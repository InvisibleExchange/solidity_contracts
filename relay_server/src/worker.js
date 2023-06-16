// worker.js
const amqp = require("amqplib/callback_api");

const grpc = require("@grpc/grpc-js");
const protoLoader = require("@grpc/proto-loader");
const { initDb, storeSpotOrder, storePerpOrder } = require("./helpers");

const path = require("path");
const protoPath = path.join(
  __dirname,
  "../../invisible_backend/proto",
  "engine.proto"
);

const packageDefinition = protoLoader.loadSync(protoPath, {
  keepCase: true,
  longs: String,
  enums: String,
  defaults: true,
  oneofs: true,
});
const engine = grpc.loadPackageDefinition(packageDefinition).engine;
const SERVER_URL = "localhost";
// const SERVER_URL = "54.212.28.196";

const client = new engine.Engine(
  `${SERVER_URL}:50052`,
  grpc.credentials.createInsecure()
);

const db = initDb();

const rabbitmqConfig = {
  protocol: "amqp",
  hostname: SERVER_URL,
  port: 5672,
  username: "Snojj25",
  password: "123456790",
  vhost: "relay_server",
};

amqp.connect(rabbitmqConfig, (error0, connection) => {
  if (error0) {
    throw error0;
  }

  connection.createChannel((error1, channel) => {
    if (error1) {
      throw error1;
    }

    const queue = "orders";

    channel.assertQueue(queue, {
      durable: true,
    });

    console.log("Waiting for orders...");

    channel.consume(
      queue,
      async (msg) => {
        try {
          const order = JSON.parse(msg.content.toString());

          const response = JSON.stringify(
            await processOrder(msg.properties.correlationId, order)
          );

          channel.sendToQueue(msg.properties.replyTo, Buffer.from(response), {
            correlationId: msg.properties.correlationId,
          });

          channel.ack(msg);
        } catch (error) {
          console.error("Error processing order:", error);

          channel.nack(msg, false, false); // (message, allUpTo, requeue)
        }
      },
      {
        noAck: false,
      }
    );
  });
});

// PROCESS ORDER ==================================================================

async function processOrder(correlationId, order) {
  if (correlationId.startsWith("deposit")) {
    // Execute deposit in the backend engine
    let res = await callDepositRpcWithPromise(order);

    return res;
  } else if (correlationId.startsWith("withdrawal")) {
    // Execute withdrawal in the backend engine
    let res = await callWithdrawalRpcWithPromise(order);

    return res;
  } else if (correlationId.startsWith("spot_order")) {
    // Execute order in the backend engine
    let res = await callSpotOrderRpcWithPromise(order);

    return res;
  } else if (correlationId.startsWith("perp_order")) {
    // Execute order in the backend engine
    let res = await callPerpOrderRpcWithPromise(order);

    return res;
  } else if (correlationId.startsWith("liquidation_order")) {
    // Execute order in the backend engine
    let res = await callLiquidationOrderRpcWithPromise(order);

    return res;
  } else if (correlationId.startsWith("cancel")) {
    // Cancels order in the backend engine
    let res = await callCancelRpcWithPromise(order);

    return res;
  } else if (correlationId.startsWith("amend")) {
    // Cancels order in the backend engine
    let res = await callAmendRpcWithPromise(order);

    return res;
  } else if (correlationId.startsWith("split_notes")) {
    // restructures notes in the backend engine
    let res = await callSplitNotesRpcWithPromise(order);

    return res;
  } else if (correlationId.startsWith("change_margin")) {
    // changes the margin for a position in the backend engine
    let res = await callChangeMarginRpcWithPromise(order);

    return res;
  } else if (correlationId.startsWith("get_orders")) {
    // gets all orders for a user in the backend engine
    let res = await callGetOrderRpcWithPromise(order);

    return res;
  } else if (correlationId.startsWith("get_liquidity")) {
    // gets all liquidity for a user in the backend engine
    let res = await callGetLiquidityRpcWithPromise(order);

    return res;
  }

  // sleep for 5 seconds
  await new Promise((resolve) => setTimeout(resolve, 5000));
  throw new Error("Order timed out");
}

function callDepositRpcWithPromise(depositRequest) {
  return new Promise((resolve, reject) => {
    client.execute_deposit(depositRequest, function (err, response) {
      if (err) {
        reject(error);
      } else {
        resolve(response);
      }
    });
  });
}

function callWithdrawalRpcWithPromise(withdrawalRequest) {
  return new Promise((resolve, reject) => {
    client.execute_withdrawal(withdrawalRequest, function (err, response) {
      if (err) {
        reject(err);
      } else {
        resolve(response);
      }
    });
  });
}

function callSpotOrderRpcWithPromise(orderObject) {
  return new Promise((resolve, reject) => {
    client.submit_limit_order(orderObject, function (err, response) {
      if (err) {
        reject(err);
      } else {
        if (response.successful) {
          storeSpotOrder(db, response.order_id, orderObject);
        }

        resolve(response);
      }
    });
  });
}

function callPerpOrderRpcWithPromise(orderObject) {
  return new Promise((resolve, reject) => {
    client.submit_perpetual_order(orderObject, function (err, response) {
      if (err) {
        reject(err);
      } else {
        if (response.successful) {
          storePerpOrder(db, response.order_id, orderObject);
        }

        resolve(response);
      }
    });
  });
}

function callLiquidationOrderRpcWithPromise(orderObject) {
  return new Promise((resolve, reject) => {
    client.submit_liquidation_order(orderObject, function (err, response) {
      if (err) {
        reject(err);
      } else {
        if (response.successful) {
          storePerpOrder(db, response.order_id, orderObject);
        }

        resolve(response);
      }
    });
  });
}

function callCancelRpcWithPromise(cancelReq) {
  return new Promise((resolve, reject) => {
    client.cancel_order(cancelReq, function (err, response) {
      if (err) {
        reject(err);
      } else {
        resolve(response);
      }
    });
  });
}

function callAmendRpcWithPromise(amendReq) {
  return new Promise((resolve, reject) => {
    client.amend_order(amendReq, function (err, response) {
      if (err) {
        reject(err);
      } else {
        resolve(response);
      }
    });
  });
}

function callSplitNotesRpcWithPromise(splitReq) {
  return new Promise((resolve, reject) => {
    client.split_notes(splitReq, function (err, response) {
      if (err) {
        reject(err);
      } else {
        resolve(response);
      }
    });
  });
}

function callChangeMarginRpcWithPromise(marginReq) {
  return new Promise((resolve, reject) => {
    client.change_position_margin(marginReq, function (err, response) {
      if (err) {
        reject(err);
      } else {
        resolve(response);
      }
    });
  });
}

function callGetOrderRpcWithPromise(ordersReq) {
  return new Promise((resolve, reject) => {
    client.get_orders(ordersReq, function (err, response) {
      if (err) {
        reject(err);
      } else {
        resolve(response);
      }
    });
  });
}

function callGetLiquidityRpcWithPromise(liquidityReq) {
  return new Promise((resolve, reject) => {
    client.get_liquidity(liquidityReq, function (err, response) {
      if (err) {
        reject(err);
      } else {
        resolve(response);
      }
    });
  });
}