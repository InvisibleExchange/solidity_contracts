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
    ? require("../artifacts/src/Invisible.sol/InvisibleL1.json").abi
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

// * L1
let invisibleL1 = "0x38a059b0EB6c42234AAAa872424500f3e1E4253F";
let escapeVerifier = "0x3eAa88623F737950E46c820776A8925CC585B63E";
let structHasher = "0x8824B3D2099C8B26dd9Eb5cf8e57D4B2F5f42EA8";
let l1MessageRelay = "0x3846c7Cf4718E080Bd023C58d9EEe640c26ffe56";
let testUsdc = "0xFa255d4aa3Aa5d3a26DF650a158835b77877767a";
let testWbtc = "0x09Cbeb94e37b5132ad934bc0b55746349B90fEb3";

// * L2
let invisibleL2 = "0xb9775eCBce69555fBEE3C5cFB0c0D7c59a6b82e3";
let l2MessageRelay = "0xF22b70448469950EfDFc44126382897CC7877A29";
let testUsdcL2 = "0x2864e0B08dDF0e64FF7c7E8376A5170a8E325651";
let testWbtcL2 = "0x27D6834e8D35CdAB5991b66ef1550326f1018F62";

// * -------------------------------------------

// initContracts(
//   invisibleL1,
//   escapeVerifier,
//   structHasher,
//   l1MessageRelay,
//   testUsdc,
//   testWbtc,
//   true
// ).catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });

// //
// setPeers(l1MessageRelay, [40231], [l2MessageRelay], true).catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });

// * -------------------------------------------

// initContracts(
//   invisibleL2,
//   "",
//   "",
//   l2MessageRelay,
//   testUsdcL2,
//   testWbtcL2,
//   false
// ).catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });

// setPeers(l2MessageRelay, [40161], [l1MessageRelay], false).catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });
