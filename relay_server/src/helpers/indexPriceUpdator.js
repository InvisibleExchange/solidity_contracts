const grpc = require("@grpc/grpc-js");
const protoLoader = require("@grpc/proto-loader");

const axios = require("axios");

const packageDefinition = protoLoader.loadSync(
  "../../../invisible_backend/proto/engine.proto",
  { keepCase: true, longs: String, enums: String, defaults: true, oneofs: true }
);
const engine = grpc.loadPackageDefinition(packageDefinition).engine;

const SERVER_URL = "localhost:50052";

let client = new engine.Engine(SERVER_URL, grpc.credentials.createInsecure());

const path = require("path");
const dotenv = require("dotenv");

dotenv.config({ path: path.join(__dirname, "../.env") });

let token2symbolPath = {
  12345: "coinbase/btcusd",
  54321: "coinbase/ethusd",
  66666: "binance/pepeusdt",
};
const PRICE_DECIMALS_PER_ASSET = {
  12345: 6, // BTC
  54321: 6, // ETH
  66666: 10, // PEPE
};
const { getKeyPair, sign } = require("starknet").ec;

/**
 *
 * @param {"btcusd" / "ethusd"} symbol
 */
async function getOracleUpdate(token) {
  let symbol = token2symbolPath[token];

  const CRYPTOWATCH_API_KEY = process.env.CRYPTOWATCH_API_KEY;

  let res = await axios
    .get(
      `https://api.cryptowat.ch/markets/${symbol}/price?apikey=` +
        CRYPTOWATCH_API_KEY
    )
    .then((res) => {
      let price = Number(
        res.data.result.price * 10 ** PRICE_DECIMALS_PER_ASSET[token]
      );

      let timestamp = Math.floor(Date.now() / 1000);

      let msg =
        (BigInt(price) * 2n ** 64n + BigInt(token)) * 2n ** 64n +
        BigInt(timestamp);

      let keyPair = getKeyPair("0x1");
      let sig = sign(keyPair, msg.toString(16));

      let oracleUpdate = {
        token: token,
        timestamp: timestamp,
        observer_ids: [0],
        prices: [price],
        signatures: [{ r: sig[0], s: sig[1] }],
      };

      return oracleUpdate;
    })
    .catch((err) => {
      console.log(err);
      return null;
    });

  return res;
}

function main() {
  setInterval(async () => {
    // Call an API here

    let updates = [];
    for (let token of [12345, 54321, 66666]) {
      let update = await getOracleUpdate(token);
      if (update) {
        updates.push(update);
      }
    }
    if (updates.length == 0) {
      return;
    }

    client.update_index_price(
      { oracle_price_updates: updates },
      function (err, response) {
        if (err) {
          console.log(err);
        }
      }
    );
  }, 25_000);
}

main();
