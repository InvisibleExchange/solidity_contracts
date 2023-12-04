// const { expect } = require("chai");

// const { ethers, upgrades } = require("hardhat");

// const fs = require("fs");

// describe("Invisible", function () {
//   let invisible;
//   let escapeVerifier;
//   let testUsdc;

//   let txJson;

//   beforeEach(async function () {
//     const [owner, addr1] = await ethers.getSigners();

//     const Invisible = await ethers.getContractFactory("Invisible");
//     invisible = await upgrades.deployProxy(Invisible, [owner.address], {
//       kind: "uups",
//     });

//     const EscapeVerifier = await ethers.getContractFactory("EscapeVerifier");
//     escapeVerifier = await upgrades.deployProxy(
//       EscapeVerifier,
//       [owner.address],
//       {
//         kind: "uups",
//       }
//     );

//     await invisible.setEscapeVerifier(escapeVerifier.address);

//     let invisibleAddress = await invisible.getAddress();
//     await escapeVerifier.setInvisibleAddress(invisibleAddress);

//     let StructHasher = await ethers.getContractFactory("StructHasher");
//     testUsdc = await StructHasher.deploy("testUsdc", "TT");
//     // function setStructHasher(address _structHasher) external onlyOwner {
//     //     structHasher = _structHasher;
//     // }

//     let TestToken = await ethers.getContractFactory("TestToken");
//     testUsdc = await TestToken.deploy("testUsdc", "TT");

//     let usdcAddress = await testUsdc.getAddress();
//     await invisible.registerToken(usdcAddress, 55555, 6);

//     const data = fs.readFileSync("./test/hardhat/escape-txs.json", "utf8");
//     txJson = JSON.parse(data);
//   });

//   it("escape notes", async () => {
//     let noteEscapes = txJson["note_escapes"];

//     noteEscapes.forEach(async (escape) => {
//       let notes = escape.note_escape.escape_notes.map((note) => {
//         return {
//           index: note.index,
//           addressX: note.address.x,
//           token: note.token,
//           amount: note.amount,
//           blinding: note.blinding,
//         };
//       });

//       //   console.log(notes);
//       //   console.log(escape.note_escape.signature);

//       try {
//         let txResult = await escapeVerifier.startNoteEscape(
//           notes,
//           escape.note_escape.signature
//         );
//         console.log(txResult);
//       } catch (e) {
//         console.log(e);
//       }
//     });
//   });
// });

const fs = require("fs");

function main() {
  const data = fs.readFileSync("./escape-txs.json", "utf8");
  let txJson = JSON.parse(data);

  let noteEscapes = txJson["note_escapes"];

  noteEscapes.forEach(async (escape) => {
    let notes = escape.note_escape.escape_notes.map((note) => {
      return {
        index: note.index,
        addressX: note.address.x,
        token: note.token,
        amount: note.amount,
        blinding: note.blinding,
      };
    });

    console.log(notes);
    console.log(escape.note_escape.signature);
  });
}

main();
