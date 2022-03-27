/**
 * Tests for the bribes.sol contract
 */
const {expect} = require("chai");
const {ContractFactory, utils, BigNumber} = require('ethers');

describe("Bribes", function () {
    let CigTokenMock;
    let cig;
    let PunkMock;
    let pm;
    let Bribes;
    let bribes;

    let owner, simp, elizabeth;

    let feth = utils.formatEther;
    let peth = utils.parseEther;
    const unlimited = BigNumber.from("2").pow(BigNumber.from("256")).sub(BigNumber.from("1"));

    before(async function () {
        [owner, simp, elizabeth] = await ethers.getSigners();

        CigTokenMock = await ethers.getContractFactory("CigTokenMock");
        cig = await CigTokenMock.deploy(owner.address);
        await cig.deployed();

        cig.mint(simp.address, peth("1000000"));
        cig.mint(owner.address, peth("1000000"));
        cig.mint(elizabeth.address, peth("1000000"));

        PunkMock = await ethers.getContractFactory("PunkMock");
        pm = await PunkMock.deploy(owner.address);
        await pm.deployed();

        Bribes = await ethers.getContractFactory("Bribes");
        bribes = await Bribes.deploy(
            cig.address,
            pm.address,
            1,
            5);
        await bribes.deployed();
    });

    describe("Bribes Full Test", function () {

        it("set the price correctly", async function () {

            expect (await bribes.updateMinAmount()).to.emit(bribes, "MinAmount")
                .withArgs(peth("100000"));
        });

        it("create some new bribes", async function () {

            await cig.approve(bribes.address, unlimited);


            expect (await bribes.newBribe(
                owner.address,
                4513,
                peth("100000"),
                0,
                20
            )).to.emit(bribes, "New");
        });

    });

});