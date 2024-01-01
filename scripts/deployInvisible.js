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

//* Deployed Invisible to 0x951bBd501d9CaF6E75CD9566f8eC40eF0860B10d
//& Deployed StructHasher to 0x572EC9E81190bA3A8763C890ef9EE26f1b40A36C and EscapeVerifier to 0x0931c3d86512aE7A38Ab870052657981bed5e01d
