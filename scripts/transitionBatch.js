const { ethers } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
const { get } = require("http");
dotenv.config({ path: path.join(__dirname, "../.env") });

async function main() {
  const [signer] = await ethers.getSigners();

  const invisibleL1Abi =
    require("../artifacts/src/Invisible.sol/Invisible.json").abi;
  const invisibleAddress = "0x9ECC2Ccc13Bf31790aaa88A985D3d24A5000d01a";
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
    2450644354998405982022115704618884006901283874365176806194200773707121413423n,
    2450644354998405982022115704618884006901283874365176806194200773707121413423n,
    597612630701875658752n,
    158458742917061392592856416256n,
    210258926710712570525957419222609112870661182717955n,
    3592681469,
    453755560,
    2413654107,
    277158171,
    3592681469,
    453755560,
    277158171,
    8,
    8,
    6,
    8,
    250,
    2500,
    50000,
    250000,
    6,
    6,
    6,
    50000000,
    500000000,
    350000000,
    150000,
    3000000,
    1500000,
    15000000,
    100000000,
    1000000000,
    9090909,
    7878787,
    5656565,
    874739451078007766457464989774322083649278607533249481151382481072868806602n,
    3324833730090626974525872402899302150520188025637965566623476530814354734325n,
    1839793652349538280924927302501143912227271479439798783640887258675143576352n,
    296568192680735721663075531306405401515803196637037431012739700151231900092n,
    9090909,
    1675105640028951796931706474521618708675446344274424013071905128634469405011n,
    768619152717472814158838473210840624932948108904983524884927496794199887899n,
    7878787,
    0,
    0,
    5656565,
    0,
    0,
    3093476031982861889697585497624236096570090752n,
    1669987464367741806901581703315727722326801619559351826421346426798401265671n,
    3093476031982861932772001104944362577399139136n,
    3225200283062039681311450510140452982672304159186741365074365564954203911314n,
    720256024024700982350945910877080384n,
    221169572003772042391163194442018419476810246840n,
    720256060178447889295157023591982336n,
    221169572003772042391163194442018419476810246840n,
  ];
}
