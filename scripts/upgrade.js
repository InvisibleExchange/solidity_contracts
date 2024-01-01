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

// * Deployed Invisible to 0x259af6f31f545C606A7E56b9960CF69066b19F91
// & Deployed StructHasher to 0xc57d4F241f5AC60E6BFeA7CCCb75bFcCc3D75B7E and EscapeVerifier to 0xCB5e9CaA6bE7dF23d34961CbF4Ac594F17FAb5c2
// ? Deployed TestUsdc to 0x22dff2e837e3F76CE2f3c193920ADb0A70878305 and TestWbtc to 0xaBC8E433D0308a41f67645cc8dCA56E4467e8Db4
