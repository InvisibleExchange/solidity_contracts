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
    : require("../artifacts/src/Invisible.sol/InvisibleL2.json").abi;
  const invisibleContract = new ethers.Contract(
    invisibleAddress,
    invisibleL1Abi,
    signer ?? undefined
  );

  let receipt;
  if (isL1) {
    const escapeVerifierAbi =
      require("../artifacts/src/core/EscapeVerifier.sol/EscapeVerifier.json").abi;
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

  // txRes = await invisibleContract.registerToken(wbtcAddress, 3592681469, 8);
  // receipt = await txRes.wait();
  // txRes = await invisibleContract.registerToken(usdcAddress, 2413654107, 6);
  // receipt = await txRes.wait();
  // console.log("Registered WBTC and USDC in invisible contract");

  // txRes = await invisibleContract.setClAggregators(
  //   [wbtcAddress, "0x0000000000000000000000000000000000000000"],
  //   [
  //     "0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43",
  //     "0x694AA1769357215DE4FAC081bf1f309aDC325306",
  //   ]
  // );
  // receipt = await txRes.wait();
  // console.log(
  //   "Set Chainlink aggregators for WBTC and ETH in invisible contract"
  // );

  txRes = await invisibleContract.setMessageRelay(messageRelayAddress);
  receipt = await txRes.wait();
  console.log("Set MessageRelay in invisible contract");

  const messageRelayAbi = isL1
    ? require("../artifacts/src/core/MessageRelay.sol/L1MessageRelay.json").abi
    : require("../artifacts/src/core/MessageRelay.sol/L2MessageRelay.json").abi;
  const messageRelayContract = new ethers.Contract(
    messageRelayAddress,
    messageRelayAbi,
    signer ?? undefined
  );

  txRes = await messageRelayContract.setInvisibleAddress(invisibleAddress);
  receipt = await txRes.wait();
  console.log("Set MessageRelay in invisible contract");
}

initContracts(
  "0x4bd6A7Fd7de59E5b0A0c6fA9DDD93508A548158a",
  "0xf2c1E1D6cA9c35D1686f29f082927748520c7F63",
  "0xB54b9D3c5e274b577AD4fba497779F6253F1bc89",
  "0x65cAD7503C36FbB9eda10877c113311c2d732D82",
  "0xFa255d4aa3Aa5d3a26DF650a158835b77877767a",
  "0x09Cbeb94e37b5132ad934bc0b55746349B90fEb3",
  true
).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

// initContracts(
//   "0x72D3D0F9f9A9F8ca748Fbed1Fd7A8A1b17a943e4",
//   "",
//   "",
//   "0x990248Cbae36334a576BD3Db2aA9bfFC6AA1AdC3",
//   "0x2864e0B08dDF0e64FF7c7E8376A5170a8E325651",
//   "0x27D6834e8D35CdAB5991b66ef1550326f1018F62",
//   false
// ).catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });

// * ETH SEPOLIA
// * Deployed Invisible to 0x4bd6A7Fd7de59E5b0A0c6fA9DDD93508A548158a
// * Deployed StructHasher to 0xB54b9D3c5e274b577AD4fba497779F6253F1bc89 and EscapeVerifier to 0xf2c1E1D6cA9c35D1686f29f082927748520c7F63
// * Deployed TestUsdc to 0xFa255d4aa3Aa5d3a26DF650a158835b77877767a and TestWbtc to 0x09Cbeb94e37b5132ad934bc0b55746349B90fEb3
// * Deployed MessageRelay to 0x65cAD7503C36FbB9eda10877c113311c2d732D82

// ! ARBITRUM SEPOLIA
// ! Deployed InvisibleL2 to 0x72D3D0F9f9A9F8ca748Fbed1Fd7A8A1b17a943e4
// ! Deployed TestUsdc to 0x2864e0B08dDF0e64FF7c7E8376A5170a8E325651 and TestWbtc to 0x27D6834e8D35CdAB5991b66ef1550326f1018F62
// ! Deployed MessageRelay to 0x990248Cbae36334a576BD3Db2aA9bfFC6AA1AdC3
