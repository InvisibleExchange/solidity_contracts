const { ethers } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

async function main() {
  const [signer] = await ethers.getSigners();

  const invisibleAddress = "0x951bBd501d9CaF6E75CD9566f8eC40eF0860B10d";
  const structHasherAddress = "0x417406f2775035131468a9841d3b8b0FED2F6455";
  const escapeVerifierAddress = "0x0931c3d86512aE7A38Ab870052657981bed5e01d";

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

  let usdcAddress = "0xa0eb40164C5d64fa4B5b466F677d3ef70c79c5c1";
  let btcAddress = "0x71a46b7F3F971982304E48342C78B5460d8047d6";

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

// * Deployed Invisible to 0x951bBd501d9CaF6E75CD9566f8eC40eF0860B10d
// & Deployed StructHasher to 0x417406f2775035131468a9841d3b8b0FED2F6455 and EscapeVerifier to 0x0931c3d86512aE7A38Ab870052657981bed5e01d
// ? Deployed TestUsdc to 0xa0eb40164C5d64fa4B5b466F677d3ef70c79c5c1 and TestWbtc to 0x71a46b7F3F971982304E48342C78B5460d8047d6
