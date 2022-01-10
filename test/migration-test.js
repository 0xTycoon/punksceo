/*
* This test needs to be run on a forked mainnet
*
* */
const {expect} = require("chai");
const {ContractFactory, utils, BigNumber} = require('ethers');

describe("Migration", function () {
    let CigToken;
    let cig;
    let OldCigToken;
    let oldcig;
    let PunkMock;
    let pm;
    let owner, simp, elizabeth;
    let PoolMock;
    let pt;
    let NFTMock;
    let nft, oldNft;
    let V2RouterMock;
    let v2;
    const BLOCK_REWARD = '5';
    const CEO_EPOCH_BLOCKS = 10;
    const CEO_AUCTION_BLOCKS = 5;
    const MIGRATION_EPOCHS = 2;
    let CEO_BUY_PRICE = '50000';
    let CEO_TAX_DEPOSIT = '5000';
    let CLAIM_AMOUNT = '100000';
    let MINT_SUPPLY = (parseInt(CLAIM_AMOUNT) * 10000) + '';
    let graffiti = "hello world";
    let graff32 = new Uint8Array(32);
    let feth = utils.formatEther;
    let peth = utils.parseEther;
    let ASSET_URL = "ipfs://2727838744/something/238374/";
    let MSV2 = '0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d'; //
    let OLD_CIG = '0x5a35a6686db167b05e2eb74e1ede9fb5d9cdb3e0';
    let oldCig;
    let OLD_NFT = '0x4aa51e8479ecb44c644c96e38c20b18fbc02da91';
    before(async function () {

        [owner, simp, elizabeth] = await ethers.getSigners();

        // deploy the punks mocking contract
        V2RouterMock = await ethers.getContractFactory("V2RouterMock");
        v2 = await V2RouterMock.deploy();
        await v2.deployed();

        PunkMock = await ethers.getContractFactory("PunkMock");
        pm = await PunkMock.deploy(owner.address);
        await pm.deployed();

        // deploy the pool mocking contract
        PoolMock = await ethers.getContractFactory("PoolTokenMock");
        pt = await PoolMock.deploy(owner.address);
        await pt.deployed();
        for (let i = 0; i < graffiti.length; i++) {
            graff32[i] = graffiti.charCodeAt(i);
        }

        // deploy the NFT contract
        NFTMock = await ethers.getContractFactory("NonFungibleCEO");
        nft = await NFTMock.deploy(ASSET_URL);
        await nft.deployed();
        // Deploy the new NFT contract
        CigToken = await ethers.getContractFactory("Cig");
        cig = await CigToken.deploy(
            100,
            utils.parseEther(BLOCK_REWARD),
            pm.address,
            CEO_EPOCH_BLOCKS,
            CEO_AUCTION_BLOCKS,
            utils.parseEther(CEO_BUY_PRICE),
            graff32,
            nft.address,
            v2.address,
            OLD_CIG,
            MIGRATION_EPOCHS
        );
        await cig.deployed();

        // tell the NFT contract about the cig token
        await nft.setCigToken(cig.address);
        //await nft.setBaseURI(ASSET_URL); // onlyCEO

        // test burning of keys
        await nft.renounceOwnership();

        await expect(nft.setBaseURI(ASSET_URL)).to.be.revertedWith('must be called by CEO');

        oldCig =  await hre.ethers.getContractAt("OldCig", OLD_CIG);
        console.log(await oldCig.totalSupply());

    });

    describe("Deployment", function () {

        it("Should be in migration state", async function () {
            expect(await cig.CEO_state()).to.be.equal("3");

            // 13974859 is the block we forked from
            let expected = 13974859 + (CEO_EPOCH_BLOCKS * MIGRATION_EPOCHS) + 5; // 5
            expect(await cig.lastRewardBlock()).to.be.equal(expected);

        })



    });

});

