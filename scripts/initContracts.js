const { ethers } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

async function main() {
  const [signer] = await ethers.getSigners();

  const invisibleAddress = "0x9ECC2Ccc13Bf31790aaa88A985D3d24A5000d01a";
  const structHasherAddress = "0x2b9350c10B6FBf52B1762ea8245d8C6c411Ce36E";
  const escapeVerifierAddress = "0x241Da4c0CEC65fBef4F94f182BAeCb4757547692";

  const invisibleL1Abi =
    require("../artifacts/src/Invisible.sol/Invisible.json").abi;
  const invisibleContract = new ethers.Contract(
    invisibleAddress,
    invisibleL1Abi,
    signer ?? undefined
  );

  const escapeVerifierAbi =
    require("../artifacts/src/core/EscapeVerifier.sol/EscapeVerifier.json").abi;
  const escapeVerifierContract = new ethers.Contract(
    escapeVerifierAddress,
    escapeVerifierAbi,
    signer ?? undefined
  );

  let txRes = await invisibleContract.setEscapeVerifier(escapeVerifierAddress);
  let receipt = await txRes.wait();
  console.log("Escape verifier set in invisible Contract");

  txRes = await escapeVerifierContract.setInvisibleAddress(invisibleAddress);
  receipt = await txRes.wait();
  console.log("Invisible address set in Escape verifier Contract");

  txRes = await escapeVerifierContract.setStructHasher(structHasherAddress);
  receipt = await txRes.wait();
  console.log("Struct Hasher set in Escape verifier Contract");

  let btcAddress = "0xbfc17B4135a6DBf44Cb008ad2aAFB56a29E894D5";
  let usdcAddress = "0x990248Cbae36334a576BD3Db2aA9bfFC6AA1AdC3";

  txRes = await invisibleContract.registerToken(btcAddress, 3592681469, 8);
  receipt = await txRes.wait();
  txRes = await invisibleContract.registerToken(usdcAddress, 2413654107, 6);
  receipt = await txRes.wait();
  console.log("Registered WBTC and USDC in invisible contract");

  txRes = await invisibleContract.setClAggregators(
    [btcAddress, "0x0000000000000000000000000000000000000000"],
    [
      "0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43",
      "0x694AA1769357215DE4FAC081bf1f309aDC325306",
    ]
  );
  console.log(
    "Set Chainlink aggregators for WBTC and ETH in invisible contract"
  );
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
