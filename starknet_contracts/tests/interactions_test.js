const { expect, assert } = require("chai");

const fs = require("fs");
const starknet = require("starknet");
const BigNumber = require("bignumber.js");
const Bigint = require("big-integer");
const hex = require("string-hex");
const { bnToUint256 } = require("starknet/dist/utils/uint256");

const program_output = JSON.parse(
  fs.readFileSync("program_output.json", "utf-8"),
  (key, value) => {
    return typeof value === "string"
      ? Bigint(value).isNegative()
        ? Bigint(starknet.ec.ec.curve.p.toString())
            .add(BigInt(value))
            .value.toString()
        : value
      : value;
  }
);

// accounts
const priv_keys = [
  "0xcd613e30d8f16adf91b7584a2265b1f5",
  "0x1e2feb89414c343c1027c4d1c386bbc4",
  "0x78e510617311d8a3c2ce6f447ed4d57b",
  "0x35bf992dc9e9c616612e7696a6cecc1b",
];
const addresses = [
  "0x7d2f37b75a5e779f7da01c22acee1b66c39e8ba470ee5448f05e1462afcedb4",
  "0x433732229ce8222824e40d3b13db581634918fba9e8e733eee866b8a7d29ab4",
  "0x3fc938163a76e0ed09ff6ef3364fb3f01f6aff6bbd8620d1466a3b3d3104c68",
  "0x6c78b4a63bdba556902114f35c453d6927b4958db3dd48ac158f45f89638a5b",
];

let interactions_contract_address =
  "0x0715409612e613ddfeca234295b774e832e142e78c78503aaf2a1ad59fd32c32";

let tokenA_address =
  "0x033b458199a49b174ef79b4216453447add7084c82a3970a13c04569a4a6479e";
let tokenB_address =
  "0x069374d81f10116263ff7ef4652f9476db9d62c247321e9bf23c59dc4703b865";

//
let token_contracts_deployed = !false;
let interactions_contract_deployed = !false;
let deposits_made = !false;
let batch_updates_made = !false;
let withdrawal_updates_made = !false;
let withdrawals_made = false;
//

const provider = new starknet.Provider({
  sequencer: {
    baseUrl: "http://127.0.0.1:5050/",
    feederGatewayUrl: "feeder_gateway",
    gatewayUrl: "gateway",
    // chainId: "0x3f44ea7b21c57b7e",
  },
});

const keyPairs = priv_keys.map((priv_key) => starknet.ec.getKeyPair(priv_key));

let accounts = [];
for (let i = 0; i < keyPairs.length; i++) {
  const account = new starknet.Account(provider, addresses[i], keyPairs[i]);
  accounts.push(account);
}

