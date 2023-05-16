// const grpc = require("@grpc/grpc-js");
// const protoLoader = require("@grpc/proto-loader");

// const packageDefinition = protoLoader.loadSync(
//   "../../invisible_backend/proto/engine.proto",
//   { keepCase: true, longs: String, enums: String, defaults: true, oneofs: true }
// );
// const engine = grpc.loadPackageDefinition(packageDefinition).engine;

// const SERVER_URL = "localhost:50052";

// const client = new engine.Engine(SERVER_URL, grpc.credentials.createInsecure());

// client.get_state_info({}, function (err, response) {
//   if (err) {
//     console.log(err);
//   } else {
//     console.log(response);
//   }
// });

let W3CWebSocket = require("websocket").w3cwebsocket;
let wsClient = new W3CWebSocket(`ws://localhost:4040/`);

wsClient.onopen = function () {
  console.log("WebSocket Client Connected");
  wsClient.send("1234567654321");
};

wsClient.onmessage = function (e) {
  console.log(e.data);
};
