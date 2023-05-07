const { getKeyPair } = require("starknet/utils/ellipticCurve");
const User = require("../users/Invisibl3User");
const { trimHash } = require("../users/Notes");
const { pedersen } = require("./pedersen");

const db = require("../helpers/firebase/firebaseAdminConfig").db;

// ! RESTORE KEY DATA ========================================================================
// TODO: Seperate logic for restoring destSpentAddress that gets generated as a sum of priv keys
async function restoreKeyData(privateSeed, privSpendKey, privViewKey) {
  // ? Get all the addresses from the datatbase =====

  let notesCollection = db.collection("notes");
  let docs = await notesCollection.listDocuments();

  const sortedAddresses = docs.map((obj) => BigInt(obj.id));
  sortedAddresses.sort((a, b) => (a > b ? 1 : a < b ? -1 : 0));

  let positionsCollection = db.collection("positions");
  let docs2 = await positionsCollection.listDocuments();

  const sortedPosAddresses = docs2.map((obj) => BigInt(obj.id));
  sortedPosAddresses.sort((a, b) => (a > b ? 1 : a < b ? -1 : 0));

  // ? ===================================================

  const tokens = [12345, 54321, 55555];

  let privKeyData = {};

  // & This returns the dest received address and blinding
  for (const token of tokens) {
    let ksi = trimHash(pedersen([privSpendKey, token]), 240);
    let kvi = trimHash(pedersen([privViewKey, token]), 240);
    let Kvi = getKeyPair(kvi).getPublic();

    for (let i = 0; i < 5; i++) {
      let ko = trimHash(pedersen([i, BigInt(Kvi.getX())]), 240) + ksi;
      let Ko = BigInt(getKeyPair(ko).getPublic().getX());

      // If the address is found in the database, then it is a valid address
      let isFound = isNumberInSortedArray(Ko, sortedAddresses);

      if (isFound) {
        privKeyData[Ko] = ko;
      }
    }
  }

  // ? ===================================================

  let posPrivKeyData = {};

  for (const token of tokens) {
    let ksi = trimHash(pedersen([privSpendKey, token]), 240);
    let kvi = trimHash(pedersen([privViewKey, token]), 240);
    let Kvi = getKeyPair(kvi).getPublic();

    for (let i = 0; i < 5; i++) {
      let ko = trimHash(pedersen([i, BigInt(Kvi.getX())]), 240) + ksi;
      let Ko = BigInt(getKeyPair(ko).getPublic().getX());

      // If the address is found in the database, then it is a valid address
      let isFound = isNumberInSortedArray(Ko, sortedPosAddresses);

      if (isFound) {
        posPrivKeyData[Ko] = ko;
      }
    }
  }
}

async function main() {
  let user = User.fromPrivKey(1234);

  //   console.log(user);

  await restoreKeyData(user.privateSeed, user.privSpendKey, user.privViewKey);
}

main();

function isNumberInSortedArray(num, array) {
  let left = 0;
  let right = array.length - 1;

  while (left <= right) {
    let mid = Math.floor((left + right) / 2);

    if (array[mid] === num) {
      return true;
    } else if (array[mid] < num) {
      left = mid + 1;
    } else {
      right = mid - 1;
    }
  }

  return false;
}
