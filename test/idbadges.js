const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const {expect} = require("chai");
const {ContractFactory, utils, BigNumber} = require('ethers');

//import { solidity } from "ethereum-waffle";
//chai.use(solidity);

//const helpers = require("@nomicfoundation/hardhat-network-helpers");
const unlimited = BigNumber.from("2").pow(BigNumber.from("256")).sub(BigNumber.from("1"));




describe("ID Badges", function () {
    let owner, simp, elizabeth, tycoon, degen, employee1, employee2, impersonatedSigner; // accounts
    let pool, Stogie, stogie, cig, cigeth, IDBadges, blocks; // contracts
    let feth = utils.formatEther;
    let peth = utils.parseEther;
    let badges, EmployeeIDBadges;
    const EXPIRED_ADDRESS = "0x0000000000000000000000000000000000000E0F";
    const EOA = "0xc43473fA66237e9AF3B2d886Ee1205b81B14b2C8"; // EOA that has ETH and CIG to impersonate
    const CIG_ADDRESS = "0xcb56b52316041a62b6b5d0583dce4a8ae7a3c629"; // cig on mainnet
    const CIGETH_SLP_ADDRESS = "0x22b15c7Ee1186A7C7CFfB2D942e20Fc228F6E4Ed";
    const ENS_ADDRESS = "0xc18360217d8f7ab5e7c516566761ea12ce7f9d72" // ENS token on mainnet
    const ZERO32 = ethers.utils.formatBytes32String("");
    before(async function () {
        // assuming we are at block 14148801

        [owner, simp, elizabeth, degen, employee1, employee2] = await ethers.getSigners();
        cig = await hre.ethers.getContractAt(CIG_ABI, CIG_ADDRESS);

        blocks = await hre.ethers.getContractAt(BLOCKS_ABI, "0xe91eb909203c8c8cad61f86fc44edee9023bda4d");

        /**
         0 Base,
         2 Cheeks,
         3 Blemish,
         1 Mouth,
         5 Neck,
         6 Beard,
         7 Earring,
         8 HeadTop1,
         9 HeadTop2,
         11 MouthProp,
         4 Eyes,
         10 Eyewear,
         12 Nose
         */

        await blocks.registerOrderConfig(
            [0,2,3,1,5,6,7,8,9,4,11,10,12]
        );

        //[owner, simp, elizabeth] = await ethers.getSigners();
        cigeth = await hre.ethers.getContractAt(SLP_ABI, CIGETH_SLP_ADDRESS);

        EmployeeIDBadges = await ethers.getContractFactory("EmployeeIDBadges");
        badges = await EmployeeIDBadges.deploy(
            CIG_ADDRESS,
            3, // epoch (blocks)
            1, // duration (number of epochs to wait)
            2, // grace period
            "0xb7f596579cd5d9ade583c90477ef1b5e2d47359e", // identicons
            "0x829e113C94c1acb6b1b5577e714E486bb3F86593", // punk blocks
            "0x4872BC4a6B29E8141868C3Fe0d4aeE70E9eA6735",  // barcode
            0 // layer order id
        );
        await badges.deployed();

        // deploy stogie
        Stogie = await ethers.getContractFactory("Stogie");
        stogie = await Stogie.deploy(
            CIG_ADDRESS, // cig on mainnet
            "0x22b15c7ee1186a7c7cffb2d942e20fc228f6e4ed", // Sushi SLP
            "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F", // sushi router
            "0xc0aee478e3658e2610c5f7a4a2e1777ce9e4f2ac", // sushi factory
            "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // uniswap router
            "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", // weth
            badges.address
        );
        await stogie.deployed();

        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [EOA],
        });
        tycoon = await ethers.provider.getSigner(EOA);

    owner.sendTransaction({
            to: EOA,
            value: ethers.utils.parseEther("10.0")
        });

        await badges.setStogie(stogie.address); // set the stogie address

    });

    it("init the id badges", async function () {

        /*
                await tycoon.sendTransaction({
                    to: "0x0000000000000000000000000000000000000000",
                    value: ethers.utils.parseEther("0.01"),
                });
        */

        let ts = Math.floor(Date.now() / 1000);


        /**
         * Here we assume that the block is 17294564
         * We harvest the CIGs first, withdraw SLP.
         *
         * Then the simp account deposits into Stogies with ETH
         * Then tycoon wraps SLP to stogies, minting an id
         */

        console.log("pending cig: " + await cig.connect(tycoon).pendingCig(EOA));
        expect(await cig.connect(tycoon).harvest()).to.emit(cig, 'Harvest');
        // withdraw our slp from staking
        expect(await cig.connect(tycoon).emergencyWithdraw()).to.emit(cig, 'EmergencyWithdraw');
        await cig.connect(tycoon).update();
        // approve stogie to take our cig
        expect(await cig.connect(tycoon).approve(stogie.address, unlimited)).to.emit(cig, 'Approval');
        // approve stogie to take our cig/eth slp
        expect(await cigeth.connect(tycoon).approve(stogie.address, unlimited)).to.emit(cig, 'Approval');
        let slpBal = await cigeth.connect(tycoon).balanceOf(EOA);
        console.log("cig/eth slp:" + feth(slpBal));
        console.log("cig:" + feth(await cig.connect(tycoon).balanceOf(EOA)));
        expect(await stogie.connect(simp).depositWithETH(
            1,
            BigNumber.from(ts+60),
            true,
            false, // do not mint id
            {value : peth("1")})).to.emit(stogie, 'Transfer');
        expect(await badges.balanceOf(simp.address)).to.equal("0"); // nothing minted for simp
        expect(await stogie.connect(tycoon).deposit(slpBal, true, true, false, 0, 0, ZERO32, ZERO32)).to.emit(stogie, 'Transfer'); // deposit stogies and mint badge for tycoon
        console.log("pending reward: " +  feth(await stogie.connect(tycoon).pendingCig(EOA)));
        expect(await badges.balanceOf(EOA)).to.equal("1"); // MINT 1 for tycoon
        // generate the badge url
        let badge = await badges.tokenURI(0);
        console.log(badge);

        /**
         * reduce the minStog to 15.5 then mint a badge using the simp account
         * then transfer the badge to tycoon.
         * Tycoon's average should change to 17.75, because (20 + 15.5) / 2 = 17.75
         * meanwhile, simp's should be 0
         */
        await badges.connect(owner).setMin(peth("15.5"));
        await expect(await badges.connect(simp).issueMeID()).to.emit(badges, "Transfer").withArgs("0x0000000000000000000000000000000000000000",  simp.address, 1); // MINT 1 for simp
        expect(await badges.balanceOf(simp.address)).to.equal("1");
        expect(await badges.totalSupply()).to.equal("2");
        console.log("tycoonA:"+await badges.connect(degen).balanceOf(EOA), " add  :"+EOA, " avgMinSTOG:", await badges.avgMinSTOG(EOA));
        await badges.connect(simp).transferFrom(simp.address, EOA, 1); // simp gave ID to tycoon
        expect(await badges.balanceOf(simp.address)).to.equal("0");
        expect(await badges.balanceOf(EOA)).to.equal("2"); // tycoon has 2
        let [a,b, c] = await badges.connect(tycoon).getStats(EOA);
        await expect(a[2]).to.equal(BigNumber.from("35500000000000000000")); // the sum
        //console.log(b);
        [a,b, c] = await badges.connect(tycoon).getStats(simp.address);
       // console.log(a); // todo average should be 0
        await expect(a[2]).to.equal(BigNumber.from("00000000000000000000"));

    });

    it("test expiry", async function () {
        // tycoon withdraws stogies.
        let [a,b, c] = await badges.connect(tycoon).getStats(EOA);
        await stogie.connect(tycoon).withdraw(a[6]); // tycoon rugs his own stogies

        // tycoon was sent some NFTs but doesn't have any stogies deposited. Oh no!

        await expect(badges.expire(1)).to.be.revertedWith("during grace period"); // cannot be expired just after transfer
        console.log("tycoon Befor expired:"+await badges.connect(degen).balanceOf(EOA), " add  :"+EOA, " avgMinSTOG:", await badges.avgMinSTOG(EOA));
        let cdata = await badges.badges( await badges.tokenOfOwnerByIndex(EOA, 0))
        console.log(cdata);
        cdata = await badges.badges( await badges.tokenOfOwnerByIndex(EOA, 1));
        console.log(cdata);
        await expect(await badges.expire(1)).to.emit(badges, "StateChanged");
        console.log("tycoon After expired:"+await badges.connect(degen).balanceOf(EOA), " add  :"+EOA, " avgMinSTOG:", await badges.avgMinSTOG(EOA));
        expect(await badges.balanceOf(simp.address)).to.equal("0"); // simp's token got yoinked
        expect(await badges.balanceOf(EXPIRED_ADDRESS)).to.equal("1");
        await expect(badges.reactivate(1)).to.be.revertedWith("not your token");

        await expect(badges.connect(tycoon).reactivate(1)).to.be.revertedWith("insert more STOG"); // cannot reactivate since no stogies
       // expect(await stogie.connect(elizabeth).wrapAndDeposit(slpBal, false)).to.emit(stogie, 'Transfer'); // load stogies
        let tx = {
            to: stogie.address,
            // Convert currency unit from ether to wei
            value: ethers.utils.parseEther("1")
        }

        // test the sending on ETH to get stogies
        expect(await elizabeth.sendTransaction(tx)).to.emit(stogie.address, "Transfer").withArgs(elizabeth.address, ethers.utils.parseEther("1")); // MINT 1 for elizabeth
        expect(await badges.totalSupply()).to.equal("3");
        [a,b, c] = await badges.connect(tycoon).getStats(elizabeth.address);
        expect(a[6]).to.be.equal(peth("1122.049524234448419428")); // 1122 stogies deposited
        expect(await badges.balanceOf(elizabeth.address)).to.equal("1");
        expect(await badges.balanceOf(EOA)).to.equal("1");

        await expect(badges.connect(degen).reclaim(1)).to.be.revertedWith("insert more STOG"); // fails because degen has no stog
        await expect(await stogie.connect(elizabeth).withdraw(peth("20"))); // withdraw 20 stog
        await expect(await stogie.connect(elizabeth).transfer(degen.address, peth("20")));//.to.emit(stogie, "Transfer");
        await expect(await stogie.connect(degen).deposit(peth("20"), false, false, false, 0, 0, ZERO32, ZERO32)).to.emit(stogie, "Deposit"); // deposit to the factory, do not mint

        await expect(badges.connect(degen).expire(1)).to.be.revertedWith("invalid state"); // already expired
        await expect(await badges.connect(degen).reclaim(1)).to.be.emit(badges, "StateChanged").withArgs(1, degen.address, 3, 1); // 3=Expired, 1=Active
        expect(await badges.balanceOf(degen.address)).to.equal("1");
        expect(await badges.balanceOf(EXPIRED_ADDRESS)).to.equal("0");
       // test reactivation. Degen withdraws, expiry is called, degen deposits and reactivates.
        await expect(await stogie.connect(degen).withdraw(peth("20"))).to.emit(stogie, "Withdraw");
        await expect(badges.expire(1)).to.be.revertedWith("during grace period");// under a grace period because recently reclaimed

        [a,b, c] = await badges.connect(tycoon).getStats(simp.address); // burn some time
        [a,b, c] = await badges.connect(tycoon).getStats(EXPIRED_ADDRESS); // burn some time
        //console.log(a);
        await expect(await badges.expire(1)).to.emit(badges, "StateChanged").withArgs(1, owner.address, 1, 2 ); // will go in State.PendingExpiry
        await expect(await stogie.connect(degen).deposit(peth("20"), false, false, false, 0, 0, ZERO32, ZERO32)).to.emit(stogie, "Deposit");
        await expect(await badges.connect(degen).reactivate(1)).to.be.emit(badges, "StateChanged").withArgs(1, degen.address, 2, 1);
        expect(await badges.balanceOf(degen.address)).to.equal("1");
        expect(await badges.balanceOf(EXPIRED_ADDRESS)).to.equal("0");
        //[a,b, c] = await badges.connect(degen).getStats(tycoon.address);
        //console.log(b);

        console.log("tycoon: "+await badges.connect(degen).balanceOf(EOA));
        console.log("liz: "+await badges.connect(degen).balanceOf(elizabeth.address));
        console.log("simp: "+await badges.connect(degen).balanceOf(simp.address));
        console.log("degen: "+await badges.connect(degen).balanceOf(degen.address));
        await expect(badges.connect(simp).issueMeID()).to.be.revertedWith("_to has already minted this pic");
    });

    it("test getBadges", async function () {
        let tx = {
            to: stogie.address,
            // Convert currency unit from ether to wei
            value: ethers.utils.parseEther("1")
        }

        // test the sending on ETH to get stogies
        expect(await employee1.sendTransaction(tx)).to.emit(stogie.address, "Transfer").withArgs(employee1.address, ethers.utils.parseEther("1"));
        expect(await employee2.sendTransaction(tx)).to.emit(stogie.address, "Transfer").withArgs(employee2.address, ethers.utils.parseEther("1"));

        expect(await badges.totalSupply()).to.equal("5");
        console.log("************** balanceA "+await badges.balanceOf(EOA) +" ********** avgMinSTOG:", await badges.avgMinSTOG(EOA));

// first transfer all badges to 1 address
        await badges.connect(degen)["safeTransferFrom(address,address,uint256)"](degen.address, EOA, await badges.connect(degen).tokenOfOwnerByIndex(degen.address, 0));
        console.log("************** balanceA "+await badges.balanceOf(EOA) +" ********** avgMinSTOG:", await badges.avgMinSTOG(EOA));
        await badges.connect(elizabeth)["safeTransferFrom(address,address,uint256)"](elizabeth.address, EOA, await badges.connect(elizabeth).tokenOfOwnerByIndex(elizabeth.address, 0));
        console.log("************** balanceB "+await badges.balanceOf(EOA) +" ********** avgMinSTOG:", await badges.avgMinSTOG(EOA));
        await badges.connect(employee1)["safeTransferFrom(address,address,uint256)"](employee1.address, EOA, await badges.connect(employee1).tokenOfOwnerByIndex(employee1.address, 0));
        console.log("************** balanceC "+await badges.balanceOf(EOA) +" ********** avgMinSTOG:", await badges.avgMinSTOG(EOA));
        await badges.connect(employee2)["safeTransferFrom(address,address,uint256)"](employee2.address, EOA, await badges.connect(employee2).tokenOfOwnerByIndex(employee2.address, 0));
        console.log("************** balanceD "+await badges.balanceOf(EOA) +" ********** avgMinSTOG:", await badges.avgMinSTOG(EOA));
        console.log("tycoon: "+await badges.connect(degen).balanceOf(EOA));

        console.log("tycoon: "+await badges.connect(degen).balanceOf(EOA), " add  :"+EOA, " avgMinSTOG:", await badges.avgMinSTOG(EOA));
        console.log("liz: "+await badges.connect(degen).balanceOf(elizabeth.address)+" add      :"+ elizabeth.address);
        console.log("simp: "+await badges.connect(degen).balanceOf(simp.address)+" add     :"+ simp.address);
        console.log("degen: "+await badges.connect(degen).balanceOf(degen.address)+" add    :"+ degen.address);
        console.log("employee1: "+await badges.connect(degen).balanceOf(employee1.address) +" add:"+ employee1.address);
        console.log("employee2: "+await badges.connect(degen).balanceOf(employee2.address)+" add:"+ employee2.address);

        //let [list, bal] = await badges.connect(tycoon).getBadges(EOA, 0, 30);
        //console.log("***********************"+bal);
        //console.log(list);

        // manually calc average
        let bal = await badges.balanceOf(EOA);
        let sum = BigNumber.from(0);
        for (let i = 0; i < bal; i++) {
            let c = await badges.badges( await badges.tokenOfOwnerByIndex(EOA, i));
            sum = sum.add(c.minStog);
            console.log(c.minStog);
        }
        console.log("///// Sum:", sum, " avg:"+  sum.div(bal));


    });

    it("test CEO governance", async function () {
        await expect ( badges.connect(tycoon).minSTOGChange(true)).to.be.revertedWith("need to be CEO");
        let max_spend = peth("10000000").add(peth('5000')); //stats[4].add(insufficient);
        let graff32 = new Uint8Array(32);
        let graffiti = "hello world";
        for (let i = 0; i < graffiti.length; i++) {
            graff32[i] = graffiti.charCodeAt(i);
        }
        expect(await cig.connect(tycoon).buyCEO(
            max_spend,
            peth("50000"),
            peth('5000'),
            4513, graff32)
        ).to.emit(cig, "NewCEO");
        await expect ( badges.connect(tycoon).minSTOGChange(true)).to.emit(badges, "MinSTOGChanged").withArgs(peth("15.887500000000000000"), peth("0.387500000000000000"));
        await expect ( badges.connect(tycoon).minSTOGChange(false)).to.be.revertedWith("wait more blocks");
        await expect ( badges.connect(tycoon).minSTOGChange(false)).to.be.revertedWith("wait more blocks");
        await expect ( badges.connect(tycoon).minSTOGChange(false)).to.be.revertedWith("wait more blocks");
        await expect ( badges.connect(tycoon).minSTOGChange(false)).to.to.emit(badges, "MinSTOGChanged").withArgs(peth("15.490312500000000000"), peth("0.397187500000000000"));
        //await expect ( badges.connect(tycoon).minSTOGChange(false)).to.be.revertedWith("wait more blocks");
        //await expect ( badges.connect(tycoon).minSTOGChange(false)).to.be.revertedWith("wait more blocks");
    });

    it("test everything else", async function () {
        // snapshots
        await expect(badges.connect(tycoon).snapshot(0)).to.be.revertedWith("id with this pic already minted");
        //console.log("Trrrrrrrrransfer");
        //console.log("ownerOf", await badges.ownerOf(1));
        await badges.connect(tycoon)["safeTransferFrom(address,address,uint256)"](EOA, elizabeth.address, 1);

        // burning curator

    });

});

