const axios = require("axios");
const User = require("../users/Invisibl3User");
const { Note } = require("../users/Notes");
const {
  storeNewNote,
  removeNoteFromDb,
} = require("./firebase/firebaseConnection");

const SYMBOLS_TO_IDS = {
  BTC: 12345,
  ETH: 54321,
  USDC: 55555,
};

const LEVERAGE_BOUNDS_PER_ASSET = {
  12345: [2.5, 50.0], // BTC
  54321: [25.0, 500.0], // ETH
};

const DECIMALS_PER_ASSET = {
  12345: 8, // BTC
  54321: 8, // ETH
  55555: 6, // USDC
};

const PRICE_DECIMALS_PER_ASSET = {
  12345: 6, // BTC
  54321: 6, // ETH
};

const DUST_AMOUNT_PER_ASSET = {
  12345: 100, // BTC ~ 1c
  54321: 1000, // ETH ~ 1c
  55555: 1000, // USDC ~ 0.1c
};

const LEVERAGE_DECIMALS = 6;
const COLLATERAL_TOKEN_DECIMALS = 6;
const COLLATERAL_TOKEN = 55555;

function get_max_leverage(token, amount) {
  let [min_bound, max_bound] = LEVERAGE_BOUNDS_PER_ASSET[token];

  const token_decimals = DECIMALS_PER_ASSET[token];
  const decimal_amount = amount / 10 ** token_decimals;

  let maxLev;
  if (decimal_amount < min_bound) {
    maxLev = 20;
  } else if (decimal_amount < max_bound) {
    // b. For trades between $100,000 and $1,000,000, reduce the maximum leverage proportionally, such as 50 * ($100,000/$trade size).

    maxLev = 20 * (min_bound / decimal_amount);
  } else {
    maxLev = 1;
  }

  return maxLev * 10 ** LEVERAGE_DECIMALS;
}

/// Things we keep track of
/// Index prices
/// Orderbooks

function getBankruptcyPrice(
  entryPrice,
  margin,
  size,
  orderSide,
  syntheticToken
) {
  const syntheticDecimals = DECIMALS_PER_ASSET[syntheticToken];
  const syntheticPriceDecimals = PRICE_DECIMALS_PER_ASSET[syntheticToken];

  const decConversion1 =
    syntheticPriceDecimals - COLLATERAL_TOKEN_DECIMALS + syntheticDecimals;
  const multiplier1 = 10 ** decConversion1;

  if (orderSide == "Long" || orderSide == 0) {
    return entryPrice - (margin * multiplier1) / size;
  } else {
    const bp = entryPrice + (margin * multiplier1) / size;
    return bp;
  }
}

function getLiquidationPrice(entryPrice, bankruptcyPrice, orderSide) {
  if (bankruptcyPrice == 0) {
    return 0;
  }

  // maintnance margin
  let mm_rate = 3; // 3% of 100

  // liquidation price is 2% above/below the bankruptcy price
  if (orderSide == "Long" || orderSide == 0) {
    return bankruptcyPrice + (mm_rate * entryPrice) / 100;
  } else {
    return bankruptcyPrice - (mm_rate * entryPrice) / 100;
  }
}

function getCurrentLeverage(indexPrice, size, margin, syntheticToken) {
  if (indexPrice == 0) {
    throw "Index price cannot be 0";
  }

  const syntheticDecimals = DECIMALS_PER_ASSET[syntheticToken];
  const syntheticPriceDecimals = PRICE_DECIMALS_PER_ASSET[syntheticToken];

  const decimalConversion =
    syntheticDecimals +
    syntheticPriceDecimals -
    (COLLATERAL_TOKEN_DECIMALS + LEVERAGE_DECIMALS);

  const multiplier = 10 ** decimalConversion;

  const currentLeverage = (indexPrice * size) / (margin * multiplier);

  return currentLeverage;
}

function averageEntryPrice(
  current_size,
  current_entry_price,
  added_size,
  added_entry_price
) {
  let prev_nominal_usd = current_size * current_entry_price;
  let added_nominal_usd = added_size * added_entry_price;

  let average_entry_price =
    (prev_nominal_usd + added_nominal_usd) / (current_size + added_size);

  return average_entry_price;
}