describe("Interaction tests", function () {
  this.timeout(200_000);
  before(async function () {});

  it("should deploy the erc20 tokens A and B", async function () {
    if (token_contracts_deployed) {
      return;
    }

    let erc20_compiled = starknet.json.parse(
      fs.readFileSync(`../artifacts/ERC20Mintable.json`).toString("ascii")
    );
    let erc20_abi = starknet.json.parse(
      fs.readFileSync(`../artifacts/abis/interactions.json`).toString("ascii")
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
        accounts[0].address,
        accounts[0].address,
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
        accounts[1].address,
        accounts[1].address,
      ],
      "0x1111"
    );

    console.log("tokenA address: ", tokenA.address);
    console.log("tokenB address: ", tokenB.address);

    tokenA_address = tokenA.address;
    tokenB_address = tokenB.address;
  });

  it("should deploy interactions contract and register tokens", async function () {
    if (interactions_contract_deployed) {
      return;
    }

    let interactions_compiled = starknet.json.parse(
      fs.readFileSync(`../artifacts/interactions.json`).toString("ascii")
    );
    let interactions_abi = starknet.json.parse(
      fs.readFileSync(`../artifacts/abis/interactions.json`).toString("ascii")
    );
    let factory = new starknet.ContractFactory(
      interactions_compiled,
      provider,
      interactions_abi
    );
    let interactions_contract = await factory.deploy();

    interactions_contract_address = interactions_contract.address;
    console.log("interactions_contract: ", interactions_contract.address);

    let res1 = await accounts[0].execute({
      contractAddress: interactions_contract.address,
      entrypoint: "register_token_proxy",
      calldata: [tokenA_address, 6],
    });

    const { transaction_hash } = await accounts[0].execute({
      contractAddress: interactions_contract.address,
      entrypoint: "register_token_proxy",
      calldata: [tokenB_address, 6],
    });

    console.log(res1.transaction_hash);
    await accounts[0].waitForTransaction(res1.transaction_hash);

    console.log(transaction_hash);
    await accounts[0].waitForTransaction(transaction_hash);
  });

  it("should make deposits", async function () {
    if (deposits_made) {
      return;
    }

    let erc20_abi = starknet.json.parse(
      fs.readFileSync(`../artifacts/abis/ERC20Mintable.json`).toString("ascii")
    );
    let tokenA_contract = new starknet.Contract(
      erc20_abi,
      tokenA_address,
      accounts[0]
    );
    let tokenB_contract = new starknet.Contract(
      erc20_abi,
      tokenB_address,
      accounts[1]
    );

    let interactions_abi = starknet.json.parse(
      fs.readFileSync(`../artifacts/abis/interactions.json`).toString("ascii")
    );

    let interactions_contract = new starknet.Contract(
      interactions_abi,
      interactions_contract_address,
      accounts[0]
    );

    let x = bnToUint256(100n * 10n ** 18n);
    let res1_ = await accounts[0].execute({
      contractAddress: tokenA_address,
      entrypoint: "approve",
      calldata: [interactions_contract_address, x.low, x.high], // 100 ETH
    });

    let y = bnToUint256(10_000n * 10n ** 18n);
    let res2_ = await accounts[1].execute({
      contractAddress: tokenB_address,
      entrypoint: "approve",
      calldata: [interactions_contract_address, y.low, y.high], // 10000 USDC
    });

    await provider.waitForTransaction(res1_.transaction_hash);
    await provider.waitForTransaction(res2_.transaction_hash);

    let res1 = await accounts[0].execute({
      contractAddress: interactions_contract.address,
      entrypoint: "make_deposit_proxy",
      calldata: [tokenA_address, (100n * 10n ** 18n).toString()], // 100 ETH
    });

    let res2 = await accounts[1].execute({
      contractAddress: interactions_contract.address,
      entrypoint: "make_deposit_proxy",
      calldata: [tokenB_address, (10_000n * 10n ** 18n).toString()], // 10000 USDC
    });

    // console.log("tx_hash 1: ", res1.transaction_hash);
    // console.log("tx_hash 2: ", res2.transaction_hash);

    await accounts[0].waitForTransaction(res1.transaction_hash);
    await accounts[0].waitForTransaction(res2.transaction_hash);

    // let after1 = await interactions_contract.get_pending_deposit_amount_proxy(
    //   accounts[0].address,
    //   tokenA_address
    // );

    // let after2 = await interactions_contract.get_pending_deposit_amount_proxy(
    //   accounts[1].address,
    //   tokenB_address
    // );

    res1 = await provider.getTransactionReceipt(res1.transaction_hash);
    res2 = await provider.getTransactionReceipt(res2.transaction_hash);

    let event_data1 = res1.events[2].data;
    let event_data2 = res2.events[2].data;

    let deposit_obj1 = {
      deposit_amount: BigInt(event_data1[2], 16),
      deposit_id: 0,
      deposit_token: BigInt(event_data1[1], 16),
      stark_key: BigInt(event_data1[0], 16),
    };

    let deposit_obj2 = {
      deposit_amount: BigInt(event_data2[2], 16),
      deposit_id: 0,
      deposit_token: BigInt(event_data2[1], 16),
      stark_key: BigInt(event_data2[0], 16),
    };

    write_deposit_to_json_file([deposit_obj1, deposit_obj2]);

    console.log("Deposits made successfully");
  });

  it("should update deposits after tx batch", async function () {
    if (batch_updates_made) {
      return;
    }

    let interactions_abi = starknet.json.parse(
      fs.readFileSync(`../artifacts/abis/interactions.json`).toString("ascii")
    );

    let interactions_contract = new starknet.Contract(
      interactions_abi,
      interactions_contract_address,
      accounts[0]
    );

    let res = await interactions_contract.parse_program_output_proxy(
      program_output
    );

    let pending1 = await interactions_contract.get_pending_deposit_amount_proxy(
      accounts[0].address,
      tokenA_address
    );
    let pending2 = await interactions_contract.get_pending_deposit_amount_proxy(
      accounts[1].address,
      tokenB_address
    );
    console.log("before: ", pending1.deposit_amount.toString());
    console.log("before: ", pending2.deposit_amount.toString());

    let { transaction_hash } =
      await interactions_contract.update_pending_deposits_proxy(res.deposits);

    await accounts[0].waitForTransaction(transaction_hash);

    console.log("tx_hash: ", transaction_hash);

    pending1 = await interactions_contract.get_pending_deposit_amount_proxy(
      accounts[0].address,
      tokenA_address
    );
    pending2 = await interactions_contract.get_pending_deposit_amount_proxy(
      accounts[1].address,
      tokenB_address
    );
    console.log("after: ", pending1.deposit_amount.toString());
    console.log("after: ", pending2.deposit_amount.toString());

    console.log("Deposit updates made successfully");
  });

  it("should update withdrawals after tx batch", async function () {
    let interactions_abi = starknet.json.parse(
      fs.readFileSync(`../artifacts/abis/interactions.json`).toString("ascii")
    );

    let interactions_contract = new starknet.Contract(
      interactions_abi,
      interactions_contract_address,
      accounts[0]
    );

    if (withdrawal_updates_made) {
      // let pending1 = await interactions_contract.get_withdrawable_amount_proxy(
      //   accounts[3].address,
      //   12345
      // );
      // let pending2 = await interactions_contract.get_withdrawable_amount_proxy(
      //   accounts[2].address,
      //   54321
      // );
      // console.log("after: ", pending1.withdraw_amount_scaled.toString());
      // console.log("after: ", pending2.withdraw_amount_scaled.toString());
      return;
    }

    let res = await interactions_contract.parse_program_output_proxy(
      program_output
    );

    let pending1 = await interactions_contract.get_withdrawable_amount_proxy(
      accounts[3].address,
      tokenA_address
    );
    let pending2 = await interactions_contract.get_withdrawable_amount_proxy(
      accounts[2].address,
      tokenB_address
    );
    console.log(
      "withdrawable amount before: ",
      pending1.withdraw_amount_scaled.toString()
    );
    console.log(
      "withdrawable amount before: ",
      pending2.withdraw_amount_scaled.toString()
    );

    let { transaction_hash } =
      await interactions_contract.store_new_batch_withdrawal_outputs_proxy(
        res.withdrawals
      );

    console.log("tx_hash: ", transaction_hash);
    await accounts[0].waitForTransaction(transaction_hash);

    pending1 = await interactions_contract.get_withdrawable_amount_proxy(
      accounts[3].address,
      tokenA_address
    );
    pending2 = await interactions_contract.get_withdrawable_amount_proxy(
      accounts[2].address,
      tokenB_address
    );
    console.log(
      "withdrawable amount after: ",
      pending1.withdraw_amount_scaled.toString()
    );
    console.log(
      "withdrawable amount after: ",
      pending2.withdraw_amount_scaled.toString()
    );

    console.log("withdrawal updates made successfully");
  });

  it("should withdrawal funds", async function () {
    let interactions_abi = starknet.json.parse(
      fs.readFileSync(`../artifacts/abis/interactions.json`).toString("ascii")
    );

    let interactions_contract = new starknet.Contract(
      interactions_abi,
      interactions_contract_address,
      accounts[0]
    );

    if (withdrawals_made) {
      return;
    }

    let pending1 = await interactions_contract.get_withdrawable_amount_proxy(
      accounts[3].address,
      tokenA_address
    );
    let pending2 = await interactions_contract.get_withdrawable_amount_proxy(
      accounts[2].address,
      tokenB_address
    );
    console.log("before: ", pending1.withdraw_amount_scaled.toString());
    console.log("before: ", pending2.withdraw_amount_scaled.toString());

    let res1 = await accounts[3].execute({
      contractAddress: interactions_contract.address,
      entrypoint: "make_withdrawal_proxy",
      calldata: [tokenA_address], // 100 ETH
    });
    let res2 = await accounts[2].execute({
      contractAddress: interactions_contract.address,
      entrypoint: "make_withdrawal_proxy",
      calldata: [tokenB_address], // 100 ETH
    });

    await provider.waitForTransaction(res1.transaction_hash);
    await provider.waitForTransaction(res2.transaction_hash);

    pending1 = await interactions_contract.get_withdrawable_amount_proxy(
      accounts[3].address,
      tokenA_address
    );
    pending2 = await interactions_contract.get_withdrawable_amount_proxy(
      accounts[2].address,
      tokenB_address
    );
    console.log("after: ", pending1.withdraw_amount_scaled.toString());
    console.log("after: ", pending2.withdraw_amount_scaled.toString());

    console.log("withdrawal updates made successfully");
  });
});

function write_deposit_to_json_file(deposit_objets) {
  let usersjson = fs.readFileSync(
    "../../invisible_backend/tests/deposits.json",
    "utf-8"
  );

  let users = JSON.parse(usersjson);

  for (const obj of deposit_objets) {
    users.push(obj);
  }

  //   usersjson = JSON.stringify(users);

  usersjson = JSON.stringify(users, (key, value) => {
    return typeof value === "bigint" ? value.toString() : value;
  });

  fs.writeFileSync(
    "../../invisible_backend/tests/deposits.json",
    usersjson,
    "utf-8"
  );
}

//
