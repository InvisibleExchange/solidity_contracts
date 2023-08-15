// Import the functions you need from the SDKs you need
const { initializeApp } = require("firebase/app");
const { getFirestore } = require("firebase/firestore/lite");
// TODO: Add SDKs for Firebase products that you want to use
// https://firebase.google.com/docs/web/setup#available-libraries

// Your web app's Firebase configuration
// For Firebase JS SDK v7.20.0 and later, measurementId is optional

const firebaseConfig = {
  apiKey: "AIzaSyCL8CFDzybWfN8bvxQJgPNvpfpNvn_mkCk",
  authDomain: "testing-1b2fb.firebaseapp.com",
  databaseURL: "https://testing-1b2fb.firebaseio.com",
  projectId: "testing-1b2fb",
  storageBucket: "testing-1b2fb.appspot.com",
  messagingSenderId: "283746589409",
  appId: "1:283746589409:web:68088230883f0bb2e0b5a0",
  measurementId: "G-YF5VHQ5NMX",
};

// const firebaseConfig = {
//   apiKey: "AIzaSyC2ErVSKSg7LG3m2Ty2V34EwBYgDt_EE30",
//   authDomain: "invisibl333.firebaseapp.com",
//   projectId: "invisibl333",
//   storageBucket: "invisibl333.appspot.com",
//   messagingSenderId: "1000403357121",
//   appId: "1:1000403357121:web:ce861b631538baa842f340",
//   measurementId: "G-RD8K36KX2J",
// };

// Initialize Firebase
const app = initializeApp(firebaseConfig);

const db = getFirestore(app);

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
  query,
  orderBy,
  limit,
} = require("firebase/firestore/lite");

const { ec, getKeyPair } = require("starknet").ec; //require("starknet/utils/ellipticCurve.js");




async function getLastDayTrades(isPerp) {
  let now = new Date().getTime() - 24 * 60 * 60 * 1000;
  now = now / 1000;

  let q;
  if (isPerp) {
    q = query(
      collection(db, "perp_fills"),
      where("timestamp", ">=", Number(now))
    );
  } else {
    q = query(collection(db, `fills`), where("timestamp", ">=", Number(now)));
  }

  let token24hVolumes = {};
  let token24hTrades = {};

  const querySnapshot = await getDocs(q);

  let fills = querySnapshot.docs.map((doc) => doc.data());

  for (let fill of fills) {
    let token = isPerp ? fill.synthetic_token : fill.base_token;

    if (!token24hVolumes[token]) {
      token24hVolumes[token] = fill.amount;
      token24hTrades[token] = 1;
    } else {
      token24hVolumes[token] += fill.amount;
      token24hTrades[token] += 1;
    }
  }

  return { token24hVolumes, token24hTrades };
}

module.exports = {
  getLastDayTrades,
};
