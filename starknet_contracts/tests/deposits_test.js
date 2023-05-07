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

// const new_priv_key = "8932749863246329746327463249328632";
// const new_pub_key =
//   "2325812664550263468000998649484612106203340046325053037275531176882642416349";

let tokenA_address =
  "0x033b458199a49b174ef79b4216453447add7084c82a3970a13c04569a4a6479e";
let tokenB_address =
  "0x04f1efcc20d0e57fca007e4676daec186817647c6057bd4f1cd3ee4c738b7b4b";

let deposit_contract_address =
  "0x0635b033b6f8d2e2462c5db3a893a69394d064495f73baba63589e11a6a8afed";

//
let tokens_deployed = true;
let deposit_contract_deployed = true;
let token_registered = true;
let deposit_made = false;
let deposit_cancelled = true;
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
const account = new starknet.Account(provider, address, starkKeyPub);

describe("Interaction tests", function () {
  this.timeout(100_000);
  before(async function () {});

  it("should deploy the erc20 tokens A and B", async function () {
    if (tokens_deployed) {
      return;
    }

    let erc20_compiled = starknet.json.parse(
      fs.readFileSync(`../artifacts/ERC20Mintable.json`).toString("ascii")
    );
    let erc20_abi = starknet.json.parse(
      fs.readFileSync(`../artifacts/abis/ERC20Mintable.json`).toString("ascii")
    );

    let factory = new starknet.ContractFactory(
      erc20_compiled,
      provider,
      erc20_abi
    );
    // name: felt, symbol: felt, decimals: felt, initial_supply: Uint256, recipient: felt, owner: felt

    let amountA = bnToUint256(100_000n * 10n ** 18n);
    let tokenA = await factory.deploy(
      [
        hex("Ether"),
        hex("ETH"),
        18,
        amountA.low,
        amountA.high,
        account.address,
        account.address,
      ],
      "0x1111"
    );
    let amountB = bnToUint256(100_000_000n * 10n ** 18n);
    let tokenB = await factory.deploy(
      [
        hex("Dai"),
        hex("DAI"),
        18,
        amountB.low,
        amountB.high,
        account.address,
        account.address,
      ],
      "0x1111"
    );

    console.log("tokenA address: ", tokenA.address);
    console.log("tokenB address: ", tokenB.address);

    tokenA_address = tokenA.address;
    tokenB_address = tokenB.address;
  });

  it("should deploy deposit contract", async function () {
    if (deposit_contract_deployed) {
      return;
    }

    let deposits_compiled = starknet.json.parse(
      fs.readFileSync(`../artifacts/deposits.json`).toString("ascii")
    );
    let deposits_abi = starknet.json.parse(
      fs.readFileSync(`../artifacts/abis/deposits.json`).toString("ascii")
    );
    let factory = new starknet.ContractFactory(
      deposits_compiled,
      account,
      deposits_abi
    );
    let deploy_contract = await factory.deploy([], "0x1111");

    deposit_contract_address = deploy_contract.address;

    console.log("contract_address: ", deploy_contract.address);
  });

  it("should register_token", async function () {
    if (token_registered) {
      return;
    }

    let res1 = await account.execute({
      contractAddress: deposit_contract_address,
      entrypoint: "register_token_proxy",
      calldata: [tokenA_address, 6],
    });

    const { transaction_hash } = await account.execute({
      contractAddress: deposit_contract_address,
      entrypoint: "register_token_proxy",
      calldata: [tokenB_address, 6],
    });

    console.log(res1.transaction_hash);
    await account.waitForTransaction(res1.transaction_hash);

    console.log(transaction_hash);
    await account.waitForTransaction(transaction_hash);

    console.log("Token registered successfully");
  });

  it("should make_deposit", async function () {
    if (deposit_made) {
      return;
    }

    let deposits_abi = starknet.json.parse(
      fs.readFileSync(`../artifacts/abis/deposits.json`).toString("ascii")
    );

    let deposit_contract = new starknet.Contract(
      deposits_abi,
      deposit_contract_address,
      account
    );

    let x = bnToUint256(100n * 10n ** 18n);
    let res1_ = await account.execute({
      contractAddress: tokenA_address,
      entrypoint: "approve",
      calldata: [deposit_contract.address, x.low, x.high], // 100 ETH
    });

    await provider.waitForTransaction(res1_.transaction_hash);
    console.log("approved tokens successfully");

    let res1 = await account.execute({
      contractAddress: deposit_contract.address,
      entrypoint: "make_deposit",
      calldata: [tokenA_address, (100n * 10n ** 18n).toString()], // 100 ETH
    });

    await account.waitForTransaction(res1.transaction_hash);

    res1 = await provider.getTransactionReceipt(res1.transaction_hash);

    let event_data1 = res1.events[2].data;

    let deposit_obj1 = {
      deposit_amount: BigInt(event_data1[2], 16),
      deposit_id: 0,
      deposit_token: BigInt(event_data1[1], 16),
      stark_key: BigInt(event_data1[0], 16),
    };

    console.log("deposit_obj1: ", deposit_obj1);

    console.log("Deposit made successfully");
  });

  it("should cancel_deposit", async function () {
    if (deposit_cancelled) {
      return true;
    }

    let deposits_abi = starknet.json.parse(
      fs.readFileSync(`../artifacts/abis/deposits.json`).toString("ascii")
    );

    let deposit_contract = new starknet.Contract(
      deposits_abi,
      deposit_contract_address,
      account
    );

    let res = await deposit_contract.get_pending_deposit_amount(
      account.address,
      12345
    );
    if (res.deposit_amount > 0) {
      console.log("Pending deposit: ", res.deposit_amount.toString());
      return;
    }

    let deposit_amount = 10n ** 15n; // 100 BTC * 10^6 decimals * 10^6 scale_factor
    console.log("deposit_amount: ", deposit_amount.toString());
    const { transaction_hash } = await deposit_contract.make_deposit(
      12345,
      deposit_amount.toString()
      //   {
      //     maxFee: "1",
      //   }
    );

    console.log(transaction_hash);

    await account.waitForTransaction(transaction_hash);
    console.log("Deposit made successfully");
  });
});

//

//
// {let res = await account.callContract({
//     contractAddress: account.address,
//     entrypoint: "get_public_key",
//     calldata: [],
//   });
//   if (res.result == new_pub_key.toString(16)) {
//     await account.execute({
//       contractAddress: account.address,
//       entrypoint: "set_public_key",
//       calldata: [new_pub_key],
//     });
//   }}
//
