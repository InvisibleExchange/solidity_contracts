const { ethers } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

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

// * -----------------------------------

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
    // gasLimit: 1_000_000,
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

let relayAddress = "0x5684Ccd1571749Caf41315b13Eb66F8F9112d5bd";
let txBatchId = 2;
relayAccumulatedHashes(relayAddress, txBatchId).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

// let l2RelayAddress = "0xF19bECd2d9Be4Cb11445DbbB74B57b7D18037a7f";
// let txBatchId = 2;
// relayL2Acknowledgment(l2RelayAddress, txBatchId).catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });
