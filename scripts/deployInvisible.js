const { upgrades, ethers } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const invisible = await ethers.getContractFactory("Invisible");

  const instance = await upgrades.deployProxy(invisible, [deployer.address], {
    kind: "uups",
  });

  let Invisible = await instance.waitForDeployment();

  console.log(`Deployed Invisible to ${await Invisible.getAddress()}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

// * Deployed Invisible to 0x557d570c97E92b4A2C7fdfaE4DDCb9EF931d33C2
// & Deployed StructHasher to 0xb19f3ADF9185C8b9122f4843a87bC51EE4FA15a2 and EscapeVerifier to 0x485caa427D245458D71674129A2340bDB69d8651
