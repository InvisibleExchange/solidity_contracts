const { expect, assert } = require("chai");

const fs = require("fs");
const starknet = require("starknet");
const BigNumber = require("bignumber.js");

const priv_key = "0x1e2feb89414c343c1027c4d1c386bbc4";
const address =
  "0x433732229ce8222824e40d3b13db581634918fba9e8e733eee866b8a7d29ab4";

const new_priv_key = "8932749863246329746327463249328632";
const new_pub_key =
  "2325812664550263468000998649484612106203340046325053037275531176882642416349";

const withdrawal_contract_address =
  "0x007ef834e0bca2fcbd71e10afb5e8e55ad03c39f1ffb97d300730a0882a023ed";

//
let updated_pub_key = true;
let withdraw_contract_deployed = true;
let token_registered = true;
let withdrawal_updates_made = false;
//

const provider = new starknet.Provider({
  sequencer: {
    baseUrl: "http://127.0.0.1:5050/",
    feederGatewayUrl: "feeder_gateway",
    gatewayUrl: "gateway",
    // chainId: "0x3f44ea7b21c57b7e",
  },
});

const starkKeyPub = starknet.ec.getKeyPair(priv_key);

let privKey = updated_pub_key ? new_priv_key : priv_key;
let keyPair = starknet.ec.getKeyPair(privKey);

const account = new starknet.Account(provider, address, keyPair);

// struct Call {
//     to
//     selector
//     calldata
// }

describe("Interaction tests", function () {
  this.timeout(100_000);
  before(async function () {});

  it("should edit pub key", async function () {
    if (updated_pub_key) {
      return;
    }

    let res = await account.execute({
      contractAddress: account.address,
      entrypoint: "set_public_key",
      calldata: [new_pub_key],
    });

    console.log("res: ", res);
  });

  it("should deploy withdrawal contract", async function () {
    if (withdraw_contract_deployed) {
      return;
    }

    let withdrawal_compiled = starknet.json.parse(
      fs.readFileSync(`../artifacts/withdrawal.json`).toString("ascii")
    );
    let withdrawal_abi = starknet.json.parse(
      fs.readFileSync(`../artifacts/abis/withdrawal.json`).toString("ascii")
    );
    let factory = new starknet.ContractFactory(
      withdrawal_compiled,
      account,
      withdrawal_abi
    );
    let withdrawal_contract = await factory.deploy();

    console.log("withdrawal_contract: ", withdrawal_contract.address);
  });

  it("should register_token", async function () {
    let withdrawal_abi = starknet.json.parse(
      fs.readFileSync(`../artifacts/abis/withdrawal.json`).toString("ascii")
    );

    let withdrawal_contract = new starknet.Contract(
      withdrawal_abi,
      withdrawal_contract_address,
      account
    );

    if (token_registered) {
      let token_id = await withdrawal_contract.get_token_id_proxy(12345);

      let scale_factor = await withdrawal_contract.get_token_scale_factor_proxy(
        token_id.res
      );
      let address = await withdrawal_contract.get_token_address_proxy(
        token_id.res
      );
      assert.equal(scale_factor.res, 6);
      assert.equal(address.res, 12345);

      console.log("Token id: ", token_id.res.toString());
      console.log("Token scale_factor: ", scale_factor.res.toString());
      console.log("Token address: ", address.res.toString());

      return;
    }

    const { transaction_hash } = await withdrawal_contract.register_token_proxy(
      12345,
      6
    );

    console.log(transaction_hash);

    await account.waitForTransaction(transaction_hash);

    console.log("Token registered successfully");
  });

  it("should make withdrawal updates", async function () {
    let withdrawal_abi = starknet.json.parse(
      fs.readFileSync(`../artifacts/abis/withdrawal.json`).toString("ascii")
    );

    let withdrawal_contract = new starknet.Contract(
      withdrawal_abi,
      withdrawal_contract_address,
      account
    );

    if (withdrawal_updates_made) {
      const res = await withdrawal_contract.get_withdrawable_amount(
        account.address,
        12345
      );

      console.log("res: ", res);

      return;
    }

    let withdrawal_updates = [
      {
        batched_withdraw_info: "340282366920938463481821351505497763072",
        withdraw_address:
          "2325812664550263468000998649484612106203340046325053037275531176882642416349",
      },
      {
        batched_withdraw_info: "340282366920938463481821351505497763072",
        withdraw_address:
          "2325812664550263468000998649484612106203340046325053037275531176882642416349",
      },
      {
        batched_withdraw_info: "340282366920938463481821351505497763072",
        withdraw_address:
          "2325812664550263468000998649484612106203340046325053037275531176882642416349",
      },
    ];

    const { transaction_hash } =
      await withdrawal_contract.store_new_batch_withdrawal_outputs(
        withdrawal_updates
      );

    console.log(transaction_hash);

    await account.waitForTransaction(transaction_hash);

    console.log("withdrawal updates made successfully");
  });
});
