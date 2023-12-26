require("@nomicfoundation/hardhat-toolbox");

require("@openzeppelin/hardhat-upgrades");

const path = require("path");
const dotenv = require("dotenv");
dotenv.config({ path: path.join(__dirname, ".env") });

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.22",
    settings: {
      outputSelection: {
        "*": {
          "*": ["storageLayout"],
        },
      },
      optimizer: {
        enabled: true,
        runs: 1000,
      },
      viaIR: true,
    },

    overrides: {
      "src/**/*.sol": {
        viaIR: true,
      },
    },
  },
  allowUnlimitedContractSize: true,
  paths: {
    sources: "./src",
    tests: "./test/hardhat",
    artifacts: "./artifacts",
  },
  networks: {
    sepolia: {
      url: `https://ethereum-sepolia.publicnode.com`,
      accounts: [process.env.PRIVATE_KEY],
    },
  },

  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};
