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
    // gasLimit: 3_000_000,
    maxFeePerGas: gasFeeData.maxFeePerGas,
    maxPriorityFeePerGas: gasFeeData.maxPriorityFeePerGas,
  };

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

  // // * PROCESS DEPOSITS ------------------------
  // let txRes = await invisibleContract
  //   .processDepositHashes(txBatchId, depositRequests, overrides)
  //   .catch((err) => {
  //     console.log("Error: ", err);
  //   });
  // console.log("tx hash: ", txRes.hash);
  // let receipt = await txRes.wait();

  // console.log("events: ", receipt.logs);
  // console.log("Successfully processed deposits: ", txRes.hash);

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

// let invisibleAddress = "0xc943D66a01bd28ED9C74e03A920ae56A02d953f8";
// transitionBatch(invisibleAddress).catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });

let depositRequests = getDepositOutputs();
let withdrawalRequests = getWithdrawalOutputs();
let invisibleAddress = "0xfa11c66f7E7C96862c2D0726aD36E372fc720Acb";
let txBatchId = 4;
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
    361774114494094996144832610614300124642270252465375182615864945613907231066n,
    3150140957918637995355800199992463730885955170609476692650525064750517879182n,
    597636100146937724932n,
    4384504911992708754690283869607379755264225837056n,
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
    1877347089213535355875292810045998310643486808027050403136168102678706235972n,
    785551284925916095344101617032869380398524571387710336238935744872183160729n,
    13666080137912487980512296010737975578774016n,
    1669987464367741806901581703315727722326801619559351826421346426798401265671n,
    3181926758794964349064301776331008n,
    987253332575707135225395624901186832535835507542n,
    140649424408447970444639526463658352079186466053097235459433038843084977497n,
  ];
}

function getDepositOutputs() {
  let depositRequests = [
    {
      depositId: 172790829285385,
      tokenId: 2413654107,
      amount: 1000000000,
      starkKey:
        "1669987464367741806901581703315727722326801619559351826421346426798401265671",
    },
  ];

  return depositRequests;
}

function getWithdrawalOutputs() {
  let withdrawalRequests = [
    {
      chainId: 40231,
      tokenId: 2413654107,
      amount: 75000000,
      recipient: "0xacedf8742edc7d923e1e6462852cce136ee9fb56",
    },
  ];

  return withdrawalRequests;
}
