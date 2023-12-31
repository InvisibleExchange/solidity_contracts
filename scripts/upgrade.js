const { ethers, upgrades } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

async function UpgradeInvisible() {
  const [signer] = await ethers.getSigners();

  const proxyAddress = "0x557d570c97E92b4A2C7fdfaE4DDCb9EF931d33C2";
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

  const proxyAddress = "0x485caa427D245458D71674129A2340bDB69d8651";
  const escapeVerifier = await ethers.getContractFactory("EscapeVerifier");

  const upgraded = await upgrades.upgradeProxy(proxyAddress, escapeVerifier, {
    kind: "uups",
    // call: { fn: "initialize", args: [signer.address] },
    gasLimit: 750000,
  });

  let EscapeVerifier = await upgraded.waitForDeployment();

  console.log(`Deployed EscapeVerifier to ${EscapeVerifier.address}`);
}

UpgradeInvisible().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

// upgradeEscapeVerifier().catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });

// * Deployed Invisible to 0x557d570c97E92b4A2C7fdfaE4DDCb9EF931d33C2
// & Deployed StructHasher to 0xb19f3ADF9185C8b9122f4843a87bC51EE4FA15a2 and EscapeVerifier to 0x485caa427D245458D71674129A2340bDB69d8651
// ? Deployed TestUsdc to 0x42Ca0987Fd7D46B985907d376Bb222D1C6281a71 and TestWbtc to 0x72a35ECeE1eb4593E9eb780AA5a5D436AB3b3941
