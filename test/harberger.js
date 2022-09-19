const {expect} = require("chai");
const {ContractFactory, utils, BigNumber} = require('ethers');

describe("Hamburgers", function () {
    let har;
    let owner, simp, elizabeth;

    let feth = utils.formatEther;
    let peth = utils.parseEther;
    const unlimited = BigNumber.from("2").pow(BigNumber.from("256")).sub(BigNumber.from("1"));

    let slogan = "hello world";
    let slogan32 = new Uint8Array(32);
    for (let i = 0; i < slogan.length; i++) {
        slogan32[i] = slogan.charCodeAt(i);
    }

    before(async function () {
        [owner, simp, elizabeth] = await ethers.getSigners();

        Harberger = await ethers.getContractFactory("Harberger");
        har = await Harberger.deploy(10, 5);
        await har.deployed();


    });

    describe("Harberger Full Test", function () {
        it("create deeds", async function () {
            //har.newDeed(0x266830230bf10A58cA64B7347499FD361a011a02, 6);
            //har.testtax(6);
        });
    });

});