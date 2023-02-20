/**
 * Treasury test. This test is designed to run on forked-mainnet
 * Eg. in the network setting, place this:
 * this object the "networks" object of the json config
 *         hardhat: {
 *             forking: {
 *                 url: "https://eth-mainnet.alchemyapi.io/v2/API-KEY",
 *                 //blockNumber: 14487179 // if you want to lock to a specific block
 *             }
 *         }
 */
const {anyValue} = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const {expect} = require("chai");
const {ContractFactory, utils, BigNumber} = require('ethers');

//import { solidity } from "ethereum-waffle";
//chai.use(solidity);
// ForeverMarketV2: commission cannot be greater than 3%
//const helpers = require("@nomicfoundation/hardhat-network-helpers");
const unlimited = BigNumber.from("2").pow(BigNumber.from("256")).sub(BigNumber.from("1"));