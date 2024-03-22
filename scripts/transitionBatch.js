const { ethers } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

async function transitionBatch(invisibleAddress) {
  const [signer] = await ethers.getSigners();

  const invisibleL1Abi =
    require("../artifacts/src/Invisible.sol/InvisibleL1.json").abi;
  const invisibleContract = new ethers.Contract(
    invisibleAddress,
    invisibleL1Abi,
    signer ?? undefined
  );

  let programOutput = getProgramOutput(); //.map((x) => BigNumber.from(x));

  let gasFeeData = await signer.provider.getFeeData();
  let overrides = {
    gasLimit: 3_000_000,
    maxFeePerGas: gasFeeData.maxFeePerGas,
    maxPriorityFeePerGas: gasFeeData.maxPriorityFeePerGas,
  };

  // console.log("programOutput: ", programOutput);
  // console.log("overrides: ", overrides);

  let txRes = await invisibleContract
    .updateStateAfterTxBatch(programOutput, overrides)
    .catch((err) => {
      console.log("Error: ", err);
    });
  console.log("tx hash: ", txRes.hash);
  let receipt = await txRes.wait();
  console.log("Successfully updated state after tx batch: ", txRes.hash);

  console.log(
    "events: ",
    receipt.logs.map((log) => log.args)
  );
}

// * -----------------------------------

async function processL2Interactions(
  invisibleAddress,
  txBatchId,
  depositRequests,
  withdrawalRequests
) {
  const [signer] = await ethers.getSigners();

  const invisibleL2Abi =
    require("../artifacts/src/InvisibleL2.sol/InvisibleL2.json").abi;
  const invisibleContract = new ethers.Contract(
    invisibleAddress,
    invisibleL2Abi,
    signer ?? undefined
  );

  let gasFeeData = await signer.provider.getFeeData();
  let overrides = {
    // gasLimit: 3_000_000,
    maxFeePerGas: gasFeeData.maxFeePerGas,
    maxPriorityFeePerGas: gasFeeData.maxPriorityFeePerGas,
  };

  // * PROCESS DEPOSITS ------------------------
  let txRes = await invisibleContract
    .processDepositHashes(txBatchId, depositRequests, overrides)
    .catch((err) => {
      console.log("Error: ", err);
    });
  console.log("tx hash: ", txRes.hash);
  let receipt = await txRes.wait();

  console.log("events: ", receipt.logs);
  console.log("Successfully processed deposits: ", txRes.hash);

  // * PROCESS WITHDRAWALS ------------------------
  txRes = await invisibleContract
    .processWithdrawals(txBatchId, withdrawalRequests, overrides)
    .catch((err) => {
      console.log("Error: ", err);
    });
  console.log("\n\n\ntx hash: ", txRes.hash);
  receipt = await txRes.wait();

  console.log("events: ", receipt.logs);
  console.log("Successfully processed withdrawals: ", txRes.hash);
}

// let invisibleAddress = "0x8Be87E71c3b5BA0CC9B5e8Ab17dC932fD0c91fF3";
// transitionBatch(invisibleAddress).catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });

let depositRequests = getDepositOutputs();
let withdrawalRequests = getWithdrawalOutputs();
let invisibleAddress = "0xA912B172057d8ADa029797623a08762e672c3e59";
let txBatchId = 2;
processL2Interactions(
  invisibleAddress,
  txBatchId,
  depositRequests,
  withdrawalRequests
).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

function getProgramOutput() {
  return [
    1424282847675403853891778325140865766203459334120803277123052462426312928040n,
    3268283864858994822319352167845407110313247692668908572298056243880237316892n,
    597645022885660590082n,
    2923003274661805836407369665506353015606703292416n,
    210258926710712570525957419222609112870661182717954n,
    3592681469n,
    453755560n,
    2413654107n,
    277158171n,
    3592681469n,
    453755560n,
    277158171n,
    8n,
    8n,
    6n,
    8n,
    250n,
    2500n,
    50000n,
    250000n,
    6n,
    6n,
    6n,
    5000000n,
    50000000n,
    350000000n,
    150000n,
    3000000n,
    1500000n,
    15000000n,
    100000000n,
    1000000000n,
    40161n,
    40231n,
    874739451078007766457464989774322083649278607533249481151382481072868806602n,
    3324833730090626974525872402899302150520188025637965566623476530814354734325n,
    1839793652349538280924927302501143912227271479439798783640887258675143576352n,
    296568192680735721663075531306405401515803196637037431012739700151231900092n,
    40231n,
    0n,
    2002474717375015991827612157684337449789776657299137496958314552559875156452n,
    3181948508010967063970497891648000n,
    987253332575707135225395624901186832535835507542n,
    3181926758794964349064301926331008n,
    987253332575707135225395624901186832535835507542n,
    3181926758794964349064301726331008n,
    987253332575707135225395624901186832535835507542n,
    3181926758794964349064301681331008n,
    987253332575707135225395624901186832535835507542n,
    2061100011568747340931046359426947377263211157501475597774350300513641254239n,
  ];
}

function getDepositOutputs() {
  let depositRequests = [];

  return depositRequests;
}

function getWithdrawalOutputs() {
  let withdrawalRequests = [
    {
      chainId: 40231,
      tokenId: 2413654107,
      amount: 50000000,
      recipient: "0xacedf8742edc7d923e1e6462852cce136ee9fb56",
      isAutomatic: false,
    },
  ];

  return withdrawalRequests;
}
