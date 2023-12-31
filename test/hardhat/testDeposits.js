const { ethers } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../../.env") });

async function main() {
  const [signer] = await ethers.getSigners();

  const invisibleAddress = "0x9ECC2Ccc13Bf31790aaa88A985D3d24A5000d01a";

  const invisibleL1Abi =
    require("../../artifacts/src/Invisible.sol/Invisible.json").abi;
  const invisibleContract = new ethers.Contract(
    invisibleAddress,
    invisibleL1Abi,
    signer ?? undefined
  );

  let btcAddress = "0xbfc17B4135a6DBf44Cb008ad2aAFB56a29E894D5";
  let usdcAddress = "0x990248Cbae36334a576BD3Db2aA9bfFC6AA1AdC3";

  let overrides = { gasLimit: 750000 };
  let txRes = await invisibleContract.makeDeposit(
    usdcAddress,
    ethers.parseEther("1"),
    "1234567890",
    overrides
  );
  console.log("Made deposit of 0.01 WBTC: ", txRes.hash);
  let receipt = await txRes.wait();
  console.log("Deposit receipt: ", receipt);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

// Deploying contracts with the account: 0xaCEdF8742eDC7d923e1e6462852cCE136ee9Fb56
// * Deployed Invisible to 0x9ECC2Ccc13Bf31790aaa88A985D3d24A5000d01a
// & Deployed StructHasher to 0x2b9350c10B6FBf52B1762ea8245d8C6c411Ce36E and EscapeVerifier to 0x241Da4c0CEC65fBef4F94f182BAeCb4757547692
// ? Deployed TestUsdc to 0x990248Cbae36334a576BD3Db2aA9bfFC6AA1AdC3 and TestWbtc to 0xbfc17B4135a6DBf44Cb008ad2aAFB56a29E894D5
