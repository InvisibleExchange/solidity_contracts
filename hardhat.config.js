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
      url: `https://sepolia.rpc.thirdweb.com`,
      accounts: [process.env.PRIVATE_KEY],
    },
    arbitrum_sepolia: {
      url: `https://arbitrum-sepolia.rpc.thirdweb.com`,
      accounts: [process.env.PRIVATE_KEY],
    },
  },

  etherscan: {
    apiKey: {
      sepolia: process.env.ETHERSCAN_API_KEY,
      arbitrum_sepolia: process.env.ARBISCAN_API_KEY,
    },

    customChains: [
      {
        network: "arbitrum_sepolia",
        chainId: 421614,
        urls: {
          apiURL: "https://api-sepolia.arbiscan.io/api",
          browserURL: "https://sepolia.arbiscan.io",
        },
      },
    ],
  },
};
