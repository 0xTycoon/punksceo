require("@nomiclabs/hardhat-waffle");

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
    const accounts = await ethers.getSigners();

    for (const account of accounts) {
        console.log(account.address);
    }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

// todo: deploy cig, claim punk, add uniswap pool, seed pool, add liquidity. test deposit & withdraw

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
    solidity: {
        version: "0.7.6",
        settings: {
            optimizer: {
                enabled: true,
                runs: 1000
            },
        },


    },
    mocha: {
        timeout: 30000
    },
    defaultNetwork: "hardhat",
    networks: {

        forkedLocal: {
            url: "http://127.0.0.1:8546",
            chainId: 1,
            forking: {
                url: "http://127.0.0.1:8546",
                blockNumber: 12542205
            }
        },
        ganache: {
            url: "http://127.0.0.1:7545",
            chainId: 1,

        }
    }
};

