// Import the functions you need from the SDKs you need
const {
  initializeApp,
  applicationDefault,
  cert,
} = require("firebase-admin/app");
const {
  getFirestore,
  Timestamp,
  FieldValue,
} = require("firebase-admin/firestore");

const serviceAccount = require("./invisibl333-362714-2703fb3e24cb.json");

initializeApp({
  credential: cert(serviceAccount),
  databaseURL: "https://invisibl333.firebaseio.com",
});

const db = getFirestore();

module.exports = { db };
