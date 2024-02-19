const { upgrades, ethers } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

async function deployInvisibleL1() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const invisible = await ethers.getContractFactory("Invisible");

  const destId = 40161;
  const instance = await upgrades.deployProxy(
    invisible,
    [deployer.address, destId],
    {
      kind: "uups",
    }
  );

  let Invisible = await instance.waitForDeployment();

  console.log(`Deployed Invisible to ${await Invisible.getAddress()}`);
}

async function deployInvisibleL2(destId) {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const invisible = await ethers.getContractFactory("InvisibleL2");

  const instance = await upgrades.deployProxy(
    invisible,
    [deployer.address, destId],
    {
      kind: "uups",
    }
  );

  let Invisible = await instance.waitForDeployment();

  console.log(`Deployed InvisibleL2 to ${await Invisible.getAddress()}`);
}

// deployInvisibleL1().catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });

let destId = 40231;
deployInvisibleL2(destId).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

// * ETH SEPOLIA
// * Deployed Invisible to 0xE0EA0063D6e7D55C30E0dDF3202B494B4ffFD117
// * Deployed StructHasher to  and EscapeVerifier to
// * Deployed TestUsdc to  and TestWbtc to
// * Deployed MessageRelay to

// ! ARBITRUM SEPOLIA
// ! Deployed InvisibleL2 to
// ! Deployed TestUsdc to  and TestWbtc to
// ! Deployed MessageRelay to
