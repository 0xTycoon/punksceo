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

        console.log("tycoon: "+await badges.connect(degen).balanceOf(EOA));
        console.log("liz: "+await badges.connect(degen).balanceOf(elizabeth.address)+" add      :"+ elizabeth.address);
        console.log("simp: "+await badges.connect(degen).balanceOf(simp.address)+" add     :"+ simp.address);
        console.log("degen: "+await badges.connect(degen).balanceOf(degen.address)+" add    :"+ degen.address);
        console.log("employee1: "+await badges.connect(degen).balanceOf(employee1.address) +" add:"+ employee1.address);
        console.log("employee2: "+await badges.connect(degen).balanceOf(employee2.address)+" add:"+ employee2.address);



    });

    it("test init", async function() {

        let atts = {};
        let Attribute = function(a, b) {
            return [a, b];
        }
        atts["0x398534927262d4f6993396751323ddd3e8326784a8e9a4808f17b99e6693835e"] = Attribute(false, "Stogie"); // 11
        atts["0x27dfd5e48f41fe8c82fecc41af933800fe5a5af6d9315a88932b9fb36d94a138"] = Attribute(false, "Headset"); // 7
        atts["0x550aa6da33a6eca427f83a70c2510cbc3c8bdb8a1ce5e5c3a32b2262f97c4aa1"] = Attribute(false, "Employee Cap"); // 9
        atts["0xd3ce42d23c6ec3bb95bfdee3de4e8d42889817871544fc9a07f05e4a2d21123e"] = Attribute(false, "Earbuds"); // 9
        atts["0x975e45b489dc6726c2a27eb784068ec791a22cf46fb780ced5e6b2083f32ebc3"] = Attribute(false, "Headphones Red"); // 9
        atts["0x421c9c08478a3dfb8a098fbef56342e7e0b53239aaa40dd2d56951cc6c178d35"] = Attribute(false, "Headphones Yellow"); // 9
        atts["0xaffb8a29fc5ed315e2a1103abc528d4f689c8365b54b17538f96e6bcae365633"] = Attribute(false, "Gas Mask"); // 11
        atts["0x314ff09b8866e566e22c7bf1fe4227185bc37e1167a84aaf299f5e016ca2ea7b"] = Attribute(false, "Goggles"); // 10
        atts["0xe5fd4286f4fc4347131889d24238df4b5ba8d8d4985cbd9cb30d447ec14cbb2f"] = Attribute(false, "Pen"); // 7
        atts["0xaeae7be74009ff61e63109240ea8e00b3bd6d166bf8a7f6584f64ff75e783f09"] = Attribute(false, "Pencil"); // 10
        atts["0x1cc630fd6d4fff8ca66aacb5acdba26a0a14ce5fd8f9cb60b002a153d1582b4e"] = Attribute(false, "Red Hat"); // 8
        atts["0xbbb91da98e74857ed34286d7efaf04751ac3f4d7081d62a0aa3b09278b5ee55a"] = Attribute(false, "Yellow Hat"); // 8
        atts["0x3fbda43b0bda236b4f6f6dba8b7052381641b3d92ce4b49b4a2e9be390980019"] = Attribute(false, "White Hat"); // 8
        atts["0x10214dd24c8822f95b3061229664e567e7da89d1f8a408179e12bf38be2c1430"] = Attribute(false, "Suit"); // 5
        atts["0xb52fd5c8112bb81b2c05dd854ac28867bf72fd52124cb27aee3de68a19c87812"] = Attribute(false, "Suit Black"); // 5
        atts["0xd7a861eff7c9242c2fc79148cdb44128460adae80afe1ba79c2d1eae290fb883"] = Attribute(true, "Bot"); // 0
        atts["0x7d3615eb6acf9ca19e31084888916f38df240bce4009857da690e4681bf8d4b0"] = Attribute(true, "Botina"); // 0
        atts["0x18a26173165d296055f2dfd8a12afc0a3e85434dd9d3f9c3ddd1eabc37ff56bc"] = Attribute(true, "Killer Bot"); // 0
        atts["0xb93c33f3b6e2e6aef9bd03b9ed7a064ed00f8306c06dfc93c76ae30db7a3f2b4"] = Attribute(true, "Killer Botina"); // 0
        atts["0x9242f3766d6363a612c9e88734e9c5667f4c82e07d00b794481f5b41b97047e8"] = Attribute(true, "Green Alien"); // 0
        atts["0x0c924a70f72135432a52769f20962602647a5b6528675c14bb318eaf4cbb2753"] = Attribute(true, "Green Alienette"); // 0
        atts["0xcd6f6379578617fc2da9c1d778e731bebaa21e9be1ed7265963ec43076d17a10"] = Attribute(true, "Blue Ape"); // 0
        atts["0x53f8bd0b36b2d3d9abc80e02d6fe9ed6a07068216cd737604c0c36ac60f458dc"] = Attribute(true, "Alien 2"); // 0
        atts["0xeca5ecd41019c8240974e9473044bf1a01598e7c650939425f53f561e959ec46"] = Attribute(true, "Alien 3"); // 0
        atts["0x061c5772160bfea6296a0317f6eff655398285ab18dbe89497436563445eeddc"] = Attribute(true, "Alien 4"); // 0
        atts["0x224b0f8059a7c50a19036c71e7500fd115adfd3af915c8d6d6639248c6e41283"] = Attribute(true, "Alien 5"); // 0
        atts["0xfb3556140e6f92df2d04796b8d8c5f6732abf43c07eb7034a90672cd4f9af372"] = Attribute(true, "Alien 6"); // 0
        atts["0xe9986a150e097f2cadc995279f34846ae9786b8ce35070b152f819d7a18d7760"] = Attribute(true, "Alienette 2"); // 0
        atts["0x0a215113c1e36c8cf69812b89dd912e3e2f1d70ab8c7691e0439a002d772f56d"] = Attribute(true, "Alienette 3"); // 0
        atts["0xac4fc861f4029388de1fa709cb865f504fb3198a6bf4dad71ff705a436c406c2"] = Attribute(true, "Alienette 4"); // 0
        atts["0xbefcd0e4ecf58c1d5e2a435bef572fca90d5fcedf6e2e3c1eb2f12b664d555a4"] = Attribute(true, "Alienette 5"); // 0
        atts["0x54526cc56c302d9d091979753406975ad06ca6a58c7bea1395ae25350268ab36"] = Attribute(true, "Alienette 6"); // 0
        atts["0xffa2b3215eb937dd3ebe2fc73a7dd3baa1f18b9906d0f69acb3ae76b99130ff7"] = Attribute(true, "Pink Ape"); // 0
        atts["0x46151bb75270ac0d6c45f21c75823f7da7a0c0281ddede44d207e1242e0a83f6"] = Attribute(true, "Male 5"); // 0
        atts["0xef8998f2252b6977b3cc239953db2f5fbcd066a5d454652f5107c59239265884"] = Attribute(true, "Male 6"); // 0
        atts["0x606da1a8306113f266975d1d05f6deed98d3b6bf84674cc69c7b1963cdc3ea86"] = Attribute(true, "Male 7"); // 0
        atts["0x804b2e3828825fc709d6d2db6078f393eafdcdedceae3bdb9b36e3c81630dd5e"] = Attribute(true, "Apette"); // 0
        atts["0x54354de4503fcf83c4214caefd1d4814c0eaf0ce462d1783be54ff9f952ec542"] = Attribute(true, "Female 5"); // 0
        atts["0x8a643536421eae5a22ba595625c8ba151b3cc48f2a4f86f9671f5c186b027ceb"] = Attribute(true, "Female 6"); // 0
        atts["0x4426d573f2858ebb8043f7fa39e34d1441d9b4fa4a8a8aa2c0ec0c78e755df0e"] = Attribute(true, "Female 7"); // 0
        atts["0x1908d72c46a0440b2cc449de243a20ac8ab3ab9a11c096f9c5abcb6de42c99e7"] = Attribute(true, "Alientina"); // 0
        atts["0xcedf32c147815fdc0d5f7e785f41a33dfc773e45bbd1a9a3b5d86c264e1b8ac5"] = Attribute(true, "Zombina"); // 0
        atts["0x691d9c552cd5457793c084f8bfce824df33aa7bcff69bb398b1c50c5283700ab"] = Attribute(true, "ZombieApe"); // 0
        atts["0x44cc2bd937a1ba84d91aa4ad1c68a4019d7441276f158686ca21113d9b58c736"] = Attribute(true, "Cigarina"); // 0
        atts["0x6ad96c1daca4b1c9f05d375a8cc7561b56dc9f8e0c47de6294d0b56e99baba9f"] = Attribute(true, "Cyborghina 1"); // 0
        atts["0x630cf72f7f662f0e4ad0e59518468203238cfd411fb9c5b474e65247043ff6ff"] = Attribute(true, "Cyborghina 2"); // 0
        atts["0x9c4d52ffba9e3fe6a536e1420a71503203fde6d50cc7dfd6dcffb18520ea92ac"] = Attribute(true, "Cyborghina 3"); // 0
        atts["0xa85374c4f65c797073c8536e4d19c56b86127fd476a9b5a4b3fbf026a0a631e9"] = Attribute(true, "Cyborghina 4"); // 0
        atts["0x53c4266e345ac07f4b1871310600f58edbc34ac584f94a14b301b73dab6f3eb7"] = Attribute(true, "Apexus 1"); // 0
        atts["0x6528e7d7c1f35ff1569dd65b8801909e5792c388e4c77a81c2861b7dba7d3800"] = Attribute(true, "Apexus 2"); // 0
        atts["0xbfaced9f8b3c58cbea8869f267e8c39500da9c86b500a8207a4f31667d37e9a4"] = Attribute(true, "Apexus 3"); // 0
        atts["0xb9c52250f5eef12475dec466c74c2d2eab10a1010f3a86073b1d92086882fb9a"] = Attribute(true, "Apexus 4"); // 0

        let all = [];
        for (const [key, value] of Object.entries(atts)) {

            console.log("key:", key);
            let key32 = new Uint8Array(32);
            for (let i = 0; i < 32; i++) {
                key32[i] = parseInt(key[(i*2)+2]+""+key[(i*2)+3], 16); // hex to bytes, each two hex digits is one byte.
            }
            all.push([key32, value[0], value[1]]);
        }
        await badges.completeInitialization1(all);

        const list = [
            //"0xc43473fA66237e9AF3B2d886Ee1205b81B14b2C8",
            "0xa80be8CAC8333330106585ee210C3F245D4f98Df",
            "0x713282ECe7b1e34Bcb88c8f1922561A4EE369772",
            "0x21077c224B7178b1Bb46af8dcd73F1EBAd869B0B",
            "0xC088B1eEf1C08CE01A2aBF73531a61270481Fb0B",
            "0x53B182152c57E37dde0E67675946169d44F3c005",
            "0x614A61a3b7F2fd8750AcAAD63b2a0CFe8B8524F1",
            "0xf20dC15A36D4E1Fdb3A767C6aB4A7e972574573d",
            "0x0000000704dd12B781af73e9D7ac1f6BE3B46423",
            "0x910E4220e1EDd15D4f5A6450521d0Cd06D275c00",
            "0x64CB2f44AE5c5D4592920D49e57e9b3F005Da5dc",
            "0x8C48b40dBa656187896147089545439E4fF4A01c",
            "0xaf016eC2AfD326126d7f43498645A33a4aCf51F2",
            "0x7539Eb7d68e49D4Ad65067577c47DfC92f5Fc1Ce",
            "0xc50A0b4F31Cd5580c7a629178ff78CFF5973edB6",
            "0xEE8dBE16568254450d890C1CB98180A770e82724",
            "0x3E5a90F582d45Cf83e0446D53B3069E86162003b",
            "0xB9CDEB51bD53fAF41Ea92c94526f40f15460c088",
            "0x1CBa69a71c1D17a69Fc0cb9eD0945F9E7DeD702a",
            "0x96aCe5Dc0404f2613ebCc5b04cD455b35b6Bf7c7",
            "0x5B5b487aEd7D18ac677C73859270b0F6CF5bB69C",
            "0xeb26E394da8d8AD5bEDDE97a281a9a9b63b3Eef3",
            "0xACe239D889b5aceffC6F4ea7fF6DdCAFD3900936",
            "0x17476d0Ed31f81d95b5ba8960b2D0b4dE4675e64",
            "0x81c247e7923eb96Aeb908228A50eDec0dB8Ba09e",
            "0x2A8bE03A5D65dE287648Ec176B74745ee9c164D2",
            "0x1E0591255AdC9Cfb2cFbBfFF5AE48b7BeE6E253d"
        ];



        let ABI = [
            "function completeInitialization2(address[])"
        ];
        // await badges.completeInitialization1(list); - didn't work, so we use a workaround
        let iface = new ethers.utils.Interface(ABI);
        let data = await iface.encodeFunctionData("completeInitialization2",[list]);

        await owner.sendTransaction({
            to: badges.address,
            data: data
        });

        expect(await badges.totalSupply()).to.be.equal(31);

        expect(await badges.ownerOf(5)).to.be.equal("0xa80be8CAC8333330106585ee210C3F245D4f98Df");

        //let thirty = await badges.tokenURI(30);
        //console.log(thirty);


    });

    it("test enumeration", async function () {

        /*

        Initial config:

        tid: BigNumber { value: "0" }
        tid: BigNumber { value: "4" }
        tid: BigNumber { value: "2" }
        tid: BigNumber { value: "3" }

        After moving out id 4, the order would be: 0, 3, 2

        */
        let list = async function (whom) {
            let tokenId;
            console.log("inventory for:" +whom);
            for (let i = 0 ; i < await badges.balanceOf(whom); i++) {
                tokenId = await badges.tokenOfOwnerByIndex(whom, i);
                console.log("tid:", tokenId);
            }
        }
        await list(EOA);
        // this removes the 4, taking 2 from the end to fill the empty spot
        await badges.connect(tycoon).transferFrom(EOA, await simp.getAddress(), 4);
        expect(await badges.tokenOfOwnerByIndex(EOA, 0)).to.be.equal("0");
        expect(await badges.tokenOfOwnerByIndex(EOA, 1)).to.be.equal("3");
        expect(await badges.tokenOfOwnerByIndex(EOA, 2)).to.be.equal("2");

        await list(EOA);
        await badges.connect(tycoon).transferFrom(EOA, await simp.getAddress(), 2);

        await list(EOA);
        // this removes the last element
        expect(await badges.tokenOfOwnerByIndex(EOA, 0)).to.be.equal("0");
        expect(await badges.tokenOfOwnerByIndex(EOA, 1)).to.be.equal("3");

    });

});