const CIG_ABI =  [{"inputs":[{"internalType":"uint256","name":"_cigPerBlock","type":"uint256"},{"internalType":"address","name":"_punks","type":"address"},{"internalType":"uint256","name":"_CEO_epoch_blocks","type":"uint256"},{"internalType":"uint256","name":"_CEO_auction_blocks","type":"uint256"},{"internalType":"uint256","name":"_CEO_price","type":"uint256"},{"internalType":"bytes32","name":"_graffiti","type":"bytes32"},{"internalType":"address","name":"_NFT","type":"address"},{"internalType":"address","name":"_V2ROUTER","type":"address"},{"internalType":"address","name":"_OC","type":"address"},{"internalType":"uint256","name":"_migration_epochs","type":"uint256"},{"internalType":"address","name":"_MASTERCHEF_V2","type":"address"}],"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"address","name":"spender","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Approval","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"called_by","type":"address"},{"indexed":false,"internalType":"uint256","name":"reward","type":"uint256"}],"name":"CEODefaulted","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"price","type":"uint256"}],"name":"CEOPriceChange","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"ChefDeposit","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"ChefWithdraw","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"uint256","name":"punkIndex","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Claim","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"Deposit","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"EmergencyWithdraw","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"Harvest","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":true,"internalType":"uint256","name":"punk_id","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"new_price","type":"uint256"},{"indexed":false,"internalType":"bytes32","name":"graffiti","type":"bytes32"}],"name":"NewCEO","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"RevenueBurned","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"reward","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"downAmount","type":"uint256"}],"name":"RewardDown","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"reward","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"upAmount","type":"uint256"}],"name":"RewardUp","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"TaxBurned","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"TaxDeposit","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"from","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Transfer","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"Withdraw","type":"event"},{"inputs":[],"name":"CEO_price","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"CEO_punk_index","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"CEO_state","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"CEO_tax_balance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"The_CEO","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"accCigPerShare","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"admin","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"},{"internalType":"address","name":"","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_spender","type":"address"},{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"burnTax","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_max_spend","type":"uint256"},{"internalType":"uint256","name":"_new_price","type":"uint256"},{"internalType":"uint256","name":"_tax_amount","type":"uint256"},{"internalType":"uint256","name":"_punk_index","type":"uint256"},{"internalType":"bytes32","name":"_graffiti","type":"bytes32"}],"name":"buyCEO","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"cigPerBlock","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_punkIndex","type":"uint256"}],"name":"claim","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"}],"name":"claims","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"decimals","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"deposit","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"depositTax","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"emergencyWithdraw","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"farmers","outputs":[{"internalType":"uint256","name":"deposit","type":"uint256"},{"internalType":"uint256","name":"rewardDebt","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"farmersMasterchef","outputs":[{"internalType":"uint256","name":"deposit","type":"uint256"},{"internalType":"uint256","name":"rewardDebt","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_user","type":"address"}],"name":"getStats","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"},{"internalType":"address","name":"","type":"address"},{"internalType":"bytes32","name":"","type":"bytes32"},{"internalType":"uint112[]","name":"","type":"uint112[]"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"graffiti","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"harvest","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_punkIndex","type":"uint256"}],"name":"isClaimed","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"lastRewardBlock","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"lpToken","outputs":[{"internalType":"contract ILiquidityPoolERC20","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"masterchefDeposits","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"migrationComplete","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"name","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"address","name":"_user","type":"address"},{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_sushiAmount","type":"uint256"},{"internalType":"uint256","name":"_newLpAmount","type":"uint256"}],"name":"onSushiReward","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_user","type":"address"}],"name":"pendingCig","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"punks","outputs":[{"internalType":"contract ICryptoPunk","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"renounceOwnership","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"rewardDown","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"rewardUp","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"rewardsChangedBlock","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"contract ILiquidityPoolERC20","name":"_addr","type":"address"}],"name":"setPool","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_price","type":"uint256"}],"name":"setPrice","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"setReward","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_startBlock","type":"uint256"}],"name":"setStartingBlock","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"stakedlpSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"symbol","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"taxBurnBlock","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"totalSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"transfer","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_from","type":"address"},{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"transferFrom","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"unwrap","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"update","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"address","name":"_user","type":"address"}],"name":"userInfo","outputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"uint256","name":"depositAmount","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"wBal","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"withdraw","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"wrap","outputs":[],"stateMutability":"nonpayable","type":"function"}];

const SLP_ABI = [{"inputs":[],"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"address","name":"spender","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Approval","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount0","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1","type":"uint256"},{"indexed":true,"internalType":"address","name":"to","type":"address"}],"name":"Burn","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount0","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1","type":"uint256"}],"name":"Mint","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount0In","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1In","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount0Out","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1Out","type":"uint256"},{"indexed":true,"internalType":"address","name":"to","type":"address"}],"name":"Swap","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint112","name":"reserve0","type":"uint112"},{"indexed":false,"internalType":"uint112","name":"reserve1","type":"uint112"}],"name":"Sync","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"from","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Transfer","type":"event"},{"inputs":[],"name":"DOMAIN_SEPARATOR","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"MINIMUM_LIQUIDITY","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"PERMIT_TYPEHASH","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"},{"internalType":"address","name":"","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"burn","outputs":[{"internalType":"uint256","name":"amount0","type":"uint256"},{"internalType":"uint256","name":"amount1","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"decimals","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"factory","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"getReserves","outputs":[{"internalType":"uint112","name":"_reserve0","type":"uint112"},{"internalType":"uint112","name":"_reserve1","type":"uint112"},{"internalType":"uint32","name":"_blockTimestampLast","type":"uint32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_token0","type":"address"},{"internalType":"address","name":"_token1","type":"address"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"kLast","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"mint","outputs":[{"internalType":"uint256","name":"liquidity","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"name","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"nonces","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"},{"internalType":"uint256","name":"deadline","type":"uint256"},{"internalType":"uint8","name":"v","type":"uint8"},{"internalType":"bytes32","name":"r","type":"bytes32"},{"internalType":"bytes32","name":"s","type":"bytes32"}],"name":"permit","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"price0CumulativeLast","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"price1CumulativeLast","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"skim","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amount0Out","type":"uint256"},{"internalType":"uint256","name":"amount1Out","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"bytes","name":"data","type":"bytes"}],"name":"swap","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"symbol","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"sync","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"token0","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"token1","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"totalSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"}],"name":"transfer","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"from","type":"address"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"}],"name":"transferFrom","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"}];

