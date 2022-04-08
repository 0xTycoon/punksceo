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

    function sleep(ms) {
        return new Promise((resolve) => {
            setTimeout(resolve, ms);
        });
    }

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
            1,  // claim days how many days the CEO has to claim the bribe
            5); // duration eg 86400 (seconds in a day)
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
                owner.address, // target
                4513, // punk id
                peth("100000"), // amount
                0, // index of bribesProposed
                20 // expiredBribes (will be ignored)
            )).to.emit(bribes, "New")
                .withArgs(1, peth("100000"), owner.address, 4513);

            // let's check state
            let ret, proposed, expired, bribe;
            [ret, proposed, expired, bribe] = await bribes.getInfo(
                owner.address, 1);
            expect(proposed[0]).to.be.equal("1");
            expect(proposed[1]).to.be.equal("0");

            // punk id incorrect
            await expect ( bribes.newBribe(
                owner.address, // target
                2513, // punk id incorrect
                peth("100000"), // amount
                0, // index of bribesProposed
                20 // expiredBribes (will be ignored)
            )).to.be.revertedWith("punkID not owned by target");

            // punk id incorrect
            await expect ( bribes.newBribe(
                owner.address, // target
                10000, // punk id incorrect
                peth("100000"), // amount
                0, // index of bribesProposed
                20 // expiredBribes (will be ignored)
            )).to.be.revertedWith("invalid _punkID");

            // amount incorrect
            await expect ( bribes.newBribe(
                owner.address, // target
                4513, // punk id
                peth("99999"), // amount incorrect
                0, // index of bribesProposed
                20 // expiredBribes (will be ignored)
            )).to.be.revertedWith("not enough cig");

            // nothing is expired yet
            await expect ( bribes.newBribe(
                owner.address, // target
                4513, // punk id
                peth("100000"), // amount
                0, // index of bribesProposed
                1 // expiredBribes (will be ignored) - incorrect, there is nothing expired yet
            )).to.be.revertedWith("cannot expire");

            await sleep(2000);

            // i = 0, but there is a proposal there, so we cannot newBribe
            await expect ( bribes.newBribe(
                owner.address, // target
                4513, // punk id
                peth("100000"), // amount
                0, // index of bribesProposed
                20 // expiredBribes (will be ignored)
            )).to.be.revertedWith("bribesProposed at _i not empty");

            expect ( await bribes.newBribe(
                owner.address, // target
                4513, // punk id
                peth("100000"), // amount
                0, // index of bribesProposed
                0 // expiredBribes (will be ignored)
            )).to.emit( bribes, "Expired")
                .to.emit(bribes, "New");

            [ret, proposed, expired, bribe] = await bribes.getInfo(
                owner.address, 1);
            expect(expired[0]).to.be.equal("1"); // proposal 1 expired
            expect(proposed[0]).to.be.equal("2"); // prposal 2 is the new proposal

            //console.log(proposed);
        });

        it("increase bribe", async function () {
            expect (await bribes.increase(0, 2, peth("100000")))
                .to.emit(bribes, "Increased");

            await expect (bribes.increase(10, 2, peth("100000")))
                .to.be.revertedWith("no such bribe active");

            await expect (bribes.increase(0, 2, peth("0")))
                .to.be.revertedWith("need to send cig");

        });

        it("accept bribe", async function () {
            expect(await bribes.accept(0, 2))
                .to.emit(bribes, "Accepted").withArgs(2);
            let ret, proposed, expired, bribe;
            [ret, proposed, expired, bribe] = await bribes.getInfo(
                owner.address, 1);
            expect(proposed[0]).to.be.equal("0"); // should be cleared
            expect(ret[1]).to.be.equal("2");
            expect(bribe.raised).to.be.equal(peth("200000"));

            // cannot accept another bribe since current not PaidOut
            await expect(bribes.accept(0, 2)).to.be.revertedWith("acceptedBribe not PaidOut");

        });

        // assuming 2 seconds since updated
        it("payout bribe", async function () {

            let ret, proposed, expired, bribe;
            [ret, proposed, expired, bribe] = await bribes.getInfo(
                owner.address, 1);

            let perSec = bribe.raised.div(ret[4]);
            let elapsedSec = ret[3].sub(bribe.updatedAt);

            console.log("claimable:::: " + elapsedSec.mul(perSec) + " elapsed:" + elapsedSec, " per sec:" + feth(perSec)); // next second, it will be double.

            expect (await bribes.payout()).to.emit(bribes, "Paid").withArgs("2", peth("80000"));
            expect (await bribes.payout()).to.emit(bribes, "Paid").withArgs("2", peth("40000"));


        })

    });

});