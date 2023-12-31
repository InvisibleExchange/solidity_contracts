const { upgrades, ethers } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

async function main() {
  const [deployer] = await ethers.getSigners();

  const testUsdc = await ethers.deployContract(
    "TestToken",
    ["Invisible USDC", "IUSDC"],
    {
      signer: deployer,
    }
  );
  let TestUsdc = await testUsdc.waitForDeployment();

  const testWbtc = await ethers.deployContract(
    "TestToken",
    ["Invisible WBTC", "IWBTC"],
    {
      signer: deployer,
    }
  );
  let TestWbtc = await testWbtc.waitForDeployment();

  console.log(
    `Deployed TestUsdc to ${await TestUsdc.getAddress()} and TestWbtc to ${await TestWbtc.getAddress()}`
  );
}

async function main2() {
  const [signer] = await ethers.getSigners();

  const testTokenAbi =
    require("../artifacts/src/TestToken.sol/TestToken.json").abi;

  let usdcAddress = "0x42Ca0987Fd7D46B985907d376Bb222D1C6281a71";
  let btcAddress = "0x72a35ECeE1eb4593E9eb780AA5a5D436AB3b3941";

  const usdcContract = new ethers.Contract(
    usdcAddress,
    testTokenAbi,
    signer ?? undefined
  );
  const btcContract = new ethers.Contract(
    btcAddress,
    testTokenAbi,
    signer ?? undefined
  );

  let accounts = [
    "0xaCEdF8742eDC7d923e1e6462852cCE136ee9Fb56",
    "0x2b2eA7eC7e366666772DaAf496817c14b8c0Ae74",
    "0x26BD962c29195832F61Af94f438444A6B7212Ab8",
    "0xcca319f79859761Cb2248Af392cB015967063369",
  ];
  for (let i = 0; i < accounts.length; i++) {
    let txRes = await usdcContract.mint(
      accounts[i],
      ethers.parseEther("100000")
    );
    let receipt = await txRes.wait();
    let txRes2 = await btcContract.mint(accounts[i], ethers.parseEther("100"));
    let receipt2 = await txRes2.wait();
    console.log(`Minted 10,000 TestUsdc and 100 TestWbtc to ${accounts[i]}`);
  }
}

// main().catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });
main2().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

// * Deployed Invisible to 0x557d570c97E92b4A2C7fdfaE4DDCb9EF931d33C2
// & Deployed StructHasher to 0xb19f3ADF9185C8b9122f4843a87bC51EE4FA15a2 and EscapeVerifier to 0x485caa427D245458D71674129A2340bDB69d8651
// ? Deployed TestUsdc to 0x42Ca0987Fd7D46B985907d376Bb222D1C6281a71 and TestWbtc to 0x72a35ECeE1eb4593E9eb780AA5a5D436AB3b3941
