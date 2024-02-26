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

  let overrides = {};

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

async function processL2Deposits(invisibleAddress, txBatchId, depositRequests) {
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

  let txRes = await invisibleContract
    .processDepositHashes(txBatchId, depositRequests, overrides)
    .catch((err) => {
      console.log("Error: ", err);
    });
  console.log("tx hash: ", txRes.hash);
  let receipt = await txRes.wait();

  console.log("events: ", receipt.logs);
  console.log("Successfully updated state after tx batch: ", txRes.hash);
}

let invisibleAddress = "0xc943D66a01bd28ED9C74e03A920ae56A02d953f8";
transitionBatch(invisibleAddress).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

// let depositRequests = getDepositOutputs();
// let invisibleAddress = "0xfa11c66f7E7C96862c2D0726aD36E372fc720Acb";
// let txBatchId = 2;
// processL2Deposits(invisibleAddress, txBatchId, depositRequests).catch(
//   (error) => {
//     console.error(error);
//     process.exitCode = 1;
//   }
// );

function getProgramOutput() {
  return [
    3122045166344712876436189192695646099784305822139485620570275293141030450110n,
    361774114494094996144832610614300124642270252465375182615864945613907231066n,
    597635766440863727619n,
    11692013098647223345629483497433542615764159168512n,
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
    2167060119205161429725692703140577688734624460848985836807740885084600866713n,
    0n,
    13666080137912192817078241668293796768289664n,
    95386976468426923783346594028622962171518585924647255192876045839129024801n,
    13666080137912250296024753217725194446923008n,
    1669987464367741806901581703315727722326801619559351826421346426798401265671n,
    13666080137912329524187267482062787940873344n,
    1669987464367741806901581703315727722326801619559351826421346426798401265671n,
    13666080137912408752349781746400381534823680n,
    1669987464367741806901581703315727722326801619559351826421346426798401265671n,
    47451617529847155513430293294260239361188648922702283848823476362958144311n,
  ];
}

function getDepositOutputs() {
  let depositRequests = [
    {
      depositId: 172790829285378,
      tokenId: 2413654107,
      amount: 1200000000,
      starkKey:
        "1669987464367741806901581703315727722326801619559351826421346426798401265671",
    },
    {
      depositId: 172790829285379,
      tokenId: 2413654107,
      amount: 200000000,
      starkKey:
        "1669987464367741806901581703315727722326801619559351826421346426798401265671",
    },
    {
      depositId: 172790829285380,
      tokenId: 3592681469,
      amount: 200000000,
      starkKey:
        "95386976468426923783346594028622962171518585924647255192876045839129024801",
    },
  ];

  return depositRequests;
}
