const { ethers } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

// * ETH SEPOLIA
// * Deployed Invisible to 0x1067EEB555DC298f7F4787919104826FF5881060
// * Deployed StructHasher to 0xB54b9D3c5e274b577AD4fba497779F6253F1bc89 and EscapeVerifier to 0xf2c1E1D6cA9c35D1686f29f082927748520c7F63
// * Deployed TestUsdc to 0xFa255d4aa3Aa5d3a26DF650a158835b77877767a and TestWbtc to 0x09Cbeb94e37b5132ad934bc0b55746349B90fEb3
// * Deployed MessageRelay to 0x65cAD7503C36FbB9eda10877c113311c2d732D82

// ! ARBITRUM SEPOLIA
// ! Deployed InvisibleL2 to 0x72D3D0F9f9A9F8ca748Fbed1Fd7A8A1b17a943e4
// ! Deployed TestUsdc to 0x2864e0B08dDF0e64FF7c7E8376A5170a8E325651 and TestWbtc to 0x27D6834e8D35CdAB5991b66ef1550326f1018F62
// ! Deployed MessageRelay to 0x990248Cbae36334a576BD3Db2aA9bfFC6AA1AdC3

async function transitionBatch(invisibleAddress) {
  const [signer] = await ethers.getSigners();

  const invisibleL1Abi =
    require("../artifacts/src/Invisible.sol/Invisible.json").abi;
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

transitionBatch("0x1067EEB555DC298f7F4787919104826FF5881060").catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

function getProgramOutput() {
  return [
    2814406029350887433650665521402299079787207694489376194532648055529135238208n,
    2277435378462760352642837143377621755718748016556037423724327297283237906196n,
    597632763343895789575n,
    2923003274661805836407372083284205268570214498304n,
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
    5000000n,
    50000000n,
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
    575047282202122890069229389724928591915440815936249435598831867634252178889n,
    0n,
    7878787n,
    0n,
    0n,
    5656565n,
    0n,
    0n,
    3093476031982862048153910526152911283182991424n,
    1669987464367741806901581703315727722326801619559351826421346426798401265671n,
    3093476031982861889697585497624236096120090752n,
    1669987464367741806901581703315727722326801619559351826421346426798401265671n,
    2854938975308276248714895682706771607557164717693820592588384252426712806944n,
  ];
}
