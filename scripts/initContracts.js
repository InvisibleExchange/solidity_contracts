const { ethers } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

async function main() {
  const [signer] = await ethers.getSigners();

  const invisibleAddress = "0x557d570c97E92b4A2C7fdfaE4DDCb9EF931d33C2";
  const structHasherAddress = "0xb19f3ADF9185C8b9122f4843a87bC51EE4FA15a2";
  const escapeVerifierAddress = "0x485caa427D245458D71674129A2340bDB69d8651";

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

  let usdcAddress = "0x42Ca0987Fd7D46B985907d376Bb222D1C6281a71";
  let btcAddress = "0x72a35ECeE1eb4593E9eb780AA5a5D436AB3b3941";

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

// * Deployed Invisible to 0x557d570c97E92b4A2C7fdfaE4DDCb9EF931d33C2
// & Deployed StructHasher to 0xb19f3ADF9185C8b9122f4843a87bC51EE4FA15a2 and EscapeVerifier to 0x485caa427D245458D71674129A2340bDB69d8651
// ? Deployed TestUsdc to 0x42Ca0987Fd7D46B985907d376Bb222D1C6281a71 and TestWbtc to 0x72a35ECeE1eb4593E9eb780AA5a5D436AB3b3941
