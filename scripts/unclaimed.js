const hre = require("hardhat");
let fs = require('fs');

/*

Get unclaimed punks list

to run:

npx hardhat run --network miranda scripts/unclaimed.js

 */

const ReverseRecordsABI =
    [{
        "inputs": [{"internalType": "contract ENS", "name": "_ens", "type": "address"}],
        "stateMutability": "nonpayable",
        "type": "constructor"
    }, {
        "inputs": [{"internalType": "address[]", "name": "addresses", "type": "address[]"}],
        "name": "getNames",
        "outputs": [{"internalType": "string[]", "name": "r", "type": "string[]"}],
        "stateMutability": "view",
        "type": "function"
    }];
const ReverseRecordsAddress = "0x3671aE578E63FdF66ad4F3E12CC0c0d71Ac7510C";

const CIG_ABI = [{
    "inputs": [{
        "internalType": "uint256",
        "name": "_cigPerBlock",
        "type": "uint256"
    }, {"internalType": "address", "name": "_punks", "type": "address"}, {
        "internalType": "uint256",
        "name": "_CEO_epoch_blocks",
        "type": "uint256"
    }, {"internalType": "uint256", "name": "_CEO_auction_blocks", "type": "uint256"}, {
        "internalType": "uint256",
        "name": "_CEO_price",
        "type": "uint256"
    }, {"internalType": "bytes32", "name": "_graffiti", "type": "bytes32"}, {
        "internalType": "address",
        "name": "_NFT",
        "type": "address"
    }, {"internalType": "address", "name": "_V2ROUTER", "type": "address"}, {
        "internalType": "address",
        "name": "_OC",
        "type": "address"
    }, {"internalType": "uint256", "name": "_migration_epochs", "type": "uint256"}, {
        "internalType": "address",
        "name": "_MASTERCHEF_V2",
        "type": "address"
    }], "stateMutability": "nonpayable", "type": "constructor"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "internalType": "address", "name": "owner", "type": "address"}, {
        "indexed": true,
        "internalType": "address",
        "name": "spender",
        "type": "address"
    }, {"indexed": false, "internalType": "uint256", "name": "value", "type": "uint256"}],
    "name": "Approval",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "internalType": "address", "name": "called_by", "type": "address"}, {
        "indexed": false,
        "internalType": "uint256",
        "name": "reward",
        "type": "uint256"
    }],
    "name": "CEODefaulted",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": false, "internalType": "uint256", "name": "price", "type": "uint256"}],
    "name": "CEOPriceChange",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "internalType": "address", "name": "user", "type": "address"}, {
        "indexed": false,
        "internalType": "uint256",
        "name": "amount",
        "type": "uint256"
    }],
    "name": "ChefDeposit",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "internalType": "address", "name": "user", "type": "address"}, {
        "indexed": false,
        "internalType": "uint256",
        "name": "amount",
        "type": "uint256"
    }],
    "name": "ChefWithdraw",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "internalType": "address", "name": "owner", "type": "address"}, {
        "indexed": true,
        "internalType": "uint256",
        "name": "punkIndex",
        "type": "uint256"
    }, {"indexed": false, "internalType": "uint256", "name": "value", "type": "uint256"}],
    "name": "Claim",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "internalType": "address", "name": "user", "type": "address"}, {
        "indexed": false,
        "internalType": "uint256",
        "name": "amount",
        "type": "uint256"
    }],
    "name": "Deposit",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "internalType": "address", "name": "user", "type": "address"}, {
        "indexed": false,
        "internalType": "uint256",
        "name": "amount",
        "type": "uint256"
    }],
    "name": "EmergencyWithdraw",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "internalType": "address", "name": "user", "type": "address"}, {
        "indexed": false,
        "internalType": "address",
        "name": "to",
        "type": "address"
    }, {"indexed": false, "internalType": "uint256", "name": "amount", "type": "uint256"}],
    "name": "Harvest",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "internalType": "address", "name": "user", "type": "address"}, {
        "indexed": true,
        "internalType": "uint256",
        "name": "punk_id",
        "type": "uint256"
    }, {"indexed": false, "internalType": "uint256", "name": "new_price", "type": "uint256"}, {
        "indexed": false,
        "internalType": "bytes32",
        "name": "graffiti",
        "type": "bytes32"
    }],
    "name": "NewCEO",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "internalType": "address", "name": "user", "type": "address"}, {
        "indexed": false,
        "internalType": "uint256",
        "name": "amount",
        "type": "uint256"
    }],
    "name": "RevenueBurned",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": false, "internalType": "uint256", "name": "reward", "type": "uint256"}, {
        "indexed": false,
        "internalType": "uint256",
        "name": "downAmount",
        "type": "uint256"
    }],
    "name": "RewardDown",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": false, "internalType": "uint256", "name": "reward", "type": "uint256"}, {
        "indexed": false,
        "internalType": "uint256",
        "name": "upAmount",
        "type": "uint256"
    }],
    "name": "RewardUp",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "internalType": "address", "name": "user", "type": "address"}, {
        "indexed": false,
        "internalType": "uint256",
        "name": "amount",
        "type": "uint256"
    }],
    "name": "TaxBurned",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "internalType": "address", "name": "user", "type": "address"}, {
        "indexed": false,
        "internalType": "uint256",
        "name": "amount",
        "type": "uint256"
    }],
    "name": "TaxDeposit",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "internalType": "address", "name": "from", "type": "address"}, {
        "indexed": true,
        "internalType": "address",
        "name": "to",
        "type": "address"
    }, {"indexed": false, "internalType": "uint256", "name": "value", "type": "uint256"}],
    "name": "Transfer",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "internalType": "address", "name": "user", "type": "address"}, {
        "indexed": false,
        "internalType": "uint256",
        "name": "amount",
        "type": "uint256"
    }],
    "name": "Withdraw",
    "type": "event"
}, {
    "inputs": [],
    "name": "CEO_price",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [],
    "name": "CEO_punk_index",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [],
    "name": "CEO_state",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [],
    "name": "CEO_tax_balance",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [],
    "name": "The_CEO",
    "outputs": [{"internalType": "address", "name": "", "type": "address"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [],
    "name": "accCigPerShare",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [],
    "name": "admin",
    "outputs": [{"internalType": "address", "name": "", "type": "address"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [{"internalType": "address", "name": "", "type": "address"}, {
        "internalType": "address",
        "name": "",
        "type": "address"
    }],
    "name": "allowance",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [{"internalType": "address", "name": "_spender", "type": "address"}, {
        "internalType": "uint256",
        "name": "_value",
        "type": "uint256"
    }],
    "name": "approve",
    "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [{"internalType": "address", "name": "", "type": "address"}],
    "name": "balanceOf",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [],
    "name": "burnTax",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [{"internalType": "uint256", "name": "_max_spend", "type": "uint256"}, {
        "internalType": "uint256",
        "name": "_new_price",
        "type": "uint256"
    }, {"internalType": "uint256", "name": "_tax_amount", "type": "uint256"}, {
        "internalType": "uint256",
        "name": "_punk_index",
        "type": "uint256"
    }, {"internalType": "bytes32", "name": "_graffiti", "type": "bytes32"}],
    "name": "buyCEO",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [],
    "name": "cigPerBlock",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [{"internalType": "uint256", "name": "_punkIndex", "type": "uint256"}],
    "name": "claim",
    "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "name": "claims",
    "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [],
    "name": "decimals",
    "outputs": [{"internalType": "uint8", "name": "", "type": "uint8"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [{"internalType": "uint256", "name": "_amount", "type": "uint256"}],
    "name": "deposit",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [{"internalType": "uint256", "name": "_amount", "type": "uint256"}],
    "name": "depositTax",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [],
    "name": "emergencyWithdraw",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [{"internalType": "address", "name": "", "type": "address"}],
    "name": "farmers",
    "outputs": [{"internalType": "uint256", "name": "deposit", "type": "uint256"}, {
        "internalType": "uint256",
        "name": "rewardDebt",
        "type": "uint256"
    }],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [{"internalType": "address", "name": "", "type": "address"}],
    "name": "farmersMasterchef",
    "outputs": [{"internalType": "uint256", "name": "deposit", "type": "uint256"}, {
        "internalType": "uint256",
        "name": "rewardDebt",
        "type": "uint256"
    }],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [{"internalType": "address", "name": "_user", "type": "address"}],
    "name": "getStats",
    "outputs": [{"internalType": "uint256[]", "name": "", "type": "uint256[]"}, {
        "internalType": "address",
        "name": "",
        "type": "address"
    }, {"internalType": "bytes32", "name": "", "type": "bytes32"}, {
        "internalType": "uint112[]",
        "name": "",
        "type": "uint112[]"
    }],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [],
    "name": "graffiti",
    "outputs": [{"internalType": "bytes32", "name": "", "type": "bytes32"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [],
    "name": "harvest",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [{"internalType": "uint256", "name": "_punkIndex", "type": "uint256"}],
    "name": "isClaimed",
    "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [],
    "name": "lastRewardBlock",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [],
    "name": "lpToken",
    "outputs": [{"internalType": "contract ILiquidityPoolERC20", "name": "", "type": "address"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [],
    "name": "masterchefDeposits",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [],
    "name": "migrationComplete",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [],
    "name": "name",
    "outputs": [{"internalType": "string", "name": "", "type": "string"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [{"internalType": "uint256", "name": "", "type": "uint256"}, {
        "internalType": "address",
        "name": "_user",
        "type": "address"
    }, {"internalType": "address", "name": "_to", "type": "address"}, {
        "internalType": "uint256",
        "name": "_sushiAmount",
        "type": "uint256"
    }, {"internalType": "uint256", "name": "_newLpAmount", "type": "uint256"}],
    "name": "onSushiReward",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [{"internalType": "address", "name": "_user", "type": "address"}],
    "name": "pendingCig",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [],
    "name": "punks",
    "outputs": [{"internalType": "contract ICryptoPunk", "name": "", "type": "address"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [],
    "name": "renounceOwnership",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [],
    "name": "rewardDown",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [],
    "name": "rewardUp",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [],
    "name": "rewardsChangedBlock",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [{"internalType": "contract ILiquidityPoolERC20", "name": "_addr", "type": "address"}],
    "name": "setPool",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [{"internalType": "uint256", "name": "_price", "type": "uint256"}],
    "name": "setPrice",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [{"internalType": "uint256", "name": "_value", "type": "uint256"}],
    "name": "setReward",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [{"internalType": "uint256", "name": "_startBlock", "type": "uint256"}],
    "name": "setStartingBlock",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [],
    "name": "stakedlpSupply",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [],
    "name": "symbol",
    "outputs": [{"internalType": "string", "name": "", "type": "string"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [],
    "name": "taxBurnBlock",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [],
    "name": "totalSupply",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [{"internalType": "address", "name": "_to", "type": "address"}, {
        "internalType": "uint256",
        "name": "_value",
        "type": "uint256"
    }],
    "name": "transfer",
    "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [{"internalType": "address", "name": "_from", "type": "address"}, {
        "internalType": "address",
        "name": "_to",
        "type": "address"
    }, {"internalType": "uint256", "name": "_value", "type": "uint256"}],
    "name": "transferFrom",
    "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [{"internalType": "uint256", "name": "_value", "type": "uint256"}],
    "name": "unwrap",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [],
    "name": "update",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [{"internalType": "uint256", "name": "", "type": "uint256"}, {
        "internalType": "address",
        "name": "_user",
        "type": "address"
    }],
    "name": "userInfo",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}, {
        "internalType": "uint256",
        "name": "depositAmount",
        "type": "uint256"
    }],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [{"internalType": "address", "name": "", "type": "address"}],
    "name": "wBal",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
}, {
    "inputs": [{"internalType": "uint256", "name": "_amount", "type": "uint256"}],
    "name": "withdraw",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
}, {
    "inputs": [{"internalType": "uint256", "name": "_value", "type": "uint256"}],
    "name": "wrap",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
}];
const PUNKS_ADDRESS = "0xb47e3cd837ddf8e4c57f05d70ab865de6e193bbb";
const PUNKS_ABI = [{
    "constant": true,
    "inputs": [],
    "name": "name",
    "outputs": [{"name": "", "type": "string"}],
    "payable": false,
    "type": "function"
}, {
    "constant": true,
    "inputs": [{"name": "", "type": "uint256"}],
    "name": "punksOfferedForSale",
    "outputs": [{"name": "isForSale", "type": "bool"}, {"name": "punkIndex", "type": "uint256"}, {
        "name": "seller",
        "type": "address"
    }, {"name": "minValue", "type": "uint256"}, {"name": "onlySellTo", "type": "address"}],
    "payable": false,
    "type": "function"
}, {
    "constant": false,
    "inputs": [{"name": "punkIndex", "type": "uint256"}],
    "name": "enterBidForPunk",
    "outputs": [],
    "payable": true,
    "type": "function"
}, {
    "constant": true,
    "inputs": [],
    "name": "totalSupply",
    "outputs": [{"name": "", "type": "uint256"}],
    "payable": false,
    "type": "function"
}, {
    "constant": false,
    "inputs": [{"name": "punkIndex", "type": "uint256"}, {"name": "minPrice", "type": "uint256"}],
    "name": "acceptBidForPunk",
    "outputs": [],
    "payable": false,
    "type": "function"
}, {
    "constant": true,
    "inputs": [],
    "name": "decimals",
    "outputs": [{"name": "", "type": "uint8"}],
    "payable": false,
    "type": "function"
}, {
    "constant": false,
    "inputs": [{"name": "addresses", "type": "address[]"}, {"name": "indices", "type": "uint256[]"}],
    "name": "setInitialOwners",
    "outputs": [],
    "payable": false,
    "type": "function"
}, {
    "constant": false,
    "inputs": [],
    "name": "withdraw",
    "outputs": [],
    "payable": false,
    "type": "function"
}, {
    "constant": true,
    "inputs": [],
    "name": "imageHash",
    "outputs": [{"name": "", "type": "string"}],
    "payable": false,
    "type": "function"
}, {
    "constant": true,
    "inputs": [],
    "name": "nextPunkIndexToAssign",
    "outputs": [{"name": "", "type": "uint256"}],
    "payable": false,
    "type": "function"
}, {
    "constant": true,
    "inputs": [{"name": "", "type": "uint256"}],
    "name": "punkIndexToAddress",
    "outputs": [{"name": "", "type": "address"}],
    "payable": false,
    "type": "function"
}, {
    "constant": true,
    "inputs": [],
    "name": "standard",
    "outputs": [{"name": "", "type": "string"}],
    "payable": false,
    "type": "function"
}, {
    "constant": true,
    "inputs": [{"name": "", "type": "uint256"}],
    "name": "punkBids",
    "outputs": [{"name": "hasBid", "type": "bool"}, {"name": "punkIndex", "type": "uint256"}, {
        "name": "bidder",
        "type": "address"
    }, {"name": "value", "type": "uint256"}],
    "payable": false,
    "type": "function"
}, {
    "constant": true,
    "inputs": [{"name": "", "type": "address"}],
    "name": "balanceOf",
    "outputs": [{"name": "", "type": "uint256"}],
    "payable": false,
    "type": "function"
}, {
    "constant": false,
    "inputs": [],
    "name": "allInitialOwnersAssigned",
    "outputs": [],
    "payable": false,
    "type": "function"
}, {
    "constant": true,
    "inputs": [],
    "name": "allPunksAssigned",
    "outputs": [{"name": "", "type": "bool"}],
    "payable": false,
    "type": "function"
}, {
    "constant": false,
    "inputs": [{"name": "punkIndex", "type": "uint256"}],
    "name": "buyPunk",
    "outputs": [],
    "payable": true,
    "type": "function"
}, {
    "constant": false,
    "inputs": [{"name": "to", "type": "address"}, {"name": "punkIndex", "type": "uint256"}],
    "name": "transferPunk",
    "outputs": [],
    "payable": false,
    "type": "function"
}, {
    "constant": true,
    "inputs": [],
    "name": "symbol",
    "outputs": [{"name": "", "type": "string"}],
    "payable": false,
    "type": "function"
}, {
    "constant": false,
    "inputs": [{"name": "punkIndex", "type": "uint256"}],
    "name": "withdrawBidForPunk",
    "outputs": [],
    "payable": false,
    "type": "function"
}, {
    "constant": false,
    "inputs": [{"name": "to", "type": "address"}, {"name": "punkIndex", "type": "uint256"}],
    "name": "setInitialOwner",
    "outputs": [],
    "payable": false,
    "type": "function"
}, {
    "constant": false,
    "inputs": [{"name": "punkIndex", "type": "uint256"}, {
        "name": "minSalePriceInWei",
        "type": "uint256"
    }, {"name": "toAddress", "type": "address"}],
    "name": "offerPunkForSaleToAddress",
    "outputs": [],
    "payable": false,
    "type": "function"
}, {
    "constant": true,
    "inputs": [],
    "name": "punksRemainingToAssign",
    "outputs": [{"name": "", "type": "uint256"}],
    "payable": false,
    "type": "function"
}, {
    "constant": false,
    "inputs": [{"name": "punkIndex", "type": "uint256"}, {"name": "minSalePriceInWei", "type": "uint256"}],
    "name": "offerPunkForSale",
    "outputs": [],
    "payable": false,
    "type": "function"
}, {
    "constant": false,
    "inputs": [{"name": "punkIndex", "type": "uint256"}],
    "name": "getPunk",
    "outputs": [],
    "payable": false,
    "type": "function"
}, {
    "constant": true,
    "inputs": [{"name": "", "type": "address"}],
    "name": "pendingWithdrawals",
    "outputs": [{"name": "", "type": "uint256"}],
    "payable": false,
    "type": "function"
}, {
    "constant": false,
    "inputs": [{"name": "punkIndex", "type": "uint256"}],
    "name": "punkNoLongerForSale",
    "outputs": [],
    "payable": false,
    "type": "function"
}, {"inputs": [], "payable": true, "type": "constructor"}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "name": "to", "type": "address"}, {
        "indexed": false,
        "name": "punkIndex",
        "type": "uint256"
    }],
    "name": "Assign",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "name": "from", "type": "address"}, {
        "indexed": true,
        "name": "to",
        "type": "address"
    }, {"indexed": false, "name": "value", "type": "uint256"}],
    "name": "Transfer",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "name": "from", "type": "address"}, {
        "indexed": true,
        "name": "to",
        "type": "address"
    }, {"indexed": false, "name": "punkIndex", "type": "uint256"}],
    "name": "PunkTransfer",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "name": "punkIndex", "type": "uint256"}, {
        "indexed": false,
        "name": "minValue",
        "type": "uint256"
    }, {"indexed": true, "name": "toAddress", "type": "address"}],
    "name": "PunkOffered",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "name": "punkIndex", "type": "uint256"}, {
        "indexed": false,
        "name": "value",
        "type": "uint256"
    }, {"indexed": true, "name": "fromAddress", "type": "address"}],
    "name": "PunkBidEntered",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "name": "punkIndex", "type": "uint256"}, {
        "indexed": false,
        "name": "value",
        "type": "uint256"
    }, {"indexed": true, "name": "fromAddress", "type": "address"}],
    "name": "PunkBidWithdrawn",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "name": "punkIndex", "type": "uint256"}, {
        "indexed": false,
        "name": "value",
        "type": "uint256"
    }, {"indexed": true, "name": "fromAddress", "type": "address"}, {
        "indexed": true,
        "name": "toAddress",
        "type": "address"
    }],
    "name": "PunkBought",
    "type": "event"
}, {
    "anonymous": false,
    "inputs": [{"indexed": true, "name": "punkIndex", "type": "uint256"}],
    "name": "PunkNoLongerForSale",
    "type": "event"
}];

