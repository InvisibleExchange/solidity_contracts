const { db } = require("./firebaseConfig.js");
const {
  collection,
  addDoc,
  getDocs,
  getDoc,
  doc,
  updateDoc,
  setDoc,
  deleteDoc,
  where,
} = require("firebase/firestore/lite");
const bigInt = require("big-integer");

const { Note, trimHash } = require("../../users/Notes.js");
const { pedersen } = require("../pedersen.js");
const { ec, getKeyPair } = require("starknet/utils/ellipticCurve.js");

const BN = require("bn.js");

// TODO: fetch deposit ids on login and remove them if they've been used

/* global BigInt */

const COMMITMENT_MASK = 112233445566778899n;
const AMOUNT_MASK = 998877665544332112n;

// ---- NOTES ---- //

async function storeNewNote(note) {
  //
  let hash8 = trimHash(note.blinding, 64);
  let hiddenAmount = bigInt(note.amount).xor(hash8).value;

  let addr = note.address.getX().toString();

  // TODO let dbDocId = addr + "-" + note.index.toString();

  let noteAddressDoc = doc(db, `notes/${addr}/indexes`, note.index.toString());
  let noteAddressData = await getDoc(noteAddressDoc);

  if (noteAddressData.exists()) {
    await updateDoc(noteAddressDoc, {
      index: note.index.toString(),
      token: note.token.toString(),
      commitment: note.commitment.toString(),
      address: [addr, note.address.getY().toString()],
      hidden_amount: hiddenAmount.toString(),
    });
  } else {
    await setDoc(noteAddressDoc, {
      index: note.index.toString(),
      token: note.token.toString(),
      commitment: note.commitment.toString(),
      address: [addr, note.address.getY().toString()],
      hidden_amount: hiddenAmount.toString(),
    });
  }
}

async function removeNoteFromDb(note) {
  //

  let addr = note.address.getX().toString();

  let noteAddressDoc = doc(db, `notes/${addr}/indexes`, note.index.toString());
  let noteAddressData = await getDoc(noteAddressDoc);

  if (noteAddressData.exists()) {
    await deleteDoc(noteAddressDoc);
  }
}

async function fetchStoredNotes(address, blinding) {
  // Address should be the x coordinate of the address in decimal format

  const querySnapshot = await getDocs(
    collection(db, `notes/${address}/indexes`)
  );

  if (querySnapshot.empty) {
    return [];
  }

  let notes = [];
  querySnapshot.forEach((doc) => {
    let noteData = doc.data();

    let addr = ec
      .keyFromPublic({
        x: new BN(noteData.address[0]),
        y: new BN(noteData.address[1]),
      })
      .getPublic();

    // let yt = pedersen([BigInt(addr.getX()), privateSeed]);
    let hash8 = trimHash(blinding, 64);
    let amount = Number.parseInt(
      bigInt(noteData.hidden_amount).xor(hash8).value
    );

    if (pedersen([BigInt(amount), blinding]) != noteData.commitment) {
      throw "Invalid amount and blinding";
    }

    let note = new Note(
      addr,
      BigInt(noteData.token),
      amount,
      blinding,
      BigInt(noteData.index)
    );

    notes.push(note);
  });

  return notes;
}

// ---- POSITIONS ---- //

async function storeNewPosition(positionObject) {
  let addr = positionObject.position_address;

  let positionAddressDoc = doc(
    db,
    `positions/${addr}/indexes`,
    positionObject.index.toString()
  );
  let positionAddressData = await getDoc(positionAddressDoc);

  if (positionAddressData.exists()) {
    await updateDoc(positionAddressDoc, {
      order_side: positionObject.order_side.toString(),
      synthetic_token: positionObject.synthetic_token.toString(),
      collateral_token: positionObject.collateral_token.toString(),
      position_size: positionObject.position_size.toString(),
      margin: positionObject.margin.toString(),
      entry_price: positionObject.entry_price.toString(),
      liquidation_price: positionObject.liquidation_price.toString(),
      bankruptcy_price: positionObject.bankruptcy_price.toString(),
      position_address: positionObject.position_address,
      last_funding_idx: positionObject.last_funding_idx.toString(),
      hash: positionObject.hash.toString(),
      index: positionObject.index,
    });
  } else {
    await setDoc(positionAddressDoc, {
      order_side: positionObject.order_side.toString(), //
      synthetic_token: positionObject.synthetic_token.toString(),
      collateral_token: positionObject.collateral_token.toString(), //
      position_size: positionObject.position_size.toString(),
      margin: positionObject.margin.toString(), //
      entry_price: positionObject.entry_price.toString(), //
      liquidation_price: positionObject.liquidation_price.toString(), //
      bankruptcy_price: positionObject.bankruptcy_price.toString(), //
      position_address: positionObject.position_address, //
      last_funding_idx: positionObject.last_funding_idx.toString(), //
      hash: positionObject.hash.toString(), //
      index: positionObject.index, //
    });
  }
}

