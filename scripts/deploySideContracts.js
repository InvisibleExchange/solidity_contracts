const { upgrades, ethers } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

async function deploy() {
  const [deployer] = await ethers.getSigners();

  const esacpeVerifier = await ethers.getContractFactory("EscapeVerifier");

  const esacpeVerifierInstance = await upgrades.deployProxy(
    esacpeVerifier,
    [deployer.address],
    {
      kind: "uups",
    }
  );
  let EscapeVerifier = await esacpeVerifierInstance.waitForDeployment();

  const structHasherInstance = await ethers.deployContract(
    "StructHasher",
    deployer
  );
  let StructHasher = await structHasherInstance.waitForDeployment();

  console.log(
    `Deployed StructHasher to ${await StructHasher.getAddress()} and EscapeVerifier to ${await EscapeVerifier.getAddress()}`
  );
}

async function deployMessageRelay(isL1) {
  const [deployer] = await ethers.getSigners();

  let lzEndpoint = "0x6edce65403992e310a62460808c4b910d972f10f";
  const messageRelayInstance = await ethers.deployContract(
    isL1 ? "L1MessageRelay" : "L2MessageRelay",
    [lzEndpoint, deployer.address],
    {
      signer: deployer,
    }
  );
  let MessageRelay = await messageRelayInstance.waitForDeployment();

  console.log(`Deployed MessageRelay to ${await MessageRelay.getAddress()}`);
}

// deploy().catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });
deployMessageRelay(false).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

// * ETH SEPOLIA
// * Deployed Invisible to
// * Deployed StructHasher to  and EscapeVerifier to
// * Deployed TestUsdc to  and TestWbtc to
// * Deployed MessageRelay to

// ! ARBITRUM SEPOLIA
// ! Deployed InvisibleL2 to
// ! Deployed TestUsdc to  and TestWbtc to
// ! Deployed MessageRelay to
