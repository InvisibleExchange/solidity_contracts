const { ethers, upgrades } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

async function UpgradeInvisible(proxyAddress, isL1) {
  const [signer] = await ethers.getSigners();

  const invisibleV2 = await ethers.getContractFactory(
    isL1 ? "InvisibleL1" : "InvisibleL2"
  );

  const upgraded = await upgrades.upgradeProxy(proxyAddress, invisibleV2, {
    kind: "uups",
    // call: { fn: "initialize", args: [signer.address, chainId] },
    gasLimit: 750000,
  });

  let Invisible = await upgraded.waitForDeployment();

  console.log(`Deployed InvisibleV2 to ${await Invisible.getAddress()}`);
}

async function upgradeEscapeVerifier() {
  const [signer] = await ethers.getSigners();

  const proxyAddress = "0x0931c3d86512aE7A38Ab870052657981bed5e01d";
  const escapeVerifier = await ethers.getContractFactory("EscapeVerifier");

  const upgraded = await upgrades.upgradeProxy(proxyAddress, escapeVerifier, {
    kind: "uups",
    // call: { fn: "initialize", args: [signer.address] },
    gasLimit: 750000,
  });

  let EscapeVerifier = await upgraded.waitForDeployment();

  console.log(`Deployed EscapeVerifier to ${EscapeVerifier.address}`);
}

UpgradeInvisible("0x8Be87E71c3b5BA0CC9B5e8Ab17dC932fD0c91fF3", true).catch(
  (error) => {
    console.error(error);
    process.exitCode = 1;
  }
);

// upgradeEscapeVerifier().catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });
