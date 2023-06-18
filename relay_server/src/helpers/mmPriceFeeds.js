const WebSocket = require("ws");
// const fetch = require("node-fetch");
const axios = require("axios");
require("dotenv").config();

const MM_CONFIG = [
  {
    symbol: "BTC/USDC",
    exchange: "binance",
    pair: "BTCUSDT",
  },
  {
    symbol: "ETH/USDC",
    exchange: "binance",
    pair: "ETHUSDT",
  },
];

async function priceUpdate(PRICE_FEEDS) {
  // Set initial prices
  const cryptowatchApiKey = process.env.CRYPTOWATCH_API_KEY;

  for (let config of MM_CONFIG) {
    let summary;
    try {
      summary = await axios
        .get(
          `https://api.cryptowat.ch/markets/${config.exchange}/${config.pair}/summary?apikey=` +
            cryptowatchApiKey
        )
        .then((r) => r.data.result)
        .catch((e) => console.log(e));
    } catch (error) {}

    if (!summary) {
      return;
    }

    let [base, _] = config.symbol.split("/");

    PRICE_FEEDS[base] = {
      percentage: summary.price.change.percentage,
      absolute: summary.price.change.absolute,
      price: summary.price.last,
    };
  }
}

module.exports = {
  priceUpdate,
};
