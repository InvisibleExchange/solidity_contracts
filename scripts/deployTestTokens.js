const { upgrades, ethers } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

async function deployTestTokens() {
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

async function mintTestTokens(usdcAddress, wbtcAddress) {
  const [signer] = await ethers.getSigners();

  const testTokenAbi =
    require("../artifacts/src/TestToken.sol/TestToken.json").abi;

  const usdcContract = new ethers.Contract(
    usdcAddress,
    testTokenAbi,
    signer ?? undefined
  );
  const btcContract = new ethers.Contract(
    wbtcAddress,
    testTokenAbi,
    signer ?? undefined
  );

  let accounts = [
    "0xaCEdF8742eDC7d923e1e6462852cCE136ee9Fb56",
    "0x2b2eA7eC7e366666772DaAf496817c14b8c0Ae74",
    "0x26BD962c29195832F61Af94f438444A6B7212Ab8",
    // "0xcca319f79859761Cb2248Af392cB015967063369",
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

async function main() {
  let l1Usdc = "0xFa255d4aa3Aa5d3a26DF650a158835b77877767a";
  let l1Wbtc = "0x09Cbeb94e37b5132ad934bc0b55746349B90fEb3";

  let l2Usdc = "0x2864e0B08dDF0e64FF7c7E8376A5170a8E325651";
  let l2Wbtc = "0x27D6834e8D35CdAB5991b66ef1550326f1018F62";

  // await deployTestTokens().catch((error) => {
  //   console.error(error);
  //   process.exitCode = 1;
  // });

  await mintTestTokens(l2Usdc, l2Wbtc).catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
main();

// * ETH SEPOLIA
// * Deployed TestUsdc to 0xFa255d4aa3Aa5d3a26DF650a158835b77877767a and TestWbtc to 0x09Cbeb94e37b5132ad934bc0b55746349B90fEb3
// Minted 10,000 TestUsdc and 100 TestWbtc to 0xaCEdF8742eDC7d923e1e6462852cCE136ee9Fb56
// Minted 10,000 TestUsdc and 100 TestWbtc to 0x2b2eA7eC7e366666772DaAf496817c14b8c0Ae74
// Minted 10,000 TestUsdc and 100 TestWbtc to 0x26BD962c29195832F61Af94f438444A6B7212Ab8

// ! ARBITRUM SEPOLIA
// ! Deployed TestUsdc to 0x2864e0B08dDF0e64FF7c7E8376A5170a8E325651 and TestWbtc to 0x27D6834e8D35CdAB5991b66ef1550326f1018F62
// Minted 10,000 TestUsdc and 100 TestWbtc to 0xaCEdF8742eDC7d923e1e6462852cCE136ee9Fb56
// Minted 10,000 TestUsdc and 100 TestWbtc to 0x2b2eA7eC7e366666772DaAf496817c14b8c0Ae74
// Minted 10,000 TestUsdc and 100 TestWbtc to 0x26BD962c29195832F61Af94f438444A6B7212Ab8
// Minted 10,000 TestUsdc and 100 TestWbtc to 0xcca319f79859761Cb2248Af392cB015967063369