const SPOT_MARKET_IDS = {
  BTCUSD: 11,
  ETHUSD: 12,
};

const PERP_MARKET_IDS = {
  BTCUSD: 21,
  ETHUSD: 22,
};

/**
 * gets the order book entries for a given market
 * ## Params:
 * @param  symbol "BTCUSD"/"ETHUSD"
 * @param  isPerp if is perpetual market
 * ## Returns:
 * @return {} {bid_queue, ask_queue}  queue structure= [price, size, timestamp]
 */
async function fetchLiquidity(symbol, isPerp) {
  let marketId = isPerp ? PERP_MARKET_IDS[symbol] : SPOT_MARKET_IDS[symbol];

  await axios
    .post("http://localhost:4000/get_liquidity", {
      market_id: marketId,
      is_perp: isPerp,
    })
    .then((res) => {
      let liquidity_response = res.data.response;

      if (liquidity_response.successful) {
        let bid_queue = liquidity_response.bid_queue;
        let ask_queue = liquidity_response.ask_queue;

        return { bid_queue, ask_queue };
      } else {
        let msg =
          "Getting liquidity failed with error: \n" +
          liquidity_response.error_message;
        throw new Error(msg);
      }
    });
}

// Also a websocket to listen to orderbook updates
// let W3CWebSocket = require("websocket").w3cwebsocket;
// client = new W3CWebSocket("ws://localhost:50053/");

// client.onopen = function () {
//   client.send(trimHash(user.userId, 64));
// };

// client.onmessage = function (e) {
//   let msg = JSON.parse(e.data);

// MESSAGE OPTIONS:

// 1.)
// "message_id": LIQUIDITY_UPDATE,
// "type": "perpetual"/"spot"
// "market":  11 / 12 / 21 / 22
// "ask_liquidity": [ [price, size, timestamp], [price, size, timestamp], ... ]
// "bid_liquidity": [ [price, size, timestamp], [price, size, timestamp], ... ]

// 2.)
// "message_id": "PERPETUAL_SWAP",
// "order_id": u64,
// "swap_response": responseObject,
// -> handlePerpSwapResult(user, responseObject)

// 3.)
// "message_id": "SWAP_RESULT",
// "order_id": u64,
// "swap_response": responseObject,
// -> handleSwapResult(user, responseObject)

/**
 * Handles the result received from the backend after a swap executed.
 * @param  result  The result structure is:
 *  result format:
 *   {
 *          swap_note: Note
 *          new_pfr_note: Note or null,
 *          new_amount_filled: u64,
 *   }
 */
function handleSwapResult(user, swap_response) {
  //

  let swapNoteObject = swap_response.swap_note;
  let swapNote = Note.fromGrpcObject(swapNoteObject);
  if (user.noteData[swapNote.token]) {
    user.noteData[swapNote.token].push(swapNote);
  } else {
    user.noteData[swapNote.token] = [swapNote];
  }

  let newPfrNote_ = swap_response.new_pfr_note;
  if (newPfrNote_) {
    let newPfrNote = Note.fromGrpcObject(newPfrNote_);
    user.pfrNotes.push(newPfrNote);
  }

  let order_id = swap_response.order_id;

  let idx = user.orders.findIndex((o) => o.order_id == order_id);
  let order = user.orders[idx];
  order.qty_left = order.qty_left - swap_response.swap_note.amount;

  // TODO: lest then 000
  if (order.qty_left <= 0) {
    user.orders.splice(idx, 1);
  } else {
    user.orders[idx] = order;
  }
}

/**
 * Handles the result received from the backend after a perpetual swap executed.
 * @param  result  The result structure is:
 *  result format:
 *   {
 *       position: PerpPosition/null,
 *       new_pfr_info: [Note, u64,u64]>/null,
 *       return_collateral_note: Note/null,
 *    }
 */
