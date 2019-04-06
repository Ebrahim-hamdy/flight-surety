var HDWalletProvider = require("truffle-hdwallet-provider");
var mnemonic =
  "crucial cage deny cloth subway produce need depth hello jeans error monitor";

module.exports = {
  networks: {
    development: {
      // provider: function() {
      //   return new HDWalletProvider(mnemonic, "http://127.0.0.1:7545/");
      // },
      host: "localhost",
      port: 7545,
      network_id: "*"
    },

    ganache: {
      provider: function() {
        return new HDWalletProvider(mnemonic, "http://127.0.0.1:8545/"), 0, 50;
      },
      network_id: "*"
    }
  },
  compilers: {
    solc: {
      version: "0.4.25"
    }
  }
};
