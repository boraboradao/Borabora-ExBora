import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-contract-sizer";
import "hardhat-gas-reporter";
import "@typechain/hardhat";
import "@nomiclabs/hardhat-ethers";
import * as dotenv from "dotenv";
// import {config as configDotenv} from 'dotenv'

dotenv.config({ path: __dirname + "/.env" });

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 100,
      },
    },
  },

  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      gasPrice: 5000000000,
      gas: 2100000,
    },
    bnbt: {
      url: process.env.BNBT_NODE_URL,
      accounts: [process.env.PRIVATE_KEY ? process.env.PRIVATE_KEY : ""],
    },
    bnb: {
      url: process.env.BSC_NODE_URL,
      accounts: [
        process.env.BSC_PRIVATE_KEY ? process.env.BSC_PRIVATE_KEY : "",
      ],
    },
  },

  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: false,
    strict: false,
  },

  gasReporter: {
    currency: "USD",
    gasPrice: 10,
    enabled: true,
  },

  etherscan: {
    apiKey: {
      bscTestnet: process.env.BSCSCAN_API_KEY
        ? process.env.BSCSCAN_API_KEY
        : "",
      bsc: process.env.BSCSCAN_API_KEY ? process.env.BSCSCAN_API_KEY : "",
    },
  },
};

export default config;
