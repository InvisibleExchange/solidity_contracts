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

// Deploying contracts with the account: 0xaCEdF8742eDC7d923e1e6462852cCE136ee9Fb56
// * Deployed Invisible to 0x9ECC2Ccc13Bf31790aaa88A985D3d24A5000d01a
// & Deployed StructHasher to 0x2b9350c10B6FBf52B1762ea8245d8C6c411Ce36E and EscapeVerifier to 0x241Da4c0CEC65fBef4F94f182BAeCb4757547692



