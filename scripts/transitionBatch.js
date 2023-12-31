const { ethers } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

// * Deployed Invisible to 0x557d570c97E92b4A2C7fdfaE4DDCb9EF931d33C2
// & Deployed StructHasher to 0xb19f3ADF9185C8b9122f4843a87bC51EE4FA15a2 and EscapeVerifier to 0x485caa427D245458D71674129A2340bDB69d8651
// ? Deployed TestUsdc to 0x42Ca0987Fd7D46B985907d376Bb222D1C6281a71 and TestWbtc to 0x72a35ECeE1eb4593E9eb780AA5a5D436AB3b3941

async function main() {
  const [signer] = await ethers.getSigners();

  const invisibleL1Abi =
    require("../artifacts/src/Invisible.sol/Invisible.json").abi;
  const invisibleAddress = "0x557d570c97E92b4A2C7fdfaE4DDCb9EF931d33C2";
  const invisibleContract = new ethers.Contract(
    invisibleAddress,
    invisibleL1Abi,
    signer ?? undefined
  );

  let programOutput = getProgramOutput(); //.map((x) => BigNumber.from(x));

  let overrides = { gasLimit: 750000 };

  let txRes = await invisibleContract
    .updateStateAfterTxBatch(programOutput, overrides)
    .catch((err) => {
      console.log("Error: ", err);
    });
  console.log("tx hash: ", txRes.hash);
  let receipt = await txRes.wait();
  console.log("receipt: ", receipt);
  console.log("Successfully updated state after tx batch: ", txRes.hash);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

function getProgramOutput() {
  return [
    2178068042422599309597315325825185436018714696379990085469773728252658426196n,
    3068657384447421633575679211318303930539487130512065774637607817153422085016n,
    597614602336677658626n,
    22300745198530623141535718272929836482691072n,
    210258926710712570525957419222609112870661182717955n,
    3592681469n,
    453755560n,
    2413654107n,
    277158171n,
    3592681469n,
    453755560n,
    277158171n,
    8n,
    8n,
    6n,
    8n,
    250n,
    2500n,
    50000n,
    250000n,
    6n,
    6n,
    6n,
    50000000n,
    500000000n,
    350000000n,
    150000n,
    3000000n,
    1500000n,
    15000000n,
    100000000n,
    1000000000n,
    9090909n,
    7878787n,
    5656565n,
    874739451078007766457464989774322083649278607533249481151382481072868806602n,
    3324833730090626974525872402899302150520188025637965566623476530814354734325n,
    1839793652349538280924927302501143912227271479439798783640887258675143576352n,
    296568192680735721663075531306405401515803196637037431012739700151231900092n,
    9090909n,
    0n,
    0n,
    7878787n,
    0n,
    0n,
    5656565n,
    0n,
    0n,
    704691608687245587077909074011728735611348324416891667261556284258056215266n,
    104465481777471529088702081153442803765281940697n,
    13066842889764036997701939897810346102003200000002n,
  ];
}
