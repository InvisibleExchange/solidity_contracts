require("@nomicfoundation/hardhat-toolbox");

require("@openzeppelin/hardhat-upgrades");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
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
    },

    overrides: {
      "contracts/**/*.sol": {
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
};
