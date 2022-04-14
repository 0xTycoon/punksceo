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
        cig.mint(owner.address, peth("10000000"));
        cig.mint(elizabeth.address, peth("1000000"));

        PunkMock = await ethers.getContractFactory("PunkMock");
        pm = await PunkMock.deploy(owner.address);
        await pm.deployed();

        Bribes = await ethers.getContractFactory("Bribes");
        bribes = await Bribes.deploy(
            cig.address,
            pm.address,
            1,  // claim days how many days the CEO has to claim the bribe
            5,
            0
            ); // duration eg 86400 (seconds in a day)
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
                4513, // punk id
                peth("100000"), // amount
                0, // index of bribesProposed
                20 // expiredBribes (will be ignored)
            )).to.emit(bribes, "New")
                .withArgs(1, peth("100000"), owner.address, 4513);

            // let's check state
            let ret, proposed, expired, bribe;
            [ret, proposed, expired, bribe] = await bribes.getInfo(
                owner.address);
            expect(proposed[0]).to.be.equal("1");
            expect(proposed[1]).to.be.equal("0");

            // punk id incorrect
            await expect ( bribes.newBribe(
                10000, // punk id incorrect
                peth("100000"), // amount
                0, // index of bribesProposed
                20 // expiredBribes (will be ignored)
            )).to.be.revertedWith("invalid _punkID");

            // amount incorrect
            await expect ( bribes.newBribe(
                4513, // punk id
                peth("99999"), // amount incorrect
                0, // index of bribesProposed
                20 // expiredBribes (will be ignored)
            )).to.be.revertedWith("not enough cig");

            // nothing is expired yet
            await expect ( bribes.newBribe(
                4513, // punk id
                peth("100000"), // amount
                0, // index of bribesProposed
                1 // expiredBribes (will be ignored) - incorrect, there is nothing expired yet
            )).to.be.revertedWith("cannot expire");

            await sleep(2000);

            // i = 0, but there is a proposal there, so we cannot newBribe
            await expect ( bribes.newBribe(
                4513, // punk id
                peth("100000"), // amount
                0, // index of bribesProposed
                20 // expiredBribes (will be ignored)
            )).to.be.revertedWith("bribesProposed at _i not empty");

            expect ( await bribes.newBribe(
                4513, // punk id
                peth("100000"), // amount
                0, // index of bribesProposed
                0 // expiredBribes (will be ignored)
            )).to.emit( bribes, "Expired")
                .to.emit(bribes, "New");

            [ret, proposed, expired, bribe] = await bribes.getInfo(
                owner.address);
            expect(expired[0]).to.be.equal("1"); // proposal 1 expired
            expect(proposed[0]).to.be.equal("2"); // proposal 2 is the new proposal

            // populate the remaining slots

            let id = 3;
            for (let i = 1; i < 20; i++) {
                console.log("populate:" + i);
                if (i === 10) continue;
                expect (await bribes.newBribe(
                    i+4000, // punk id
                    peth("100000"), // amount
                    i, // index of bribesProposed
                    20 // expiredBribes (will be ignored)
                )).to.emit(bribes, "New")
                    .withArgs(id, peth("100000"), owner.address, i+4000);
                id++;
            }
            [ret, proposed, expired, bribe] = await bribes.getInfo(
                owner.address);
            // by now we should have `expired[0] == 1`
            // and `proposed` all populated with id randing from 2 .. 21
            // with `proposed[10]` being empty
            console.log(proposed);
        });

        it("increase bribe", async function () {
            expect (await bribes.increase(0, 2, peth("100000")))
                .to.emit(bribes, "Increased");

            await expect (bribes.increase(10, 2, peth("100000")))
                .to.be.revertedWith("no such bribe active");

            await expect (bribes.increase(0, 2, peth("0")))
                .to.be.revertedWith("not enough cig");

            await cig.connect(elizabeth).approve(bribes.address, unlimited);
            expect (await bribes.connect(elizabeth).increase(4, 6, peth("100000"))).to.emit(bribes, "Increased");

        });

        it("accept bribe", async function () {
            expect(await bribes.accept(0, 2))
                .to.emit(bribes, "Accepted").withArgs(2);
            let ret, proposed, expired, bribe;
            [ret, proposed, expired, bribe] = await bribes.getInfo(
                owner.address);
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
                owner.address);
            let perSec = bribe.raised.div(ret[3]);
            let elapsedSec = ret[2].sub(bribe.updatedAt);

            console.log("claimable:::: " + elapsedSec.mul(perSec) + " elapsed:" + elapsedSec, " per sec:" + feth(perSec)); // next second, it will be double.

            await sleep(1000);

            expect (await bribes.payout()).to.emit(bribes, "Paid").withArgs("2", peth("80000"));

            await sleep(3000);

            expect (await bribes.payout()).to.emit(bribes, "Paid").withArgs("2", peth("40000"));


        });

        it("refund expired bribe", async function () {

            let ret, proposed, expired, bribe;
            [ret, proposed, expired, bribe] = await bribes.getInfo(
                owner.address);
            expect(expired[0]).to.be.equal(1);
           // console.log(expired);

            expect(await bribes.refund(20, 0, 1))
                .to.emit(bribes, "Refunded").withArgs(1, peth("100000"), owner.address)
                .to.emit(bribes, "Defunct");
        });

        it("set slogan", async function () {
            let slogan = "hello world";
            let slogan32 = new Uint8Array(32);
            for (let i = 0; i < slogan.length; i++) {
                slogan32[i] = slogan.charCodeAt(i);
            }

            expect(await bribes.setSlogan(3, slogan32)).to.emit(bribes, "Slogan");
        });

        it("test expire", async function () {
            let ret, proposed, expired, bribe, data, balances;

            [ret, proposed, expired, bribe, data, balances] = await bribes.getInfo(
                owner.address);
            let id = proposed[4];
/*
todo: this ill increase expire, move uo
            await cig.connect(elizabeth).approve(bribes.address, unlimited);
            expect (await bribes.connect(elizabeth).increase(4, 6, peth("100000"))).to.emit(bribes, "Increased");
*/
            expect(await bribes.expire(4, 4)).to.emit(bribes, "Expired")
                .to.emit(bribes, "Refunded").withArgs(
                    6,
                    peth("100000"),
                    owner.address);

            [ret, proposed, expired, bribe, data, balances] = await bribes.getInfo(
                owner.address);

            expect(data[24].state).to.be.equal(2);

            expect(await bribes.connect(elizabeth).refund(20, 4, 6)).to.emit(bribes, "Refunded")
                .to.emit(bribes, "Defunct");

        });




    });

});