const CIG_ABI =  [{"inputs":[{"internalType":"uint256","name":"_cigPerBlock","type":"uint256"},{"internalType":"address","name":"_punks","type":"address"},{"internalType":"uint256","name":"_CEO_epoch_blocks","type":"uint256"},{"internalType":"uint256","name":"_CEO_auction_blocks","type":"uint256"},{"internalType":"uint256","name":"_CEO_price","type":"uint256"},{"internalType":"bytes32","name":"_graffiti","type":"bytes32"},{"internalType":"address","name":"_NFT","type":"address"},{"internalType":"address","name":"_V2ROUTER","type":"address"},{"internalType":"address","name":"_OC","type":"address"},{"internalType":"uint256","name":"_migration_epochs","type":"uint256"},{"internalType":"address","name":"_MASTERCHEF_V2","type":"address"}],"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"address","name":"spender","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Approval","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"called_by","type":"address"},{"indexed":false,"internalType":"uint256","name":"reward","type":"uint256"}],"name":"CEODefaulted","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"price","type":"uint256"}],"name":"CEOPriceChange","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"ChefDeposit","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"ChefWithdraw","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"uint256","name":"punkIndex","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Claim","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"Deposit","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"EmergencyWithdraw","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"Harvest","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":true,"internalType":"uint256","name":"punk_id","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"new_price","type":"uint256"},{"indexed":false,"internalType":"bytes32","name":"graffiti","type":"bytes32"}],"name":"NewCEO","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"RevenueBurned","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"reward","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"downAmount","type":"uint256"}],"name":"RewardDown","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"reward","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"upAmount","type":"uint256"}],"name":"RewardUp","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"TaxBurned","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"TaxDeposit","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"from","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Transfer","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"Withdraw","type":"event"},{"inputs":[],"name":"CEO_price","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"CEO_punk_index","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"CEO_state","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"CEO_tax_balance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"The_CEO","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"accCigPerShare","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"admin","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"},{"internalType":"address","name":"","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_spender","type":"address"},{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"burnTax","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_max_spend","type":"uint256"},{"internalType":"uint256","name":"_new_price","type":"uint256"},{"internalType":"uint256","name":"_tax_amount","type":"uint256"},{"internalType":"uint256","name":"_punk_index","type":"uint256"},{"internalType":"bytes32","name":"_graffiti","type":"bytes32"}],"name":"buyCEO","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"cigPerBlock","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_punkIndex","type":"uint256"}],"name":"claim","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"}],"name":"claims","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"decimals","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"deposit","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"depositTax","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"emergencyWithdraw","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"farmers","outputs":[{"internalType":"uint256","name":"deposit","type":"uint256"},{"internalType":"uint256","name":"rewardDebt","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"farmersMasterchef","outputs":[{"internalType":"uint256","name":"deposit","type":"uint256"},{"internalType":"uint256","name":"rewardDebt","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_user","type":"address"}],"name":"getStats","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"},{"internalType":"address","name":"","type":"address"},{"internalType":"bytes32","name":"","type":"bytes32"},{"internalType":"uint112[]","name":"","type":"uint112[]"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"graffiti","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"harvest","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_punkIndex","type":"uint256"}],"name":"isClaimed","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"lastRewardBlock","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"lpToken","outputs":[{"internalType":"contract ILiquidityPoolERC20","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"masterchefDeposits","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"migrationComplete","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"name","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"address","name":"_user","type":"address"},{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_sushiAmount","type":"uint256"},{"internalType":"uint256","name":"_newLpAmount","type":"uint256"}],"name":"onSushiReward","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_user","type":"address"}],"name":"pendingCig","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"punks","outputs":[{"internalType":"contract ICryptoPunk","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"renounceOwnership","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"rewardDown","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"rewardUp","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"rewardsChangedBlock","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"contract ILiquidityPoolERC20","name":"_addr","type":"address"}],"name":"setPool","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_price","type":"uint256"}],"name":"setPrice","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"setReward","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_startBlock","type":"uint256"}],"name":"setStartingBlock","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"stakedlpSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"symbol","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"taxBurnBlock","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"totalSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"transfer","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_from","type":"address"},{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"transferFrom","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"unwrap","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"update","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"address","name":"_user","type":"address"}],"name":"userInfo","outputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"uint256","name":"depositAmount","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"wBal","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"withdraw","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"wrap","outputs":[],"stateMutability":"nonpayable","type":"function"}];

const SLP_ABI = [{"inputs":[],"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"address","name":"spender","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Approval","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount0","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1","type":"uint256"},{"indexed":true,"internalType":"address","name":"to","type":"address"}],"name":"Burn","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount0","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1","type":"uint256"}],"name":"Mint","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount0In","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1In","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount0Out","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1Out","type":"uint256"},{"indexed":true,"internalType":"address","name":"to","type":"address"}],"name":"Swap","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint112","name":"reserve0","type":"uint112"},{"indexed":false,"internalType":"uint112","name":"reserve1","type":"uint112"}],"name":"Sync","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"from","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Transfer","type":"event"},{"inputs":[],"name":"DOMAIN_SEPARATOR","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"MINIMUM_LIQUIDITY","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"PERMIT_TYPEHASH","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"},{"internalType":"address","name":"","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"burn","outputs":[{"internalType":"uint256","name":"amount0","type":"uint256"},{"internalType":"uint256","name":"amount1","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"decimals","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"factory","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"getReserves","outputs":[{"internalType":"uint112","name":"_reserve0","type":"uint112"},{"internalType":"uint112","name":"_reserve1","type":"uint112"},{"internalType":"uint32","name":"_blockTimestampLast","type":"uint32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_token0","type":"address"},{"internalType":"address","name":"_token1","type":"address"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"kLast","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"mint","outputs":[{"internalType":"uint256","name":"liquidity","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"name","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"nonces","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"},{"internalType":"uint256","name":"deadline","type":"uint256"},{"internalType":"uint8","name":"v","type":"uint8"},{"internalType":"bytes32","name":"r","type":"bytes32"},{"internalType":"bytes32","name":"s","type":"bytes32"}],"name":"permit","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"price0CumulativeLast","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"price1CumulativeLast","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"skim","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amount0Out","type":"uint256"},{"internalType":"uint256","name":"amount1Out","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"bytes","name":"data","type":"bytes"}],"name":"swap","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"symbol","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"sync","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"token0","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"token1","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"totalSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"}],"name":"transfer","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"from","type":"address"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"}],"name":"transferFrom","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"}];

