const { upgrades, ethers } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

async function deployInvisibleL1() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const invisible = await ethers.getContractFactory("InvisibleL1");

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

  let gasInfo = await deployer.provider.getFeeData();

  const instance = await upgrades.deployProxy(
    invisible,
    [deployer.address, destId],
    {
      kind: "uups",
      txOverrides: {
        gasPrice: gasInfo.gasPrice * 2n,
      },
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

//
// * ETH SEPOLIA
// * Deployed Invisible to 0x38a059b0EB6c42234AAAa872424500f3e1E4253F
// * Deployed StructHasher to 0x8824B3D2099C8B26dd9Eb5cf8e57D4B2F5f42EA8 and EscapeVerifier to 0x3eAa88623F737950E46c820776A8925CC585B63E
// * Deployed TestUsdc to 0xFa255d4aa3Aa5d3a26DF650a158835b77877767a and TestWbtc to 0x09Cbeb94e37b5132ad934bc0b55746349B90fEb3
// * Deployed MessageRelay to 0x3846c7Cf4718E080Bd023C58d9EEe640c26ffe56

// ! ARBITRUM SEPOLIA
// ! Deployed InvisibleL2 to 0xb9775eCBce69555fBEE3C5cFB0c0D7c59a6b82e3
// ! Deployed TestUsdc to 0x2864e0B08dDF0e64FF7c7E8376A5170a8E325651 and TestWbtc to 0x27D6834e8D35CdAB5991b66ef1550326f1018F62
// ! Deployed MessageRelay to 0xF22b70448469950EfDFc44126382897CC7877A29