const BLOCKS_ABI = [{"inputs":[],"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"","type":"address"},{"indexed":false,"internalType":"uint32","name":"","type":"uint32"},{"indexed":false,"internalType":"string","name":"","type":"string"}],"name":"NewBlock","type":"event"},{"inputs":[],"name":"abort","outputs":[],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"name":"blockL","outputs":[{"internalType":"bytes","name":"","type":"bytes"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"name":"blockS","outputs":[{"internalType":"bytes","name":"","type":"bytes"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"}],"name":"blockToLayer","outputs":[{"internalType":"enum PunkBlocks.Layer","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"name":"blocksInfo","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_fromID","type":"uint256"},{"internalType":"uint256","name":"_count","type":"uint256"}],"name":"getBlocks","outputs":[{"components":[{"internalType":"enum PunkBlocks.Layer","name":"layer","type":"uint8"},{"internalType":"bytes","name":"blockL","type":"bytes"},{"internalType":"bytes","name":"blockS","type":"bytes"}],"internalType":"struct PunkBlocks.Block[]","name":"","type":"tuple[]"},{"internalType":"uint32","name":"","type":"uint32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint32","name":"","type":"uint32"}],"name":"index","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes32","name":"_id","type":"bytes32"}],"name":"info","outputs":[{"internalType":"enum PunkBlocks.Layer","name":"","type":"uint8"},{"internalType":"uint16","name":"","type":"uint16"},{"internalType":"uint16","name":"","type":"uint16"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"nextConfigId","outputs":[{"internalType":"uint32","name":"","type":"uint32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"nextId","outputs":[{"internalType":"uint32","name":"","type":"uint32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint32","name":"","type":"uint32"},{"internalType":"enum PunkBlocks.Layer","name":"","type":"uint8"}],"name":"orderConfig","outputs":[{"internalType":"uint16","name":"","type":"uint16"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes","name":"_dataL","type":"bytes"},{"internalType":"bytes","name":"_dataS","type":"bytes"},{"internalType":"uint8","name":"_layer","type":"uint8"},{"internalType":"string","name":"_name","type":"string"}],"name":"registerBlock","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"enum PunkBlocks.Layer[]","name":"_order","type":"uint8[]"}],"name":"registerOrderConfig","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"seal","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint32[]","name":"_ids","type":"uint32[]"},{"internalType":"uint16","name":"_x","type":"uint16"},{"internalType":"uint16","name":"_y","type":"uint16"},{"internalType":"uint16","name":"_size","type":"uint16"},{"internalType":"uint32","name":"_orderID","type":"uint32"}],"name":"svgFromIDs","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes32[]","name":"_attributeKeys","type":"bytes32[]"},{"internalType":"uint16","name":"_x","type":"uint16"},{"internalType":"uint16","name":"_y","type":"uint16"},{"internalType":"uint16","name":"_size","type":"uint16"},{"internalType":"uint32","name":"_orderID","type":"uint32"}],"name":"svgFromKeys","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"string[]","name":"_attributeNames","type":"string[]"},{"internalType":"uint16","name":"_x","type":"uint16"},{"internalType":"uint16","name":"_y","type":"uint16"},{"internalType":"uint16","name":"_size","type":"uint16"},{"internalType":"uint32","name":"_orderID","type":"uint32"}],"name":"svgFromNames","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_tokenID","type":"uint256"},{"internalType":"uint16","name":"_x","type":"uint16"},{"internalType":"uint16","name":"_y","type":"uint16"},{"internalType":"uint16","name":"_size","type":"uint16"},{"internalType":"uint32","name":"_orderID","type":"uint32"}],"name":"svgFromPunkID","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"value","type":"uint256"}],"name":"toString","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"pure","type":"function"}]