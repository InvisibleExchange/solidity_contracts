const { upgrades, ethers } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

async function main() {
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

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

// Deploying contracts with the account: 0xaCEdF8742eDC7d923e1e6462852cCE136ee9Fb56
// * Deployed Invisible to 0x9ECC2Ccc13Bf31790aaa88A985D3d24A5000d01a
// & Deployed StructHasher to 0x2b9350c10B6FBf52B1762ea8245d8C6c411Ce36E and EscapeVerifier to 0x241Da4c0CEC65fBef4F94f182BAeCb4757547692
