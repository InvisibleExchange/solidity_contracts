const grpc = require("@grpc/grpc-js");
const protoLoader = require("@grpc/proto-loader");

const path = require("path");

const packageDefinition = protoLoader.loadSync(
  path.join(__dirname, "../../../../invisible_backend/proto/engine.proto"),
  { keepCase: true, longs: String, enums: String, defaults: true, oneofs: true }
);
const engine = grpc.loadPackageDefinition(packageDefinition).engine;

let client = new engine.Engine(
  "localhost:50052",
  grpc.credentials.createInsecure()
);

/// =============================================================================

// * EXECUTE DEPOSIT -----------------------------------------------------------------
async function execute_deposit(depositObject) {
  return new Promise((resolve) => {
    setTimeout(() => {
      client.execute_deposit(depositObject, function (err, response) {
        if (err) {
          console.log(err);
        } else {
          resolve(response);
        }
      });
    }, 2000);
  });
}

// * SUBMIT LIMIT ORDER ---------------------------------------------------------------------

async function submit_limit_order(orderObject) {
  return new Promise((resolve) => {
    setTimeout(() => {
      client.submit_limit_order(orderObject, function (err, response) {
        if (err) {
          console.log(err);
        } else {
          resolve(response);
        }
      });
    }, 2000);
  });
}

// * EXECUTE WITHDRAWAL ---------------------------------------------------------------

async function execute_withdrawal(withdrawalObject) {
  return new Promise((resolve) => {
    setTimeout(() => {
      client.execute_withdrawal(withdrawalObject, function (err, response) {
        if (err) {
          console.log(err);
        } else {
          resolve(response);
        }
      });
    }, 2000);
  });
}

// * EXECUTE PERPETUAL SWAP -----------------------------------------------------------

async function submit_perpetual_order(orderObject) {
  return new Promise((resolve) => {
    setTimeout(() => {
      client.submit_perpetual_order(orderObject, function (err, response) {
        if (err) {
          console.log(err);
        } else {
          resolve(response);
        }
      });
    }, 2000);
  });
}

// * CANCEL ORDER ---------------------------------------------------------------------

async function cancel_order(cancelObject) {
  return new Promise((resolve) => {
    setTimeout(() => {
      client.cancel_order(cancelObject, function (err, response) {
        if (err) {
          console.log(err);
        } else {
          resolve(response);
        }
      });
    }, 2000);
  });
}

// *  SPLIT NOTES -----------------------------------------------------------

async function split_notes(splitObject) {
  return new Promise((resolve) => {
    setTimeout(() => {
      client.split_notes(splitObject, function (err, response) {
        if (err) {
          console.log(err);
        } else {
          resolve(response);
        }
      });
    }, 2000);
  });
}

// *  CGANGE POSITION MARGIN -----------------------------------------------------------

async function change_position_margin(ChangeMarginObject) {
  return new Promise((resolve) => {
    setTimeout(() => {
      client.change_position_margin(
        ChangeMarginObject,
        function (err, response) {
          if (err) {
            console.log(err);
          } else {
            resolve(response);
          }
        }
      );
    }, 2000);
  });
}

// * GET LIQUIDITY ---------------------------------------------------------------------

async function get_liquidity(liquidityObject) {
  return new Promise((resolve) => {
    setTimeout(() => {
      client.get_liquidity(liquidityObject, function (err, response) {
        if (err) {
          console.log(err);
        } else {
          resolve(response);
        }
      });
    }, 2000);
  });
}

// * GET ORDERS ---------------------------------------------------------------------

async function get_orders(ordersObject) {
  return new Promise((resolve) => {
    setTimeout(() => {
      client.get_orders(ordersObject, function (err, response) {
        if (err) {
          console.log(err);
        } else {
          resolve(response);
        }
      });
    }, 2000);
  });
}

// ===================================================================

async function update_index_price(indexPriceObject) {
  return new Promise((resolve) => {
    setTimeout(() => {
      client.update_index_price(indexPriceObject, function (err, response) {
        if (err) {
          console.log(err);
        } else {
          resolve(response);
        }
      });
    }, 2000);
  });
}

// ===================================================================

module.exports = {
  execute_deposit,
  submit_limit_order,
  execute_withdrawal,
  submit_perpetual_order,
  cancel_order,
  split_notes,
  change_position_margin,
  get_liquidity,
  get_orders,
  update_index_price,
};