const WRAP_ADDRESS = "0xb7F7F6C52F2e2fdb1963Eab30438024864c313F6";
const WRAP_ABI = [{"inputs":[{"internalType":"address","name":"punkContract","type":"address"}],"payable":false,"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"address","name":"approved","type":"address"},{"indexed":true,"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"Approval","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"address","name":"operator","type":"address"},{"indexed":false,"internalType":"bool","name":"approved","type":"bool"}],"name":"ApprovalForAll","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"previousOwner","type":"address"},{"indexed":true,"internalType":"address","name":"newOwner","type":"address"}],"name":"OwnershipTransferred","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"account","type":"address"}],"name":"Paused","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"address","name":"proxy","type":"address"}],"name":"ProxyRegistered","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"from","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":true,"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"Transfer","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"account","type":"address"}],"name":"Unpaused","type":"event"},{"constant":false,"inputs":[{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"approve","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[{"internalType":"address","name":"owner","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"baseURI","outputs":[{"internalType":"string","name":"","type":"string"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"internalType":"uint256","name":"punkIndex","type":"uint256"}],"name":"burn","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"getApproved","outputs":[{"internalType":"address","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"operator","type":"address"}],"name":"isApprovedForAll","outputs":[{"internalType":"bool","name":"","type":"bool"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"internalType":"uint256","name":"punkIndex","type":"uint256"}],"name":"mint","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[],"name":"name","outputs":[{"internalType":"string","name":"","type":"string"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"owner","outputs":[{"internalType":"address","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"ownerOf","outputs":[{"internalType":"address","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[],"name":"pause","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[],"name":"paused","outputs":[{"internalType":"bool","name":"","type":"bool"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"proxyInfo","outputs":[{"internalType":"address","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"punkContract","outputs":[{"internalType":"address","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[],"name":"registerProxy","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[],"name":"renounceOwnership","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[{"internalType":"address","name":"from","type":"address"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"safeTransferFrom","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[{"internalType":"address","name":"from","type":"address"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"tokenId","type":"uint256"},{"internalType":"bytes","name":"_data","type":"bytes"}],"name":"safeTransferFrom","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[{"internalType":"address","name":"to","type":"address"},{"internalType":"bool","name":"approved","type":"bool"}],"name":"setApprovalForAll","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[{"internalType":"string","name":"baseUri","type":"string"}],"name":"setBaseURI","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[{"internalType":"bytes4","name":"interfaceId","type":"bytes4"}],"name":"supportsInterface","outputs":[{"internalType":"bool","name":"","type":"bool"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"symbol","outputs":[{"internalType":"string","name":"","type":"string"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"internalType":"uint256","name":"index","type":"uint256"}],"name":"tokenByIndex","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"uint256","name":"index","type":"uint256"}],"name":"tokenOfOwnerByIndex","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"tokenURI","outputs":[{"internalType":"string","name":"","type":"string"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"totalSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"internalType":"address","name":"from","type":"address"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"transferFrom","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[{"internalType":"address","name":"newOwner","type":"address"}],"name":"transferOwnership","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[],"name":"unpause","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"}];



async function writeOut(content) {
    try {
        return fs.writeFileSync('./artifacts/unclaimed-data.csv', content)
        //file written successfully
    } catch (err) {
        console.error(err)
    }
}
async function main() {
    const CIG_ADDRESS = "0xCB56b52316041A62B6b5D0583DcE4A8AE7a3C629";
    let CIG, ENS, PUNKS, WRAPPED;
    let domainResolver = {};
    let result = {};

    CIG = await hre.ethers.getContractAt(CIG_ABI, CIG_ADDRESS);
    PUNKS = await hre.ethers.getContractAt(PUNKS_ABI, PUNKS_ADDRESS);
    ENS = await hre.ethers.getContractAt(ReverseRecordsABI, ReverseRecordsAddress);
    WRAPPED = await hre.ethers.getContractAt(WRAP_ABI, WRAP_ADDRESS);

    domainResolver = {
        "cache": {},
        "setNames": async function (addresses) {
            let matched = 0;
            for (let i = 0; i < addresses.length; i++) {
                if (this.cache[addresses[i]]) {
                    matched++;
                }
            }
            if (matched === addresses.length) {
                return this.cache;
            }
            let result = await ENS.getNames(addresses);
            for (let i = 0; i < addresses.length; i++) {
                this.cache[addresses[i]] = result[i];
            }
            return this.cache;
        },
        "isCached": function (addr) {
            return addr in this.cache;
        },
        "name": function (addr) {
            if (this.cache.hasOwnProperty(addr)) {
                if (!this.cache[addr]) return addr;
                return this.cache[addr];
            }
            return addr;
        },
        "clear": function () {
            this.cache = null;
        }
    }

    for (let i = 0; i < 9999; i++) {
        let claimed = await CIG.isClaimed(i);
        if (claimed === true) continue;
        let owner = await PUNKS.punkIndexToAddress(i);
        if (owner.toLowerCase() === "0xb7f7f6c52f2e2fdb1963eab30438024864c313f6") continue;
        let name;

        if (!domainResolver.isCached(owner)) {
            domainResolver.setNames([owner]);
        }
        name = domainResolver.name(owner);

        if (name in result) {
            result[name] += 100000;
        } else {
            result[name] = 100000;
        }
        //console.log("claimed:" + claimed, " owner:" + name);
        console.log(i);

    }

    let wrapped_count = await WRAPPED.totalSupply();
    for (let i =0; i < wrapped_count; i++) {
        let punkID = await WRAPPED.tokenByIndex(i);
        let claimed = await CIG.isClaimed(punkID);
        if (claimed === true) continue;
        let owner = await WRAPPED.ownerOf(punkID);
        let name;

        if (!domainResolver.isCached(owner)) {
            domainResolver.setNames([owner]);
        }
        name = domainResolver.name(owner);

        if (name in result) {
            result[name] += 100000;
        } else {
            result[name] = 100000;
        }
        //console.log("claimed:" + claimed, " owner:" + name);
        console.log(i);
    }

    let csv = '';
    for (let user in result) {
        csv = csv + user +","+ result[user] + "\n";
    }
    //console.log(csv);
    await writeOut(csv);
    console.log("done");


}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });


