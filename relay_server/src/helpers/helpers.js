let activeOrderIds = {}; // {market_id: [orderId1, orderId2, ...]}

// WEBSOCKETS

class OrderBook {
  constructor(marketId, isPerp) {
    this.market_id = marketId;
    this.is_perp = isPerp;
    this.bid_queue = []; // [price, size, timestamp]
    this.ask_queue = []; // [price, size, timestamp]
    this.prev_bid_queue = []; // [price, size, timestamp]
    this.prev_ask_queue = []; // [price, size, timestamp]
  }

  updateAndCompare() {
    let isBidQueueSame = this.bid_queue.equals(this.prev_bid_queue);
    let isAskQueueSame = this.ask_queue.equals(this.prev_ask_queue);

    this.prev_ask_queue = this.ask_queue;
    this.prev_bid_queue = this.bid_queue;

    return {
      bidQueue: this.bid_queue,
      askQueue: this.ask_queue,
      isBidQueueSame,
      isAskQueueSame,
    };
  }
}

function initOrderBooks() {
  const markets = [11, 12];
  const perpMarkets = [21, 22];

  let orderBooks = {};
  for (let market of markets) {
    orderBooks[market] = new OrderBook(market, false);
  }
  for (let market of perpMarkets) {
    orderBooks[market] = new OrderBook(market, true);
  }
  return orderBooks;
}

function listenToLiquidityUpdates(e, db, orderBooks, fillUpdates) {
  let msg = JSON.parse(e.data);

  if (msg.message_id == "LIQUIDITY_UPDATE") {
    for (let liq_msg of msg.liquidity) {
      let book = orderBooks[liq_msg.market];

      book.bid_queue = liq_msg.bid_liquidity;
      book.ask_queue = liq_msg.ask_liquidity;

      let newActiveOrders = [];
      liq_msg.bid_liquidity.forEach((el) => {
        newActiveOrders.push(el[3]);
      });
      liq_msg.ask_liquidity.forEach((el) => {
        newActiveOrders.push(el[3]);
      });

      let bidQueue = JSON.stringify(liq_msg.bid_liquidity);
      let askQueue = JSON.stringify(liq_msg.ask_liquidity);

      let spotCommand =
        "UPDATE spotLiquidity SET bidQueue = $1, askQueue = $2 WHERE market_id = $3";
      let perpCommand =
        "UPDATE perpLiquidity SET bidQueue = $1, askQueue = $2 WHERE market_id = $3";

      if (liq_msg.type == "perpetual") {
        try {
          db.run(
            perpCommand,
            [bidQueue, askQueue, Number.parseInt(liq_msg.market)],
            function (err) {
              if (err) {
                return console.error(err.message);
              }
            }
          );
        } catch (error) {
          console.log("error: ", error);
        }
      } else {
        try {
          db.run(
            spotCommand,
            [bidQueue, askQueue, Number.parseInt(liq_msg.market)],
            function (err) {
              if (err) {
                return console.error(err.message);
              }
            }
          );
        } catch (error) {
          console.log("error: ", error);
        }
      }

      if (!activeOrderIds[liq_msg.market]) {
        activeOrderIds[liq_msg.market] = [];
      }

      // Get all orderIds from activeOrderIds[liq_msg.market] array that are not in newActiveOrders array
      let inactiveOrderIds = activeOrderIds[liq_msg.market].filter(
        (el) => !newActiveOrders.includes(el)
      );
      for (const orderId of inactiveOrderIds) {
        let spotCommand = "DELETE FROM spotOrders WHERE order_id = $1";
        let perpCommand = "DELETE FROM perpOrders WHERE order_id = $1";

        try {
          db.run(liq_msg.type == "perpetual" ? perpCommand : spotCommand, [
            orderId,
          ]);
        } catch (error) {
          console.log("error: ", error);
        }
      }
      activeOrderIds[liq_msg.market] = newActiveOrders;
    }
  } else if (msg.message_id == "SWAP_FILLED") {
    //   let json_msg = json!({
    //     "message_id": "SWAP_FILLED",
    //     "type": "spot",
    //     "asset": base_asset,
    //     "amount": qty,
    //     "price": price,
    //     "is_buy": taker_side == OBOrderSide::Bid,
    //     "timestamp": timestamp,
    //     "user_id_a": user_id_pair.0,
    //     "user_id_b": user_id_pair.1,
    // });

    fillUpdates.push(JSON.stringify(msg));
  } else if (msg.message_id == "NEW_POSITIONS") {
    // "message_id": "NEW_POSITIONS",
    // "position1": [position_address, position_index, synthetic_token, is_long, liquidation_price]
    // "position2":  [position_address, position_index, synthetic_token, is_long, liquidation_price]

    if (msg.position1) {
      let [
        position_address,
        position_index,
        synthetic_token,
        is_long,
        liquidation_price,
      ] = msg.position1;
      is_long = is_long ? 1 : 0;
      let command =
        "INSERT OR REPLACE INTO liquidations (position_index, position_address, synthetic_token, order_side, liquidation_price ) VALUES($1, $2, $3, $4, $5)";

      try {
        db.run(
          command,
          [
            position_index,
            position_address,
            synthetic_token,
            is_long,
            liquidation_price,
          ],
          function (err) {
            if (err) {
              return console.error(err.message);
            }
          }
        );
      } catch (error) {
        console.log("error: ", error);
      }
    }
    if (msg.position2) {
      let [
        position_address,
        position_index,
        synthetic_token,
        is_long,
        liquidation_price,
      ] = msg.position2;
      is_long = is_long ? 1 : 0;
      let command =
        "INSERT OR REPLACE INTO liquidations (position_index, position_address, synthetic_token, order_side, liquidation_price) VALUES($1, $2, $3, $4, $5)";

      try {
        db.run(
          command,
          [
            position_index,
            position_address,
            synthetic_token,
            is_long,
            liquidation_price,
          ],
          function (err) {
            if (err) {
              return console.error(err.message);
            }
          }
        );
      } catch (error) {
        console.log("error: ", error);
      }
    }
  }
}

function compileLiqUpdateMessage(orderBooks) {
  let updates = [];

  for (let book of Object.values(orderBooks)) {
    let { bidQueue, askQueue, isBidQueueSame, isAskQueueSame } =
      book.updateAndCompare();

    if (!isBidQueueSame || !isAskQueueSame) {
      updates.push(
        JSON.stringify({
          is_perp: book.is_perp,
          market_id: book.market_id,
          bid_queue: !isBidQueueSame ? bidQueue : null,
          ask_queue: !isAskQueueSame ? askQueue : null,
        })
      );
    }
  }

  return updates;
}

// DB HELPERS ============================================================================================================================

const path = require("path");
const { restoreOrderbooks } = require("./restoreOrderBooks");
function storeSpotOrder(db, order_id, orderObject) {

  let command = `
    INSERT OR REPLACE INTO spotOrders
      (order_id, expiration_timestamp, token_spent, token_received, amount_spent, amount_received,
      fee_limit, spot_note_info, order_tab, signature, user_id) 
    VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
    `;

  try {
    db.run(command, [
      order_id,
      orderObject.expiration_timestamp,
      orderObject.token_spent,
      orderObject.token_received,
      orderObject.amount_spent,
      orderObject.amount_received,
      orderObject.fee_limit,
      // spot_note_info
      orderObject.spot_note_info
        ? JSON.stringify(orderObject.spot_note_info)
        : null,
      // order_tab
      orderObject.order_tab ? JSON.stringify(orderObject.order_tab) : null,
      //
      JSON.stringify(orderObject.signature),
      orderObject.user_id,
    ]);
  } catch (error) {
    console.log("error: ", error);
  }
}

function storePerpOrder(db, order_id, orderObject) {
  let command = `
    INSERT OR REPLACE INTO perpOrders 
      (order_id, expiration_timestamp, position, position_effect_type, order_side, synthetic_token, synthetic_amount, 
      collateral_amount, fee_limit, open_order_fields, close_order_fields, signature, user_id) 
    VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
    `;

  try {
    db.run(command, [
      order_id,
      orderObject.expiration_timestamp,
      JSON.stringify(orderObject.position),
      orderObject.position_effect_type,
      orderObject.order_side,
      orderObject.synthetic_token,
      orderObject.synthetic_amount,
      orderObject.collateral_amount,
      orderObject.fee_limit,
      JSON.stringify(orderObject.open_order_fields),
      JSON.stringify(orderObject.close_order_fields),
      JSON.stringify(orderObject.signature),
      orderObject.user_id,
    ]);
  } catch (error) {
    console.log("error: ", error);
  }
}