function handlePerpSwapResult(user, swap_response) {
  //

  // ? Save position data (if not null)
  let position = swap_response.position;
  if (position) {
    if (user.positionData[position.token]) {
      user.positionData[position.token].push(position);
    } else {
      user.positionData[position.token] = [position];
    }
  }

  // ? Save partiall fill note (if not null)
  let newPfrInfo = swap_response.new_pfr_info;
  if (newPfrInfo && newPfrInfo[0]) {
    let newPfrNote = Note.fromGrpcObject(newPfrInfo[0]);
    user.pfrNotes.push(newPfrNote);
  }

  // ? Save return collateral note (if not null)
  let returnCollateralNote = swap_response.return_collateral_note;
  if (returnCollateralNote) {
    let returnCollateralNoteObject = Note.fromGrpcObject(returnCollateralNote);
    if (user.noteData[returnCollateralNoteObject.token]) {
      user.noteData[returnCollateralNoteObject.token].push(
        returnCollateralNoteObject
      );
    } else {
      user.noteData[returnCollateralNoteObject.token] = [
        returnCollateralNoteObject,
      ];
    }
  }

  let order_id = swap_response.order_id;

  let idx = user.orders.findIndex((o) => o.order_id == order_id);
  let order = user.orders[idx];
  order.qty_left = order.qty_left - swap_response.swap_note.amount;

  if (order.qty_left <= 000) {
    user.orders.splice(idx, 1);
  } else {
    user.orders[idx] = order;
  }
}

/**
 * Handles the result received from the backend after a note split(restructuring)
 * Removes the previous notes and adds the new notes to the user's noteData and database.
 * @param  zero_idxs  The indexes of new notes
 */
function handleNoteSplit(user, zero_idxs, notesIn, notesOut) {
  //

  for (const noteIn of notesIn) {
    user.noteData[noteIn.token].filter((n) => n.index != noteIn.index);
  }

  if (notesIn.length > notesOut.length) {
    for (let i = notesOut.length; i < notesIn.length; i++) {
      let note = notesIn[i];
      removeNoteFromDb(note);
    }

    for (let i = 0; i < zero_idxs.length; i++) {
      let note = notesOut[i];
      note.index = zero_idxs[i];
      storeNewNote(note);
      user.noteData[note.token].push(note);
    }
  } else {
    for (let i = 0; i < zero_idxs.length; i++) {
      let note = notesOut[i];
      note.index = zero_idxs[i];
      storeNewNote(note);
      user.noteData[note.token].push(note);
    }
  }
}

//

//

//

/**
 * This ask the user to sign a message to login. The signature is used to derive the private key
 * and use it to login and fetch all the user's data.
 * @param  signer  ethers.js signer
 */
async function loginUser(signer) {
  const keyDerivation =
    require("@starkware-industries/starkware-crypto-utils").keyDerivation;

  let sig = await signer.signMessage(
    "Sign this message to access your Invisibl3 account. \nIMPORTANT: Only sign this message on Invisible.com!!"
  );

  let pk = keyDerivation.getPrivateKeyFromEthSignature(sig);

  console.log(pk);

  let user = User.fromPrivKey(privKey);

  await user.login();

  let { badOrderIds, orders, badPerpOrderIds, perpOrders } =
    await getActiveOrders(user.orderIds, user.perpetualOrderIds);

  await user.handleActiveOrders(
    badOrderIds,
    orders,
    badPerpOrderIds,
    perpOrders
  );

  return user;
}

async function getActiveOrders(order_ids, perp_order_ids) {
  return await axios
    .post("http://localhost:4000/get_orders", { order_ids, perp_order_ids })
    .then((res) => {
      let order_response = res.data.response;

      let badOrderIds = order_response.bad_order_ids;
      let orders = order_response.orders;
      let badPerpOrderIds = order_response.bad_perp_order_ids;
      let perpOrders = order_response.perp_orders;
      let pfrNotes = order_response.pfr_notes;

      return { badOrderIds, orders, badPerpOrderIds, perpOrders, pfrNotes };
    })
    .catch((err) => {
      alert(err);
    });
}

//

//

//

//

//

module.exports = {
  DECIMALS_PER_ASSET,
  PRICE_DECIMALS_PER_ASSET,
  DUST_AMOUNT_PER_ASSET,
  LEVERAGE_DECIMALS,
  COLLATERAL_TOKEN_DECIMALS,
  COLLATERAL_TOKEN,
  get_max_leverage,
  getBankruptcyPrice,
  getLiquidationPrice,
  getCurrentLeverage,
  averageEntryPrice,
  handleSwapResult,
  handlePerpSwapResult,
  handleNoteSplit,
  getActiveOrders,
  loginUser,
  SYMBOLS_TO_IDS,
};
