const { ethers } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

async function transitionBatch(invisibleAddress) {
  const [signer] = await ethers.getSigners();

  const invisibleL1Abi =
    require("../artifacts/src/Invisible.sol/Invisible.json").abi;
  const invisibleContract = new ethers.Contract(
    invisibleAddress,
    invisibleL1Abi,
    signer ?? undefined
  );

  let programOutput = getProgramOutput(); //.map((x) => BigNumber.from(x));

  let overrides = { gasLimit: 750000 };

  let txRes = await invisibleContract
    .updateStateAfterTxBatch(programOutput, overrides)
    .catch((err) => {
      console.log("Error: ", err);
    });
  console.log("tx hash: ", txRes.hash);
  let receipt = await txRes.wait();

  console.log("receipt: ", receipt);
  console.log("Successfully updated state after tx batch: ", txRes.hash);

  console.log("events: ", receipt.logs);
}

async function relayAccumulatedHashes(relayAddress, txBatchId) {
  const [signer] = await ethers.getSigners();

  const relayAbi =
    require("../artifacts/src/core/L1/L1MessageRelay.sol/L1MessageRelay.json").abi;
  const relayContract = new ethers.Contract(
    relayAddress,
    relayAbi,
    signer ?? undefined
  );

  let gasFeeData = await signer.provider.getFeeData();

  let options = "0x00030100110100000000000000000000000000030d40";
  let destinationIds = [40231];

  for (let i = 0; i < destinationIds.length; i++) {
    let result = await relayContract.estimateMessageFee(
      destinationIds[i],
      txBatchId,
      options
    );
    let messageFee = result[0][0]; // + result[0][0] / 1000n;
    // let messageFee = 50000000000000n;

    console.log("messageFee: ", messageFee);

    let overrides = {
      gasLimit: 500_000,
      // gasPrice: gasFeeData.gasPrice,
      maxFeePerGas: gasFeeData.maxFeePerGas,
      maxPriorityFeePerGas: gasFeeData.maxPriorityFeePerGas,
      value: messageFee,
    };

    let txRes = await relayContract
      .sendAccumulatedHashes(destinationIds[i], txBatchId, options, overrides)
      .catch((err) => {
        console.log("Error: ", err);
      });
    let receipt = await txRes.wait();
    console.log(
      "events: ",
      receipt.logs.map((log) => log.args)
    );
    console.log("\nSuccessfully sent accumulated hashes: ", txRes.hash);
  }
}

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
    gasLimit: 3_000_000,
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

async function relayL2Acknowledgment(relayAddress, txBatchId) {
  const [signer] = await ethers.getSigners();

  const relayAbi =
    require("../artifacts/src/core/L2/L2MessageRelay.sol/L2MessageRelay.json").abi;
  const relayContract = new ethers.Contract(
    relayAddress,
    relayAbi,
    signer ?? undefined
  );

  let gasFeeData = await signer.provider.getFeeData();

  let options = "0x000301001101000000000000000000000000004c4b40";

  let result = await relayContract.estimateAcknowledgmentFee(
    txBatchId,
    options
  );
  let messageFee = result[0];

  console.log("messageFee: ", messageFee);

  let overrides = {
    gasLimit: 1_000_000,
    maxFeePerGas: gasFeeData.maxFeePerGas,
    maxPriorityFeePerGas: gasFeeData.maxPriorityFeePerGas,
    value: messageFee,
  };

  let txRes = await relayContract
    .sendAcknowledgment(txBatchId, options, overrides)
    .catch((err) => {
      console.log("Error: ", err);
    });
  console.log("tx hash: ", txRes);
  let receipt = await txRes.wait();

  console.log(
    "events: ",
    receipt.logs.map((log) => log.args)
  );
  console.log("\nSuccessfully sent accumulated hashes: ", txRes.hash);
}

// transitionBatch("0xCd086eb074169F629e44e74A6F288E565e439204").catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });

// relayAccumulatedHashes("0x7A37e98441d3c45204c281A7a1cEBAdd39A307Ec", 1).catch(
//   (error) => {
//     console.error(error);
//     process.exitCode = 1;
//   }
// );

// let depositRequests = [
//   {
//     depositId: 172790829285376,
//     tokenId: 2413654107,
//     amount: 30000000,
//     starkKey:
//       "1669987464367741806901581703315727722326801619559351826421346426798401265671",
//   },
// ];
// processL2Deposits(
//   "0x46dac0E2F096A496BCADCf3738d28EA540BE9744",
//   1,
//   depositRequests
// ).catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });

relayL2Acknowledgment("0x33C240077CE294Ea37c2439b5b2db53d8A7a16fB", 1).catch(
  (error) => {
    console.error(error);
    process.exitCode = 1;
  }
);

function getProgramOutput() {
  return [
    2450644354998405982022115704618884006901283874365176806194200773707121413423n,
    2308781005156518147215710264135861262766973966466339122345457151024766823175n,
    597633417922681503745n,
    2923003274661805836407370874358385653941039792128n,
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
    2551512883222007111101294975648258367973295612776855703669225340654746306991n,
    0n,
    13666080137911854155212181896037226327171328n,
    1669987464367741806901581703315727722326801619559351826421346426798401265671n,
    2112678174764664975105616342095246236799898327306347996646273750320011999860n,
  ];
}
