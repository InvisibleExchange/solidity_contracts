const grpc = require("@grpc/grpc-js");
const protoLoader = require("@grpc/proto-loader");
const { getLastDayTrades } = require("./firebaseConnection");

const { db } = require("./firebaseAdminConfig");
const { computeHashOnElements } = require("starknet/dist/utils/hash");
const path = require("path");

const packageDefinition = protoLoader.loadSync(
  path.join(__dirname, "../../../../invisible_backend/proto/engine.proto"),

  { keepCase: true, longs: String, enums: String, defaults: true, oneofs: true }
);
const engine = grpc.loadPackageDefinition(packageDefinition).engine;

const SERVER_URL = "localhost:50052";
// const SERVER_URL = "54.212.28.196:50052";

const client = new engine.Engine(SERVER_URL, grpc.credentials.createInsecure());

async function getStateInfo() {
  client.get_state_info({}, function (err, response) {
    if (err) {
      console.log(err);
    } else {
      console.log(response);

      let res_map = {};
      for (let i = 0; i < response.state_tree.length; i++) {
        const element = response.state_tree[i];

        if (element != 0) {
          res_map[i] = element;
        }
      }

      // * =====================================================
      const fs = require("fs");

      const jsonData = JSON.stringify(
        res_map,
        (key, value) => {
          if (typeof value === "bigint") {
            return value.toString(); // Convert BigInt to string
          }
          return value;
        },
        2
      );

      fs.writeFile("dex_state.json", jsonData, "utf8", (err) => {
        if (err) {
          console.error("Error writing JSON file:", err);
        } else {
          console.log("JSON data has been written to dex_state.json");
        }
      });
      console.log(res_map);

      // * =====================================================
    }
  });
}

let counter = 0;
async function fetchDbState() {
  let state = {}; // {idx: note}

  let docsLength = 0;

  // * Notes ------------------------------
  let notesCollection = db.collection("notes");
  let docs = await notesCollection.listDocuments();
  docs.forEach((doc) => {
    doc.listCollections().then((collections) => {
      collections.forEach((collection) => {
        collection.listDocuments().then((docs_) => {
          let numDocs = docs_.length;

          let c2 = 0;
          docs_.forEach((doc) => {
            doc.get().then((doc) => {
              let data = doc.data();
              let hash = BigInt(
                computeHashOnElements([
                  BigInt(data.address[0]),
                  data.token,
                  data.commitment,
                ]),
                16
              );

              state[doc.id] = hash;

              c2++;
              if (c2 == numDocs) {
                counter++;
              }
            });
          });
        });
      });
    });
  });
  docsLength += docs.length;

  // * Positions ------------------------------
  let positionsCollection = db.collection("positions");
  docs = await positionsCollection.listDocuments();
  docs.forEach((doc) => {
    doc.listCollections().then((collections) => {
      collections.forEach((collection) => {
        collection.listDocuments().then((docs) => {
          let numDocs = docs.length;

          let c2 = 0;
          docs.forEach((doc) => {
            doc.get().then((doc) => {
              let data = doc.data();
              let hash = BigInt(data.hash);

              state[doc.id] = hash;

              c2++;
              if (c2 == numDocs) {
                counter++;
              }
            });
          });
        });
      });
    });
  });
  docsLength += docs.length;

  // * Order Tabs ------------------------------
  let tabsCollection = db.collection("order_tabs");
  docs = await tabsCollection.listDocuments();
  docs.forEach((doc) => {
    doc.listCollections().then((collections) => {
      collections.forEach((collection) => {
        collection.listDocuments().then((docs) => {
          let numDocs = docs.length;

          let c2 = 0;
          docs.forEach((doc) => {
            doc.get().then((doc) => {
              let data = doc.data();
              let hash = BigInt(data.hash);

              state[doc.id] = hash;

              c2++;
              if (c2 == numDocs) {
                counter++;
              }
            });
          });
        });
      });
    });
  });
  docsLength += docs.length;

  while (counter < docsLength) {
    console.log("counter", counter, "docsLength", docsLength);
    await new Promise((resolve) => setTimeout(resolve, 500));
  }

  const fs = require("fs");

  const jsonData = JSON.stringify(
    state,
    (key, value) => {
      if (typeof value === "bigint") {
        return value.toString(); // Convert BigInt to string
      }
      return value;
    },
    2
  );

  // Step 3: Write the JSON string to a file
  fs.writeFile("db_state.json", jsonData, "utf8", (err) => {
    if (err) {
      console.error("Error writing JSON file:", err);
    } else {
      console.log("JSON data has been written to db_state.json");
    }
  });

  console.log("state", state);
}

// * ===================================================== =========================================================
async function compareStates() {
  const fs = require("fs");

  // Step 4: Read the JSON file back into an object
  fs.readFile("db_state.json", "utf8", (err, data) => {
    if (err) {
      console.error("Error reading JSON file:", err);
    } else {
      try {
        const parsedObject = JSON.parse(data, (key, value) => {
          if (/^\d+$/.test(value)) {
            return BigInt(value); // Convert strings to BigInt
          }
          return value;
        });
        let dbState = parsedObject;

        fs.readFile("dex_state.json", "utf8", (err, data) => {
          if (err) {
            console.error("Error reading JSON file:", err);
          } else {
            try {
              const parsedObject = JSON.parse(data, (key, value) => {
                if (/^\d+$/.test(value)) {
                  return BigInt(value); // Convert strings to BigInt
                }
                return value;
              });
              let serverState = parsedObject;

              _compareStatesInner(dbState, serverState);
            } catch (parseErr) {
              console.error("Error parsing JSON:", parseErr);
            }
          }
        });
      } catch (parseErr) {
        console.error("Error parsing JSON:", parseErr);
      }
    }
  });
}

function _compareStatesInner(dbState, serverState) {
  console.log(
    Object.keys(dbState).length,
    " ",
    Object.keys(serverState).length
  );
  for (let idx of Object.keys(dbState)) {
    let dbEl = dbState[idx];
    if (!serverState[idx]) {
      console.log(idx);
    }
    let serverEl = serverState[idx];
    if (dbEl != serverEl) {
      console.log(idx);
    } else {
      // console.log(dbEl, "==", serverEl);
    }
  }
}

// getStateInfo();
// fetchDbState();

compareStates();
