/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require("dotenv").config();
require("@nomiclabs/hardhat-ethers");
require("@openzeppelin/hardhat-upgrades");
const { SEPOLIA, API_URL, PRIVATE_KEY } = process.env;
module.exports = {
  solidity: {
    version: "0.8.12",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  defaultNetwork: "hardhat",
  // settings: {
  //    optimizer: {
  //      enabled: true,
  //      runs: 2000,
  //    },
  //  },
  networks: {
    hardhat: {
      chainId: 31337,
    },
    bsc_testnet: {
      url: API_URL,
      chainId: 97,
      accounts: [PRIVATE_KEY],
    },
    sepolia: {
      url: "https://sepolia.infura.io/v3/z3X7QltOR1YoGxXAC--cO1SahTgeF8Ls",
      chainId: 11155111,
      accounts: [PRIVATE_KEY],
    },
    bsc_mainnet: {
      url: "https://bsc-dataseed.binance.org/",
      chainId: 56,
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
  },
};
