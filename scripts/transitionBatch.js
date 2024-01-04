const { ethers } = require("hardhat");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, "../.env") });

// * Deployed Invisible to 0x951bBd501d9CaF6E75CD9566f8eC40eF0860B10d
// & Deployed StructHasher to 0x572EC9E81190bA3A8763C890ef9EE26f1b40A36C and EscapeVerifier to 0x0931c3d86512aE7A38Ab870052657981bed5e01d
// ? Deployed TestUsdc to 0xa0eb40164C5d64fa4B5b466F677d3ef70c79c5c1 and TestWbtc to 0x71a46b7F3F971982304E48342C78B5460d8047d6

async function main() {
  const [signer] = await ethers.getSigners();

  const invisibleL1Abi =
    require("../artifacts/src/Invisible.sol/Invisible.json").abi;
  const invisibleAddress = "0x951bBd501d9CaF6E75CD9566f8eC40eF0860B10d";
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
    2281620433085456340059554291303887265571879122285199284058614432440453349013n,
    3573272304525349311657958474462939779786208604754195642342706527882714648697n,
    597616076635741618182n,
    79228162514264337593544015872n,
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
    65793n,
    2998183787675689191983209794787519062343261092247560212857805158528148252887n,
    899948125069894827331318255587718780084119485111186428639986813672439141461n,
    3565728768220541163399801779204240126702309103952930684049560536153888709009n,
  ];
}