async function removePositionFromDb(positionAddressX, index) {
  //

  let positionAddressDoc = doc(
    db,
    `positions/${positionAddressX}/indexes`,
    index.toString()
  );
  let positionAddressData = await getDoc(positionAddressDoc);

  if (positionAddressData.exists()) {
    await deleteDoc(positionAddressDoc);
  }
}

async function fetchStoredPosition(address) {
  // returns the position at this address from the db

  const querySnapshot = await getDocs(
    collection(db, `positions/${address}/indexes`)
  );

  if (querySnapshot.empty) {
    return [];
  }

  let positions = [];
  querySnapshot.forEach((doc) => {
    let position = doc.data();

    positions.push(position);
  });

  return positions;
}

async function fetchLiquidatablePositions(index_price) {
  const querySnapshot = await getDocs(collection(db, `positions`));

  if (querySnapshot.empty) {
    return [];
  }

  let liquidablePositions = [];
  querySnapshot.forEach(async (doc) => {
    let positionAddr = doc.id;

    const querySnapshot = await getDocs(
      collection(db, `positions/${positionAddr}/indexes`)
    );

    if (querySnapshot.empty) {
      return;
    }

    querySnapshot.forEach(async (doc) => {
      let positionData = doc.data();

      if (
        (positionData == "Long" &&
          index_price <= positionData.liquidation_price) ||
        (positionData == "Short" &&
          index_price >= positionData.liquidation_price)
      ) {
        liquidablePositions.push(positionData);
      }
    });
  });
}

// ---- USER INFO ---- //

async function registerUser(userId) {
  let userAddressesDoc = doc(db, "users", userId.toString());
  let userAddressData = await getDoc(userAddressesDoc);

  if (userAddressData.exists()) {
    return;
  }

  let userData = {
    noteCounts: {},
    positionCounts: {},
    depositIds: [],
  };

  await setDoc(userAddressesDoc, userData);

  return userData;
}

async function storeUserData(userId, noteCounts, positionCounts) {
  //& stores privKey, the address can be derived from the privKey

  let userDataDoc = doc(db, "users", userId.toString());
  let userDataData = await getDoc(userDataDoc);

  if (!userDataData.exists()) {
    throw "Register user first";
  }

  await updateDoc(userDataDoc, {
    noteCounts,
    positionCounts,
  });
}

async function storePrivKey(userId, privKey, isPosition) {
  let docRef;
  if (isPosition) {
    docRef = doc(db, `users/${userId}/positionPrivKeys`, privKey.toString());
  } else {
    docRef = doc(db, `users/${userId}/privKeys`, privKey.toString());
  }

  await setDoc(docRef, {});
}

async function removePrivKey(userId, privKey, isPosition) {
  let docRef;
  if (isPosition) {
    docRef = doc(db, `users/${userId}/positionPrivKeys`, privKey.toString());
  } else {
    docRef = doc(db, `users/${userId}/privKeys`, privKey.toString());
  }

  await deleteDoc(docRef);
}

async function storeOrderId(userId, orderId, pfrNotePrivKey, isPerp) {
  if (!orderId) {
    return;
  }

  let docRef;
  if (isPerp) {
    docRef = doc(db, `users/${userId}/perpetualOrderIds`, orderId);
  } else {
    docRef = doc(db, `users/${userId}/orderIds`, orderId);
  }

  await setDoc(docRef, {
    pfrPrivKey: pfrNotePrivKey ? pfrNotePrivKey.toString() : null,
  });
}

async function removeOrderId(userId, orderId, isPerp) {
  let docRef;
  if (isPerp) {
    docRef = doc(db, `users/${userId}/perpetualOrderIds`, orderId);
  } else {
    docRef = doc(db, `users/${userId}/orderIds`, orderId);
  }

  await deleteDoc(docRef);
}

async function fetchUserData(userId) {
  //& stores privKey : [address.x, address.y]

  let userDoc = doc(db, "users", userId.toString());
  let userData = await getDoc(userDoc);

  if (!userData.exists()) {
    await registerUser(userId);
    return {
      privKeys: [],
      positionPrivKeys: [],
      orderIds: [],
      perpetualOrderIds: [],
      noteCounts: {},
      positionCounts: {},
    };
  }

  let noteCounts = userData.data().noteCounts;
  let positionCounts = userData.data().positionCounts;

  let pfrKeys = {};

  // Note priv_keys
  let querySnapshot = await getDocs(collection(db, `users/${userId}/privKeys`));
  let privKeys = [];
  if (!querySnapshot.empty) {
    querySnapshot.forEach((doc) => {
      privKeys.push(doc.id);
    });
  }

  // position priv_keys
  querySnapshot = await getDocs(
    collection(db, `users/${userId}/positionPrivKeys`)
  );
  let positionPrivKeys = [];
  if (!querySnapshot.empty) {
    querySnapshot.forEach((doc) => {
      positionPrivKeys.push(doc.id);
    });
  }

  // spot order ids
  querySnapshot = await getDocs(collection(db, `users/${userId}/orderIds`));
  let orderIds = [];
  if (!querySnapshot.empty) {
    querySnapshot.forEach((doc) => {
      orderIds.push(Number.parseInt(doc.id));
      pfrKeys[doc.id] = doc.data().pfrPrivKey;
    });
  }

  // perpetual order ids
  querySnapshot = await getDocs(
    collection(db, `users/${userId}/perpetualOrderIds`)
  );
  let perpetualOrderIds = [];
  if (!querySnapshot.empty) {
    querySnapshot.forEach((doc) => {
      perpetualOrderIds.push(Number.parseInt(doc.id));
      if (doc.data().pfrPrivKey) {
        pfrKeys[doc.id] = doc.data().pfrPrivKey;
      }
    });
  }

  return {
    privKeys,
    noteCounts,
    positionCounts,
    orderIds,
    perpetualOrderIds,
    positionPrivKeys,
    pfrKeys,
  };
}

