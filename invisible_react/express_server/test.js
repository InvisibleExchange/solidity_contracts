const grpc = require("@grpc/grpc-js");
const protoLoader = require("@grpc/proto-loader");

const packageDefinition = protoLoader.loadSync(
  "../../invisible_backend/proto/engine.proto",
  { keepCase: true, longs: String, enums: String, defaults: true, oneofs: true }
);
const engine = grpc.loadPackageDefinition(packageDefinition).engine;

const SERVER_URL = "localhost:50052";

const client = new engine.Engine(SERVER_URL, grpc.credentials.createInsecure());

client.get_state_info({}, function (err, response) {
  if (err) {
    console.log(err);
  } else {
    console.log(response);
  }
});
