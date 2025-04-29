require('dotenv').config();

module.exports = {
  networks: {
    mainnet: {
      // Don't put your private key here:
      privateKey: process.env.PRIVATE_KEY_MAINNET,
      userFeePercentage: 100,
      feeLimit: 1000 * 1e6,
      fullHost: 'https://api.trongrid.io',
      network_id: '1'
    },
    shasta: {
      privateKey: process.env.PRIVATE_KEY_SHASTA,
      userFeePercentage: 50,
      feeLimit: 1000 * 1e6,
      fullHost: 'https://api.shasta.trongrid.io',
      network_id: '2'
    },
    nile: {
      privateKey: process.env.PRIVATE_KEY_NILE,
      consume_user_resource_percent: 50,
      fee_limit: 1e9,
      fullHost: 'https://nile.trongrid.io',
      network_id: '*',
    },
    development: {
      privateKey: process.env.PRIVATE_KEY_DEVELOPMENT,
      consume_user_resource_percent: 100,
      fee_limit: 1000000000,
      fullHost: process.env.FULL_NODE_DEVELOPMENT,
      network_id: '*'
    },

    compilers: {
      solc: {
        version: "0.8.20",
      }
    }
  },

  // solc compiler optimize
  solc: {
    optimizer: {
      enabled: true, // default: false, true: enable solc optimize
      runs: 200
    },
    evmVersion: 'shanghai',
    //viaIR: true               //Implement viaIR to reduce deployment costs further
  }

};
