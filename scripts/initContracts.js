const { ethers } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

async function initContracts(
  invisibleAddress,
  escapeVerifierAddress,
  structHasherAddress,
  messageRelayAddress,
  usdcAddress,
  wbtcAddress,
  isL1
) {
  const [signer] = await ethers.getSigners();

  const invisibleL1Abi = isL1
    ? require("../artifacts/src/Invisible.sol/Invisible.json").abi
    : require("../artifacts/src/InvisibleL2.sol/InvisibleL2.json").abi;
  const invisibleContract = new ethers.Contract(
    invisibleAddress,
    invisibleL1Abi,
    signer ?? undefined
  );

  let receipt;
  if (isL1) {
    const escapeVerifierAbi =
      require("../artifacts/src/core/L1/EscapeVerifier.sol/EscapeVerifier.json").abi;
    const escapeVerifierContract = new ethers.Contract(
      escapeVerifierAddress,
      escapeVerifierAbi,
      signer ?? undefined
    );

    let txRes = await invisibleContract.setEscapeVerifier(
      escapeVerifierAddress
    );
    receipt = await txRes.wait();
    console.log("Escape verifier set in invisible Contract");

    txRes = await escapeVerifierContract.setInvisibleAddress(invisibleAddress);
    receipt = await txRes.wait();
    console.log("Invisible address set in Escape verifier Contract");

    txRes = await escapeVerifierContract.setStructHasher(structHasherAddress);
    receipt = await txRes.wait();
    console.log("Struct Hasher set in Escape verifier Contract");
  }

  txRes = await invisibleContract.registerToken(wbtcAddress, 3592681469, 8);
  receipt = await txRes.wait();
  txRes = await invisibleContract.registerToken(usdcAddress, 2413654107, 6);
  receipt = await txRes.wait();
  console.log("Registered WBTC and USDC in invisible contract");

  txRes = await invisibleContract.setClAggregators(
    [wbtcAddress, "0x0000000000000000000000000000000000000000"],
    [
      "0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43",
      "0x694AA1769357215DE4FAC081bf1f309aDC325306",
    ]
  );
  receipt = await txRes.wait();
  console.log(
    "Set Chainlink aggregators for WBTC and ETH in invisible contract"
  );

  txRes = await invisibleContract.setMessageRelay(messageRelayAddress);
  receipt = await txRes.wait();
  console.log("Set MessageRelay in invisible contract");

  const messageRelayAbi = isL1
    ? require("../artifacts/src/core/L1/L1MessageRelay.sol/L1MessageRelay.json")
        .abi
    : require("../artifacts/src/core/L2/L2MessageRelay.sol/L2MessageRelay.json")
        .abi;
  const messageRelayContract = new ethers.Contract(
    messageRelayAddress,
    messageRelayAbi,
    signer ?? undefined
  );

  txRes = await messageRelayContract.setInvisibleAddress(invisibleAddress);
  receipt = await txRes.wait();
  console.log("Set InvisibleAddress in MessageRelay contract");
}

//  * -------------------------------------------

async function setPeers(messageRelayAddress, destIds, peerAddresses, isL1) {
  const [signer] = await ethers.getSigners();

  const messageRelayAbi = isL1
    ? require("../artifacts/src/core/L1/L1MessageRelay.sol/L1MessageRelay.json")
        .abi
    : require("../artifacts/src/core/L2/L2MessageRelay.sol/L2MessageRelay.json")
        .abi;
  const messageRelayContract = new ethers.Contract(
    messageRelayAddress,
    messageRelayAbi,
    signer ?? undefined
  );

  for (let i = 0; i < destIds.length; i++) {
    let peerAddresss = "0x000000000000000000000000" + peerAddresses[0].slice(2);

    let txRes = await messageRelayContract.setPeer(destIds[i], peerAddresss);
    let receipt = await txRes.wait();
    console.log("Set peerAddress in MessageRelay contract");
  }
}

// * -------------------------------------------

// initContracts(
//   "0xCd086eb074169F629e44e74A6F288E565e439204",
//   "0x3eAa88623F737950E46c820776A8925CC585B63E",
//   "0x8824B3D2099C8B26dd9Eb5cf8e57D4B2F5f42EA8",
//   "0x7A37e98441d3c45204c281A7a1cEBAdd39A307Ec",
//   "0xFa255d4aa3Aa5d3a26DF650a158835b77877767a",
//   "0x09Cbeb94e37b5132ad934bc0b55746349B90fEb3",
//   true
// ).catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });
setPeers(
  "0x7A37e98441d3c45204c281A7a1cEBAdd39A307Ec",
  [40231],
  ["0x33C240077CE294Ea37c2439b5b2db53d8A7a16fB"],
  true
).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

// initContracts(
//   "0x46dac0E2F096A496BCADCf3738d28EA540BE9744",
//   "",
//   "",
//   "0x33C240077CE294Ea37c2439b5b2db53d8A7a16fB",
//   "0x2864e0B08dDF0e64FF7c7E8376A5170a8E325651",
//   "0x27D6834e8D35CdAB5991b66ef1550326f1018F62",
//   false
// ).catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });
// setPeers(
//   "0x33C240077CE294Ea37c2439b5b2db53d8A7a16fB",
//   [40161],
//   ["0x7A37e98441d3c45204c281A7a1cEBAdd39A307Ec"],
//   false
// ).catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });
