const express = require("express");
const app = express();
const port = 4000;

const cors = require("cors");
const {
  initDb,
  storeSpotOrder,
  storePerpOrder,
  initLiquidity,
} = require("./helpers/helpers");

const grpc = require("@grpc/grpc-js");
const protoLoader = require("@grpc/proto-loader");
const { initServer, initFundingInfo } = require("./helpers/initServer");

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

initLiquidity(db);

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
function update24HInfo(fillUpdates) {
  for (let i = 0; i < fillUpdates.length; i++) {
    let trade = JSON.parse(fillUpdates[i]);

    if (trade.type == "spot") {
      if (spot24hTrades[trade.asset]) {
        spot24hTrades[trade.asset] += 1;
        spot24hVolumes[trade.asset] += trade.amount;
      } else {
        spot24hTrades[trade.asset] = 1;
        spot24hVolumes[trade.asset] = trade.amount;
      }
    } else {
      if (perp24hTrades[trade.asset]) {
        perp24hTrades[trade.asset] += 1;
        perp24hVolumes[trade.asset] += trade.amount;
      } else {
        perp24hTrades[trade.asset] = 1;
        perp24hVolumes[trade.asset] = trade.amount;
      }
    }
  }
}

let fundingRates = {};
let fundingPrices = {};
function updateFundingInfo(rates, prices) {
  fundingRates = rates;
  fundingPrices = prices;
}

initServer(db, updateSpot24hInfo, updatePerp24hInfo, update24HInfo);
initFundingInfo(client, updateFundingInfo);

/// =============================================================================

// * EXECUTE DEPOSIT -----------------------------------------------------------------
app.post("/execute_deposit", (req, res) => {
  client.execute_deposit(req.body, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      console.log(response);
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
      res.send({ response: response });

      storeSpotOrder(db, response.order_id, req.body);
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
// app.post("/get_liquidatable_positions", (req, res) => {
//   let { token, price } = req.body;
//   getLiquidatablePositions(db, token, price).then((response) => {
//     res.send({ response: response });
//   });
// });

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

// *  OPEN NEW ORDER TAB -----------------------------------------------------------
app.post("/open_order_tab", (req, res) => {
  client.open_order_tab(req.body, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      res.send({ response: response });
    }
  });
});

// *  CLOSE ORDER TAB -----------------------------------------------------------
app.post("/close_order_tab", (req, res) => {
  client.close_order_tab(req.body, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      res.send({ response: response });
    }
  });
});

// *  MODIFY ORDER TAB -----------------------------------------------------------
app.post("/modify_order_tab", (req, res) => {
  client.modify_order_tab(req.body, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      res.send({ response: response });
    }
  });
});

// *  REGISTER ORDER TAB -----------------------------------------------------------
app.post("/onchain_register_mm", (req, res) => {
  client.onchain_register_mm(req.body, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      res.send({ response: response });
    }
  });
});

// *  ADD LIQUIDITY ORDER TAB -----------------------------------------------------------
app.post("/add_liquidity_mm", (req, res) => {
  client.add_liquidity_mm(req.body, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      res.send({ response: response });
    }
  });
});

// *  REMOVE LIQUIDITY ORDER TAB -----------------------------------------------------------
app.post("/remove_liquidity_mm", (req, res) => {
  client.remove_liquidity_mm(req.body, function (err, response) {
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

// * GET FUNDING INFO
app.post("/get_market_info", (req, res) => {
  // TODO: For testing
  fundingRates = {
    12345: [272, 103, -510],
    54321: [321, -150, 283],
    66666: [-100, 250, 333],
  };
  fundingPrices = {
    12345: [25000_000_000, 25130_000_000, 25300_000_000],
    54321: [1500_000_000, 1600_000_000, 1700_000_000],
    66666: [10850, 10850, 10850],
  };

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
