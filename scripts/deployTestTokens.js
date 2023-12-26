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

  let usdcAddress = "0x990248Cbae36334a576BD3Db2aA9bfFC6AA1AdC3";
  let btcAddress = "0xbfc17B4135a6DBf44Cb008ad2aAFB56a29E894D5";

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
    "0x124c64eb369f277C78CcfBE41d27EfbBA839e4D9",
    "0x035e7288e36c8e8fA790DE6590371833CE61ee56",
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

// Deploying contracts with the account: 0xaCEdF8742eDC7d923e1e6462852cCE136ee9Fb56
// * Deployed Invisible to 0x9ECC2Ccc13Bf31790aaa88A985D3d24A5000d01a
// & Deployed StructHasher to 0x2b9350c10B6FBf52B1762ea8245d8C6c411Ce36E and EscapeVerifier to 0x241Da4c0CEC65fBef4F94f182BAeCb4757547692
// ? Deployed TestUsdc to 0x990248Cbae36334a576BD3Db2aA9bfFC6AA1AdC3 and TestWbtc to 0xbfc17B4135a6DBf44Cb008ad2aAFB56a29E894D5