const sqlite3 = require("sqlite3").verbose();
function initDb() {
  const createPerpTableCommand = `
  CREATE TABLE IF NOT EXISTS perpOrders 
    (order_id INTEGER PRIMARY KEY NOT NULL, 
    expiration_timestamp INTEGER NOT NULL, 
    position TEXT, 
    position_effect_type INTEGER NOT NULL,
     order_side INTEGER NOT NULL, 
    synthetic_token INTEGER NOT NULL,
    synthetic_amount INTEGER NOT NULL, 
    collateral_amount INTEGER NOT NULL, 
    fee_limit INTEGER NOT NULL, 
    open_order_fields TEXT, 
    close_order_fields TEXT,
    signature TEXT NOT NULL, 
    user_id INTEGER )`;

  // spot_note_info = {dest_received_address, dest_received_blinding, notes_in, refund_note}
  const createSpotTableCommand = `
  CREATE TABLE IF NOT EXISTS spotOrders
  (order_id INTEGER PRIMARY KEY NOT NULL, 
  expiration_timestamp INTEGER NOT NULL,  
  token_spent INTEGER NOT NULL, 
  token_received INTEGER NOT NULL, 
  amount_spent INTEGER NOT NULL,  
  amount_received INTEGER NOT NULL,  
  fee_limit INTEGER NOT NULL, 
  spot_note_info TEXT,
  order_tab TEXT,
  signature TEXT NOT NULL, 
  user_id INTEGER )  `;

  let db = new sqlite3.Database(
    path.join(__dirname, "../orderBooks.db"),
    (err) => {
      if (err) {
        console.error(err.message);
      }
      console.log("Connected to the orderBook database.");
    }
  );

  db.run(createSpotTableCommand);

  db.run(createPerpTableCommand);

  const createSpotLiquidityTableCommand =
    "CREATE TABLE IF NOT EXISTS spotLiquidity (market_id INTEGER PRIMARY KEY UNIQUE NOT NULL, bidQueue TEXT NOT NULL, askQueue TEXT NOT NULL)";
  const createPerpLiquidityTableCommand =
    "CREATE TABLE IF NOT EXISTS perpLiquidity (market_id INTEGER PRIMARY KEY UNIQUE NOT NULL, bidQueue TEXT NOT NULL, askQueue TEXT NOT NULL)";

  db.run(createSpotLiquidityTableCommand, (res, err) => {
    if (err) {
      console.log(err);
    }

    db.run(createPerpLiquidityTableCommand, (res, err) => {
      if (err) {
        console.log(err);
      }
    });
  });

  const createLiquidationTable =
    "CREATE TABLE IF NOT EXISTS liquidations (position_index INTEGER PRIMARY KEY NOT NULL, position_address TEXT NOT NULL, synthetic_token INTEGER NOT NULL, order_side BIT NOT NULL, liquidation_price INTEGER NOT NULL)";

  db.run(createLiquidationTable, (res, err) => {
    if (err) {
      console.log(err);
    }
  });

  return db;
}

function initLiquidity(db) {
  const SPOT_MARKET_IDS = {
    BTCUSD: 11,
    ETHUSD: 12,
  };

  const PERP_MARKET_IDS = {
    BTCUSD: 21,
    ETHUSD: 22,
  };

  // & Restore liquidity from database
  restoreOrderbooks(db);

  // & Create liquidity if it does not exist
  for (let marketId of Object.values(SPOT_MARKET_IDS)) {
    // Check if liquidity already exists
    const query = `SELECT * FROM spotLiquidity WHERE market_id = ${marketId}`;
    db.all(query, [], (err, rows) => {
      if (err) {
        console.error(err.message);
        return;
      }

      if (rows && rows.length == 0) {
        // Liquidity does not exist, so create it
        db.run(
          "INSERT INTO spotLiquidity (market_id, bidQueue, askQueue) VALUES($1, $2, $3)",
          [marketId, JSON.stringify([]), JSON.stringify([])]
        );
      }
    });
  }

  for (let marketId of Object.values(PERP_MARKET_IDS)) {
    // Check if liquidity already exists
    const query = `SELECT * FROM perpLiquidity WHERE market_id = ${marketId}`;
    db.all(query, [], (err, rows) => {
      if (err) {
        console.error(err.message);
        return;
      }

      if (rows && rows.length == 0) {
        // Liquidity does not exist, so create it
        db.run(
          "INSERT INTO perpLiquidity (market_id, bidQueue, askQueue) VALUES($1, $2, $3)",
          [marketId, JSON.stringify([]), JSON.stringify([])]
        );
      }
    });
  }
}

// Warn if overriding existing method
if (Array.prototype.equals)
  console.warn(
    "Overriding existing Array.prototype.equals. Possible causes: New API defines the method, there's a framework conflict or you've got double inclusions in your code."
  );
// attach the .equals method to Array's prototype to call it on any array
Array.prototype.equals = function (array) {
  // if the other array is a falsy value, return
  if (!array) return false;
  // if the argument is the same array, we can be sure the contents are same as well
  if (array === this) return true;
  // compare lengths - can save a lot of time
  if (this.length != array.length) return false;

  for (var i = 0, l = this.length; i < l; i++) {
    // Check if we have nested arrays
    if (this[i] instanceof Array && array[i] instanceof Array) {
      // recurse into the nested arrays
      if (!this[i].equals(array[i])) return false;
    } else if (this[i] != array[i]) {
      // Warning - two different object instances will never be equal: {x:20} != {x:20}
      return false;
    }
  }
  return true;
};
// Hide method from for-in loops
Object.defineProperty(Array.prototype, "equals", { enumerable: false });

// * TESTING ========================================================

module.exports = {
  listenToLiquidityUpdates,
  compileLiqUpdateMessage,
  storeSpotOrder,
  storePerpOrder,
  initDb,
  initOrderBooks,
  initLiquidity,
};
