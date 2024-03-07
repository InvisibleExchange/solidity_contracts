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

let invisibleAddress = "0x582DAF4368f88281b6FE7a315Ef50323693C39AF";
transitionBatch(invisibleAddress).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

// let depositRequests = getDepositOutputs();
// let withdrawalRequests = getWithdrawalOutputs();
// let invisibleAddress = "0xf077225097090fB566BC5d32995a29808035E156";
// let txBatchId = 5;
// processL2Interactions(
//   invisibleAddress,
//   txBatchId,
//   depositRequests,
//   withdrawalRequests
// ).catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });

function getProgramOutput() {
  return [
    2413538521893157956869522357006235860322019039808149590262438952731562665373n,
    778643507763365307684435980607034917737400029513894349099445580984279878135n,
    597639461079105929219n,
    20461022922632640854851594911582879962958103838720n,
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
    529772439197085255804942518291485531350899438878394109743661553264768126565n,
    0n,
    13666080137912171067862238953387600902972672n,
    1669987464367741806901581703315727722326801619559351826421346426798401265671n,
    13666080137912408752349781746400381084823680n,
    1669987464367741806901581703315727722326801619559351826421346426798401265671n,
    13666080137912668186053327254319357781991680n,
    95386976468426923783346594028622962171518585924647255192876045839129024801n,
    13666080137912905870540870047332138413842688n,
    95386976468426923783346594028622962171518585924647255192876045839129024801n,
    13666080137912985098703384311669731957793024n,
    95386976468426923783346594028622962171518585924647255192876045839129024801n,
    13666080137913042577649895861101129387426368n,
    1669987464367741806901581703315727722326801619559351826421346426798401265671n,
    2080056632011220430802714481244435741834961858455520233203053625351682007237n,
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