const BLOCKS_ABI = [{"inputs":[],"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"","type":"address"},{"indexed":false,"internalType":"uint32","name":"","type":"uint32"},{"indexed":false,"internalType":"string","name":"","type":"string"}],"name":"NewBlock","type":"event"},{"inputs":[],"name":"abort","outputs":[],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"name":"blockL","outputs":[{"internalType":"bytes","name":"","type":"bytes"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"name":"blockS","outputs":[{"internalType":"bytes","name":"","type":"bytes"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"}],"name":"blockToLayer","outputs":[{"internalType":"enum PunkBlocks.Layer","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"name":"blocksInfo","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_fromID","type":"uint256"},{"internalType":"uint256","name":"_count","type":"uint256"}],"name":"getBlocks","outputs":[{"components":[{"internalType":"enum PunkBlocks.Layer","name":"layer","type":"uint8"},{"internalType":"bytes","name":"blockL","type":"bytes"},{"internalType":"bytes","name":"blockS","type":"bytes"}],"internalType":"struct PunkBlocks.Block[]","name":"","type":"tuple[]"},{"internalType":"uint32","name":"","type":"uint32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint32","name":"","type":"uint32"}],"name":"index","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes32","name":"_id","type":"bytes32"}],"name":"info","outputs":[{"internalType":"enum PunkBlocks.Layer","name":"","type":"uint8"},{"internalType":"uint16","name":"","type":"uint16"},{"internalType":"uint16","name":"","type":"uint16"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"nextConfigId","outputs":[{"internalType":"uint32","name":"","type":"uint32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"nextId","outputs":[{"internalType":"uint32","name":"","type":"uint32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint32","name":"","type":"uint32"},{"internalType":"enum PunkBlocks.Layer","name":"","type":"uint8"}],"name":"orderConfig","outputs":[{"internalType":"uint16","name":"","type":"uint16"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes","name":"_dataL","type":"bytes"},{"internalType":"bytes","name":"_dataS","type":"bytes"},{"internalType":"uint8","name":"_layer","type":"uint8"},{"internalType":"string","name":"_name","type":"string"}],"name":"registerBlock","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"enum PunkBlocks.Layer[]","name":"_order","type":"uint8[]"}],"name":"registerOrderConfig","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"seal","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint32[]","name":"_ids","type":"uint32[]"},{"internalType":"uint16","name":"_x","type":"uint16"},{"internalType":"uint16","name":"_y","type":"uint16"},{"internalType":"uint16","name":"_size","type":"uint16"},{"internalType":"uint32","name":"_orderID","type":"uint32"}],"name":"svgFromIDs","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes32[]","name":"_attributeKeys","type":"bytes32[]"},{"internalType":"uint16","name":"_x","type":"uint16"},{"internalType":"uint16","name":"_y","type":"uint16"},{"internalType":"uint16","name":"_size","type":"uint16"},{"internalType":"uint32","name":"_orderID","type":"uint32"}],"name":"svgFromKeys","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"string[]","name":"_attributeNames","type":"string[]"},{"internalType":"uint16","name":"_x","type":"uint16"},{"internalType":"uint16","name":"_y","type":"uint16"},{"internalType":"uint16","name":"_size","type":"uint16"},{"internalType":"uint32","name":"_orderID","type":"uint32"}],"name":"svgFromNames","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_tokenID","type":"uint256"},{"internalType":"uint16","name":"_x","type":"uint16"},{"internalType":"uint16","name":"_y","type":"uint16"},{"internalType":"uint16","name":"_size","type":"uint16"},{"internalType":"uint32","name":"_orderID","type":"uint32"}],"name":"svgFromPunkID","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"value","type":"uint256"}],"name":"toString","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"pure","type":"function"}]