// ---- DEPOSIT ---- //
async function storeOnchainDeposit(deposit) {
  let depositDoc = doc(db, "deposits", deposit.depositId.toString());
  let depositData = await getDoc(depositDoc);

  if (depositData.exists()) {
    await updateDoc(depositDoc, {
      depositId: deposit.depositId.toString(),
      starkKey: deposit.starkKey.toString(),
      tokenId: deposit.tokenId.toString(),
      depositAmountScaled: deposit.depositAmountScaled.toString(),
      timestamp: deposit.timestamp,
    });
  } else {
    await setDoc(depositDoc, {
      depositId: deposit.depositId.toString(),
      starkKey: deposit.starkKey.toString(),
      tokenId: deposit.tokenId.toString(),
      depositAmountScaled: deposit.depositAmountScaled.toString(),
      timestamp: deposit.timestamp,
    });
  }
}

async function storeDepositId(userId, depositId) {
  if (!depositId) return;
  // ? Stores the depositId of the user

  let userDataDoc = doc(db, "users", userId.toString());
  let userDataData = await getDoc(userDataDoc);

  let depositIdData = userDataData.data().depositIds;
  if (!depositIdData.includes(depositId.toString())) {
    depositIdData.push(depositId.toString());
  }

  await updateDoc(userDataDoc, {
    depositIds: depositIdData,
  });
}

async function removeDepositFromDb(depositId) {
  //
  if (!depositId) return;

  let depositDoc = doc(db, `deposits`, depositId.toString());
  let depositData = await getDoc(depositDoc);

  if (depositData.exists()) {
    await deleteDoc(depositDoc);
  }
}

async function fetchOnchainDeposits(userId) {
  if (!userId) {
    return [];
  }

  let userDataDoc = doc(db, "users", userId.toString());
  let userDataData = await getDoc(userDataDoc);

  let depositIds = userDataData.data().depositIds;

  let deposits = [];
  for (const depositId of depositIds) {
    let depositDoc = doc(db, "deposits", depositId);
    let depositData = await getDoc(depositDoc);

    deposits.push({
      depositId: depositData.data().depositId,
      starkKey: depositData.data().starkKey,
      tokenId: depositData.data().tokenId,
      depositAmountScaled: depositData.data().depositAmountScaled,
      timestamp: depositData.data().timestamp,
    });
  }

  return deposits;
}

// ---- DEPOSIT ---- //
async function fetchUserFills(user_id) {
  const q1 = query(collection(db, `fills`), where("user_id_a", "==", user_id));
  const querySnapshot1 = await getDocs(q1);

  const q2 = query(collection(db, `fills`), where("user_id_b", "==", user_id));
  const querySnapshot2 = await getDocs(q2);

  // Loop through the first and second query and add them to the same array ordered by timestamp
  let fills = [];
  let i = 0;
  let j = 0;
  while (i < querySnapshot1.docs.length && j < querySnapshot2.docs.length) {
    if (
      querySnapshot1.docs[i].data().timestamp >
      querySnapshot2.docs[j].data().timestamp
    ) {
      fills.push(querySnapshot1.docs[i].data());
      i++;
    } else {
      fills.push(querySnapshot2.docs[j].data());
      j++;
    }
  }

  while (i < querySnapshot1.docs.length) {
    fills.push(querySnapshot1.docs[i].data());
    i++;
  }

  while (j < querySnapshot2.docs.length) {
    fills.push(querySnapshot2.docs[j].data());
    j++;
  }

  return fills;
}

/**
 * @param {} n number of fills to fetch
 */
async function fetchLatestFills(n) {
  const q = query(
    collection(db, `fills`),
    orderBy("timestamp", "desc"),
    limit(n)
  );

  const querySnapshot = await getDocs(q);
  let fills = querySnapshot.docs.map((doc) => doc.data());

  return fills;
}

// ================================================================

// ================================================================

module.exports = {
  storeNewNote,
  fetchStoredNotes,
  storeUserData,
  fetchUserData,
  removeNoteFromDb,
  storeNewPosition,
  removePositionFromDb,
  fetchStoredPosition,
  storeOnchainDeposit,
  storeDepositId,
  removeDepositFromDb,
  fetchOnchainDeposits,
  storePrivKey,
  removePrivKey,
  storeOrderId,
  removeOrderId,
  fetchUserFills,
  fetchLatestFills,
};
