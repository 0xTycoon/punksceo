const {expect} = require("chai");
const {ContractFactory, utils, BigNumber} = require('ethers');

describe("Hamburgers", function () {
    let burger, Harberger, PunkMock, punks, CigTokenMock, cig, ERC721Mock, nft1, nft2;
    let owner, simp, elizabeth;

    let feth = utils.formatEther;
    let peth = utils.parseEther;
    const unlimited = BigNumber.from("2").pow(BigNumber.from("256")).sub(BigNumber.from("1"));

    let slogan = "hello world";
    let graffiti32 = new Uint8Array(32);
    for (let i = 0; i < slogan.length; i++) {
        graffiti32[i] = slogan.charCodeAt(i);
    }

    before(async function () {
        [owner, simp, elizabeth] = await ethers.getSigners();

        // deploy cig mock and mint some CIG for ourselves
        CigTokenMock = await ethers.getContractFactory("CigTokenMock");
        cig = await CigTokenMock.deploy(owner.address);
        await cig.deployed();

        cig.mint(simp.address, peth("1000000"));
        cig.mint(owner.address, peth("10000000"));
        cig.mint(elizabeth.address, peth("1000000"));

        // deploy our punk mocking contract
        PunkMock = await ethers.getContractFactory("PunkMock");
        punks = await PunkMock.deploy(owner.address, simp.address, elizabeth.address);
        await punks.deployed();

        ERC721Mock = await ethers.getContractFactory("ERC721Mock");
        nft1 = await ERC721Mock.deploy(); // simulates a regular 721 nft
        await nft1.deployed();
        nft2 = await ERC721Mock.deploy();
        await nft2.deployed(); // simulates an ENS

        Harberger = await ethers.getContractFactory("Harberger");
        burger = await Harberger.deploy(
            10, // 10 blocks per epoch
            5, // change dutch auction every 5 blocks
            cig.address,
            nft2.address,
            punks.address
            );
        await burger.deployed();

        // approve cig
        await cig.approve(burger.address, unlimited);
        await cig.connect(simp).approve(burger.address, unlimited);
        await cig.connect(elizabeth).approve(burger.address, unlimited);

    });

    describe("Harberger Full Test", function () {
        it("create deeds", async function () {
            // should fail because we have not put the punk for sale
            await expect(burger.newDeed(
                punks.address, // a cryptopunk
                4513,
                peth("10000"),
                cig.address,
                10, // 1% tax,
                1000, // 100% to originator
            )).to.be.revertedWith("you are not the toAddress");

            expect (await punks.offerPunkForSaleToAddress(4513, 0, burger.address))
                .to.emit(punks, "PunkOffered");
             expect(await burger.newDeed(
                punks.address, // a cryptopunk
                4513,
                peth("10000"),
                cig.address,
                10,
                1000
            )).to.emit(burger, "NewDeed").withArgs(1);


            // sanity check
            expect(await burger.getApproved(1)).to.equal(burger.address);
            await expect( burger.getApproved(0)).to.be.revertedWith("index out of range");
            expect(await burger.isApprovedForAll(simp.address, burger.address)).to.equal(false);
            expect(await burger.tokenByIndex(0)).to.equal(1); // index starts from 0
            expect(await burger.totalSupply()).to.equal(1);
            expect(await burger.balanceOf(owner.address)).to.equal(1);

            // now simp's turn
            expect (await punks.connect(simp).offerPunkForSaleToAddress(4515, 0, burger.address))
                .to.emit(punks, "PunkOffered");
            expect (await punks.connect(simp).offerPunkForSaleToAddress(4519, 0, burger.address))
                .to.emit(punks, "PunkOffered");
            expect (await punks.connect(simp).offerPunkForSaleToAddress(4520, 0, burger.address))
                .to.emit(punks, "PunkOffered");
            expect(await burger.connect(simp).newDeed(
                punks.address, // a cryptopunk
                4515,
                peth("10000"),
                cig.address,
                10,
                1000
            )).to.emit(burger, "NewDeed").withArgs(2);
            expect(await burger.connect(simp).newDeed(
                punks.address, // a cryptopunk
                4519,
                peth("10000"),
                cig.address,
                10,
                1000
            )).to.emit(burger, "NewDeed").withArgs(3);
            expect(await burger.connect(simp).newDeed(
                punks.address, // a cryptopunk
                4520,
                peth("10000"),
                cig.address,
                10,
                1000
            )).to.emit(burger, "NewDeed").withArgs(4);

            // sanity check
            expect(await burger.balanceOf(simp.address)).to.equal(3);
            expect(await burger.tokenOfOwnerByIndex(simp.address, 0)).to.equal(2);
            expect(await burger.tokenOfOwnerByIndex(simp.address, 1)).to.equal(3);

        });

        it("buy deeds", async function () {
            await expect( burger.buyDeed(
                1,
                peth("15000"),
                peth("10000"),
                peth("5000"),
                graffiti32
            )).to.be.revertedWith("you already own it");

            console.log(await burger.tokenOfOwnerByIndex(simp.address, 0));
            console.log(await burger.tokenOfOwnerByIndex(simp.address, 1));
            console.log(await burger.tokenOfOwnerByIndex(simp.address, 2));

            // remove the middle item
            console.log("elizabeth buys #3, i=middle");
            expect(await burger.connect(elizabeth).buyDeed(
                3,
                peth("15000"),
                peth("10000"),
                peth("5000"),
                graffiti32
            )).to.emit(burger, "Takeover");

            expect(await burger.balanceOf(simp.address)).to.equal(2);
            console.log(await burger.tokenOfOwnerByIndex(simp.address, 0));
            console.log(await burger.tokenOfOwnerByIndex(simp.address, 1));

            // remove the last item
            console.log("elizabeth buys #4, i=last");
            expect(await burger.connect(elizabeth).buyDeed(
                4,
                peth("15000"),
                peth("10000"),
                peth("5000"),
                graffiti32
            )).to.emit(burger, "Takeover");

            expect(await burger.balanceOf(simp.address)).to.equal(1);
            console.log(await burger.tokenOfOwnerByIndex(simp.address, 0));

            console.log("elizabeth buys #2, i=remaining");
            expect(await burger.connect(elizabeth).buyDeed(
                2,
                peth("15000"),
                peth("10000"),
                peth("5000"),
                graffiti32
            )).to.emit(burger, "Takeover");

            expect(await burger.balanceOf(simp.address)).to.equal(0);
            await expect(burger.tokenOfOwnerByIndex(simp.address, 0)).to.be.revertedWith("index out of range");
            expect(await burger.balanceOf(elizabeth.address)).to.equal(3);

        });

        it("deposit tax", async function () {


        });
    });

});