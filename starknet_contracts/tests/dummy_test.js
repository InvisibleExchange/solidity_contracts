const { expect, assert } = require("chai");

const fs = require("fs");
const starknet = require("starknet");
const BigNumber = require("bignumber.js");
const { bnToUint256 } = require("starknet/dist/utils/uint256");
const hex = require("string-hex");
const { getSelectorFromName } = require("starknet/utils/hash");

const priv_key = "0xcd613e30d8f16adf91b7584a2265b1f5";
const address =
  "0x7d2f37b75a5e779f7da01c22acee1b66c39e8ba470ee5448f05e1462afcedb4";

const provider = new starknet.Provider({
  sequencer: {
    baseUrl: "http://127.0.0.1:5050/",
    feederGatewayUrl: "feeder_gateway",
    gatewayUrl: "gateway",
    // chainId: "0x3f44ea7b21c57b7e",
  },
});

const starkKeyPub = starknet.ec.getKeyPair(priv_key);
const account = new starknet.Account(provider, address, starkKeyPub);

describe("Interaction tests", function () {
  this.timeout(100_000);
  before(async function () {});

  it("should test contract", async function () {
    let test_compiled = starknet.json.parse(
      fs.readFileSync(`../artifacts/test.json`).toString("ascii")
    );
    let test_abi = starknet.json.parse(
      fs.readFileSync(`../artifacts/abis/test.json`).toString("ascii")
    );
    let factory = new starknet.ContractFactory(
      test_compiled,
      account,
      test_abi
    );
    let deploy_contract = await factory.deploy([], "0x1111");

    let res1 = await account.execute({
      contractAddress: deploy_contract.address,
      entrypoint: "get_public_key",
      calldata: [],
    });

    await account.waitForTransaction(res1.transaction_hash);

    res1 = await provider.getTransactionReceipt(res1.transaction_hash);

    let event_data1 = res1.events[0].data;

    console.log(event_data1);
  });
});
