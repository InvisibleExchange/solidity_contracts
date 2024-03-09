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

// let invisibleAddress = "0x38a059b0EB6c42234AAAa872424500f3e1E4253F";
// transitionBatch(invisibleAddress).catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });

let depositRequests = getDepositOutputs();
let withdrawalRequests = getWithdrawalOutputs();
let invisibleAddress = "0xb9775eCBce69555fBEE3C5cFB0c0D7c59a6b82e3";
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
    2132616961684971076565772114418786220818472814443497691298505987987571786167n,
    916692353632818141094092754065738969697627650589059088688998936652690781169n,
    597640121284298801154n,
    10230556062806717488988994386229308987279123939328n,
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
    114955376182661222528459590620020015627924498786408205437491963098052443160n,
    1848749649068846898772464803574342175054383802756396370513706250192760409288n,
    13666080137912091839699724689050007859022336n,
    1669987464367741806901581703315727722326801619559351826421346426798401265671n,
    13666080137912192817078241668293796518289664n,
    95386976468426923783346594028622962171518585924647255192876045839129024801n,
    13666080137912250296024753217725194046923008n,
    2642092749689377153080241311842925827947262820199074023775737174772744537106n,
    13666080137912329524187267482062789990873344n,
    2642092749689377153080241311842925827947262820199074023775737174772744537106n,
    3181926758794964349064301926331008n,
    987253332575707135225395624901186832535835507542n,
    1642363199488299864620532354628131733495459515046521176289134923496084204783n,
  ];
}

function getDepositOutputs() {
  let depositRequests = [
    {
      depositId: 172790829285380,
      tokenId: 2413654107,
      amount: 3000000000,
      starkKey:
        "1669987464367741806901581703315727722326801619559351826421346426798401265671",
    },
    {
      depositId: 172790829285381,
      tokenId: 2413654107,
      amount: 100000000,
      starkKey:
        "1669987464367741806901581703315727722326801619559351826421346426798401265671",
    },
    {
      depositId: 172790829285382,
      tokenId: 3592681469,
      amount: 200000000,
      starkKey:
        "95386976468426923783346594028622962171518585924647255192876045839129024801",
    },
    {
      depositId: 172790829285383,
      tokenId: 2413654107,
      amount: 100000000,
      starkKey:
        "1669987464367741806901581703315727722326801619559351826421346426798401265671",
    },
    {
      depositId: 172790829285384,
      tokenId: 2413654107,
      amount: 1000000,
      starkKey:
        "1669987464367741806901581703315727722326801619559351826421346426798401265671",
    },
    {
      depositId: 172790829285385,
      tokenId: 2413654107,
      amount: 1000000,
      starkKey:
        "1669987464367741806901581703315727722326801619559351826421346426798401265671",
    },
    {
      depositId: 172790829285386,
      tokenId: 2413654107,
      amount: 1000000,
      starkKey:
        "1669987464367741806901581703315727722326801619559351826421346426798401265671",
    },
    {
      depositId: 172790829285387,
      tokenId: 3592681469,
      amount: 100000000,
      starkKey:
        "95386976468426923783346594028622962171518585924647255192876045839129024801",
    },
    {
      depositId: 172790829285388,
      tokenId: 3592681469,
      amount: 100000000,
      starkKey:
        "95386976468426923783346594028622962171518585924647255192876045839129024801",
    },
  ];

  return depositRequests;
}

function getWithdrawalOutputs() {
  let withdrawalRequests = [
    {
      chainId: 40231,
      tokenId: 3592681469,
      amount: 200000000,
      recipient: "0xacedf8742edc7d923e1e6462852cce136ee9fb56",
    },
    {
      chainId: 40231,
      tokenId: 2413654107,
      amount: 362600000,
      recipient: "0xacedf8742edc7d923e1e6462852cce136ee9fb56",
    },
  ];

  return withdrawalRequests;
}
