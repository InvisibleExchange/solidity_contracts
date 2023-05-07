// Import the functions you need from the SDKs you need
const { initializeApp } = require("firebase/app");
const { getFirestore } = require("firebase/firestore/lite");
// TODO: Add SDKs for Firebase products that you want to use
// https://firebase.google.com/docs/web/setup#available-libraries

// Your web app's Firebase configuration
// For Firebase JS SDK v7.20.0 and later, measurementId is optional
const firebaseConfig = {
  apiKey: "AIzaSyC2ErVSKSg7LG3m2Ty2V34EwBYgDt_EE30",
  authDomain: "invisibl333.firebaseapp.com",
  projectId: "invisibl333",
  storageBucket: "invisibl333.appspot.com",
  messagingSenderId: "1000403357121",
  appId: "1:1000403357121:web:ce861b631538baa842f340",
  measurementId: "G-RD8K36KX2J",
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);

const db = getFirestore(app);

module.exports = { db };
