const { ethers, upgrades } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

async function main() {
  const [signer] = await ethers.getSigners();

  const proxyAddress = "0x9ECC2Ccc13Bf31790aaa88A985D3d24A5000d01a";
  const invisibleV2 = await ethers.getContractFactory("InvisibleV2");

  const upgraded = await upgrades.upgradeProxy(proxyAddress, invisibleV2, {
    kind: "uups",
    // call: { fn: "initialize", args: [signer.address] },
    gasLimit: 750000,
  });

  let Invisible = await upgraded.waitForDeployment();

  console.log(`Deployed InvisibleV2 to ${invisibleV2.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
