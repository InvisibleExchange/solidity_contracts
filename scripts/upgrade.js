const { ethers, upgrades } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

async function UpgradeInvisible() {
  const [signer] = await ethers.getSigners();

  const proxyAddress = "0x951bBd501d9CaF6E75CD9566f8eC40eF0860B10d";
  const invisibleV2 = await ethers.getContractFactory("InvisibleV2");

  const upgraded = await upgrades.upgradeProxy(proxyAddress, invisibleV2, {
    kind: "uups",
    // call: { fn: "initialize", args: [signer.address] },
    gasLimit: 750000,
  });

  let Invisible = await upgraded.waitForDeployment();

  console.log(`Deployed InvisibleV2 to ${invisibleV2.address}`);
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

// UpgradeInvisible().catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });

upgradeEscapeVerifier().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

// * Deployed Invisible to 0x951bBd501d9CaF6E75CD9566f8eC40eF0860B10d
// & Deployed StructHasher to 0x417406f2775035131468a9841d3b8b0FED2F6455 and EscapeVerifier to 0x0931c3d86512aE7A38Ab870052657981bed5e01d
// ? Deployed TestUsdc to 0xa0eb40164C5d64fa4B5b466F677d3ef70c79c5c1 and TestWbtc to 0x71a46b7F3F971982304E48342C78B5460d8047d6
