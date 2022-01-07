const {expect} = require("chai");
const {ContractFactory, utils, BigNumber} = require('ethers');

describe("NewCig", function () {
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
    let CEO_BUY_PRICE = '50000';
    let CEO_TAX_DEPOSIT = '5000';
    let CLAIM_AMOUNT = '100000';
    let MINT_SUPPLY = (parseInt(CLAIM_AMOUNT) * 10000) + '';
    let graffiti = "hello world";
    let graff32 = new Uint8Array(32);
    let feth = utils.formatEther;
    let peth = utils.parseEther;
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



        // tell the NFT contract about the cig token
        await nft.setCigToken(cig.address);
        //await nft.setBaseURI(ASSET_URL); // onlyCEO

        // test burning of keys
        await nft.renounceOwnership();

        await expect(nft.setBaseURI(ASSET_URL)).to.be.revertedWith('must be called by CEO');

        // Deploy the old contract

        oldNft = await NFTMock.deploy(ASSET_URL);
        await oldNft.deployed();

        OldCigToken = await ethers.getContractFactory("OldCig");
        oldCig = await CigToken.deploy(
            100,
            utils.parseEther(BLOCK_REWARD),
            pm.address,
            CEO_EPOCH_BLOCKS,
            CEO_AUCTION_BLOCKS,
            utils.parseEther(CEO_BUY_PRICE),
            MSV2,
            graff32,
            oldNft.address,
            v2.address
        );
        await cig.deployed();

        // tell the NFT contract about the cig token
        await oldNft.setCigToken(cig.address);
        //await nft.setBaseURI(ASSET_URL); // onlyCEO

        // test burning of keys
        await oldNft.renounceOwnership();

        await expect(oldNft.setBaseURI(ASSET_URL)).to.be.revertedWith('must be called by CEO');

        // deploy the NFT contract

        NFTMock = await ethers.getContractFactory("NonFungibleCEO");
        nft = await NFTMock.deploy(ASSET_URL);
        await nft.deployed();
        // Deploy the new NFT contract
        CigToken = await ethers.getContractFactory("Cig");
        old = await CigToken.deploy(
            100,
            utils.parseEther(BLOCK_REWARD),
            pm.address,
            CEO_EPOCH_BLOCKS,
            CEO_AUCTION_BLOCKS,
            utils.parseEther(CEO_BUY_PRICE),
            graff32,
            nft.address,
            v2.address,
            oldcig.address
        );
        await cig.deployed();


    });

    describe("Deployment", function () {



    });

});