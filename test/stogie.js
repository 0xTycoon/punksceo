/**
 * Stogie test. This test is designed to run on forked-mainnet
 * Eg. in the network setting, place this:
 * this object the "networks" object of the json config
 *         hardhat: {
 *             forking: {
 *                 url: "https://eth-mainnet.alchemyapi.io/v2/API-KEY",
 *                 //blockNumber: 14487179 // if you want to lock to a specific block
 *             }
 *         }
 */
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const {expect} = require("chai");
const {ContractFactory, utils, BigNumber} = require('ethers');

//import { solidity } from "ethereum-waffle";
//chai.use(solidity);

//const helpers = require("@nomicfoundation/hardhat-network-helpers");
const unlimited = BigNumber.from("2").pow(BigNumber.from("256")).sub(BigNumber.from("1"));

const SCALE = BigNumber.from("1000");

describe("Stogie", function () {
    let owner, simp, elizabeth, tycoon, impersonatedSigner; // accounts
    let pool, Stogie, stogie, cig, cigeth; // contracts
    let feth = utils.formatEther;
    let peth = utils.parseEther;
    let badges, EmployeeIDBadges;
    let router;
    const EOA = "0xc43473fA66237e9AF3B2d886Ee1205b81B14b2C8"; // EOA that has ETH and CIG to impersonate
    const CIG_ADDRESS = "0xcb56b52316041a62b6b5d0583dce4a8ae7a3c629"; // cig on mainnet
    const CIGETH_SLP_ADDRESS = "0x22b15c7Ee1186A7C7CFfB2D942e20Fc228F6E4Ed";
    const ENS_ADDRESS = "0xc18360217d8f7ab5e7c516566761ea12ce7f9d72" // ENS token on mainnet
    const WETH_Address = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
    const UNIV2Router_Address = '0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f';
    before(async function () {
        // assuming we are at block 14148801

        [owner, simp, elizabeth] = await ethers.getSigners();
        cig = await hre.ethers.getContractAt(CIG_ABI,  CIG_ADDRESS);

        //[owner, simp, elizabeth] = await ethers.getSigners();
        cigeth = await hre.ethers.getContractAt(SLP_ABI,  CIGETH_SLP_ADDRESS);
        EmployeeIDBadges = await ethers.getContractFactory("EmployeeIDBadges");
        badges = await EmployeeIDBadges.deploy(CIG_ADDRESS,
            3, // epoch (blocks)
            1, // duration (number of epochs to wait)
            2, // grace period
            "0xc55C7913BE9E9748FF10a4A7af86A5Af25C46047", // identicons
            "0xe91eb909203c8c8cad61f86fc44edee9023bda4d", // punk blocks
            "0x4872BC4a6B29E8141868C3Fe0d4aeE70E9eA6735",  // barcode
            0
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

        await badges.setStogie(stogie.address);

        //await helpers.impersonateAccount(EOA);
        //let impersonatedSigner = await ethers.getSigner(EOA);

        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [EOA],
        });
        tycoon = await ethers.provider.getSigner(EOA);
        let tx = {
            to: EOA,
            // Convert currency unit from ether to wei
            value: ethers.utils.parseEther("10")
        }
        await owner.sendTransaction(tx);
//        console.log(tycoon, cig.address, tycoon.address, impersonatedSigner);
        router =  await hre.ethers.getContractAt(v2RouterABI, v2RouterAddress);
        await expect(await cig.connect(tycoon).approve(router.address, unlimited)).to.emit(cig, "Approval");

    });

    it("init the stogie", async function () {
/*
        await tycoon.sendTransaction({
            to: "0x0000000000000000000000000000000000000000",
            value: ethers.utils.parseEther("0.01"),
        });
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
        console.log("cig/eth slp:" + feth(await cigeth.connect(tycoon).balanceOf(EOA)));
        console.log("cig:" + feth(await cig.connect(tycoon).balanceOf(EOA)));
    });


    let _sqrt = function(y) {
        let z,x;
        if (y > 3n) {
            z = y;
            x = y / 2n + 1n;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2n;
            }
        } else if (y !== 0n) {
            z = 1n;
        }
        return z;
    }

    /**
     * @dev _getSwapAmount calculates how much _a we need to sell to have an equal portion when adding
     *        liquidity to a pool, that has a reserve balance of _r in that token. Includes 3% fee
     * @param _r
     * @param _a
     * @returns {bigint}
     */
    function getSwapAmount(_r, _a) {
        return (_sqrt((_a * ((_r * 3988000n) + (_a * 3988009n)))) - (_a * 1997n)) / 1994n;
    }

    // Given some asset amount and reserves, returns an amount of the other asset representing equivalent value
    function quote(amountA, reserveA, reserveB) {
        //reserves
        return amountA.mul(reserveB).div(reserveA);
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(amountIn,reserveIn,reserveOut) {
        let amountInWithFee = amountIn.mul(BigNumber.from("997"));
        let numerator = amountInWithFee.mul(reserveOut);
        let denominator = reserveIn.mul(1000).add(amountInWithFee);
        return numerator.div(denominator);
        /*
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
        */

    }

    async function getStats(_user)  {
        let r = {};
        //let s = await stogie.getStats(_user);
        let [s2, cigdata, theCEO, graffiti, reserves] = await stogie.getStats(_user);
        r.stakeDeposit = s2[0]; // how much STOG staked by user
        r.rewardDebt = s2[1]; // amount of rewards paid out for user
        r.stogieContractBal = s2[2]; // contract's STOGE balance
        r.slpContractBal = s2[3]; // contract CIG/ETH SLP balance
        r.stogieBal = s2[4];// user's STOG balance
        r.accumulated = s2[5]; // amount of CIG accumulated and advanced from the factory
        r.accCigPerShare = s2[6]; // accumulated CIG per STOG share
        r.pendingCig = s2[7]; // pending CIG reward to be harvested by _user
        r.wethBal = s2[8]; // user's WETH balance
        r.ethBal = s2[9]; // user's ETH balance
        r.cigContractApproval = s2[10]; // user's approval for Stogies to spend their CIG
        r.slpContractApproval = s2[11]; // user's approval for Stogies to spend CIG/ETH SLP
        r.ethContractApproval = s2[12]; // user's approval for stogies to spend WETH
        r.stogieSupply = s2[13];
        r.cigBal = cigdata[15];// user's CIG balance
        r.slpBal = cigdata[16];// user's CIG/ETH SLP balance
        r.ethPriceInCig = s2[14]; // How much CIG for 1 ETH (ETH price in CIG)
        r.ethdaiETHRes = s2[15]; // DAI reserves of WETH/DAI
        r.ethdaiDAIRes = s2[16]; // WETH reserves of WETH/DAI
        r.ethPriceInUsd = s2[17]; // ETH price in USD
        r.slpEthReserve = reserves[0]; // CIG/ETH SLP reserves, ETH
        r.slpCigReserve = reserves[1]; // CIG reserve is slp


        r.blockNumber = cigdata[9]; // current block number
        r.slpSupply = cigdata[22]; // total supply of CIG/ETH SLP
        r.cigSupply = cigdata[7];
        r.slpDepositedInCig = cigdata[8];
        r.cigPerBlock = cigdata[6];
        r.theCEO = theCEO;
        r.graffiti = graffiti;
        r.cigdata = cigdata;

/*
        if (ethers.utils.hexlify(s[29]) === CIG_ADDRESS ) { // web3.utils.toHex
            r.stogieSlpCigReserve = s[27];
            r.stogieSlpStogieReserve = s[28];
        } else { // reversed
            r.stogieSlpCigReserve = s[28];
            r.stogieSlpStogieReserve = s[27];
        }
        r.stogieSlpToken0 = ethers.utils.hexlify(s[29]); // address of token0 in Stogie/Cig slp
  */

        r.blockTimestamp = s2[20];
        r.cigBalContract = s2[21];

        return r;
    }
    it("deposit ETH and stake", async function () {

        let stats = await getStats(EOA);
        let deposit = peth("1");

        console.log(stats);
        expect(stats.stakeDeposit).to.equal(0);

        // work out how much eth the position will sell
        let portion = BigNumber.from(getSwapAmount(BigInt(deposit.toString()), BigInt(stats.slpEthReserve)));


        let q = getAmountOut(portion, stats.slpEthReserve, stats.slpCigReserve);

        //let amountETHMin = q.sub(portion.div(BigNumber.from("1000").mul(BigNumber.from("100")))) ;

       let percent = BigNumber.from("10"); // scale by 10 (100 = 10%)
        // 900 = 90% , 10 = 1%, etc.
        let amountCIGMin = q.sub(q.mul(percent).div(SCALE)) ;


        console.log("portion:"+feth(portion));
        console.log("q:"+feth(q));
        console.log("reserve js:"+stats.slpEthReserve);
        console.log("amountCIGMin", feth(amountCIGMin));


        let ts = Math.floor(Date.now() / 1000);
        console.log("deposit is:"+deposit);
        //
        await expect( stogie.connect(tycoon)
            .depositWithETH(
                amountCIGMin, // peth("1"),
                BigNumber.from(ts+60),
                true,
                true, // mint ud
                {value: deposit})
        ).to.emit(stogie, "Deposit").withArgs(EOA, peth("1129.035931538015063025"));

        // sanity check
        let stats2 = await getStats(EOA);
        let lpDeposited = BigNumber.from(stats2.stakeDeposit);
        console.log("lp deposited:", feth(lpDeposited));
        expect(lpDeposited).to.greaterThan(BigNumber.from(0)); // we have deposited

        console.log(stats2);

        await stogie.connect(tycoon).fetchCigarettes();
        let pending = await stogie.connect(tycoon).pendingCig(EOA);
        console.log("Pending CIGGGGGGGGGGGGGGG:", feth(pending));

        // harvest time
        expect(await stogie.connect(tycoon).harvest()).to.emit(stogie, "Harvest");
        let stats3 = await getStats(EOA);
        //expect(parseInt(stats3.cigBal)).to.greaterThan(parseInt(stats2.cigBal)); // cig balance should increase
        console.log("1. CIG increased by:"+feth(BigNumber.from(stats3.cigBal).sub(BigNumber.from(stats2.cigBal))));
       ////
        await stogie.connect(tycoon).fetchCigarettes();
       ///
        stats2 = await getStats(EOA);
        expect(await stogie.connect(tycoon).harvest()).to.emit(stogie, "Harvest");
        stats3 = await getStats(EOA);
        //expect(parseInt(stats3.cigBal)).to.greaterThan(parseInt(stats2.cigBal)); // cig balance should increase
        console.log("2. CIG increased by:"+feth(BigNumber.from(stats3.cigBal).sub(BigNumber.from(stats2.cigBal))));
        // test withdraw
        expect(await stogie.connect(tycoon).withdraw(BigNumber.from(stats3.stakeDeposit))).to.emit(stogie, "Withdraw");
        expect(await stogie.connect(tycoon).balanceOf(EOA)).to.equal(lpDeposited);

    });


   // todo test with Uniswap router
    it("deposit with ENS token and stake", async function () {

        let ens = await hre.ethers.getContractAt(CIG_ABI,  ENS_ADDRESS); // we can use CIG_ABI since it's ERC20 compatible
        await expect(await router.swapExactETHForTokens(
            peth("0.5"), // amountOutMin
            [WETH_Address, ENS_ADDRESS],
            EOA,
            Math.floor(Date.now() / 1000) + 1200, // deadline + 20 min
            {
                value: peth("0.5")
            }
        )).to.emit(ens, "Transfer");

        let ensBal = await ens.connect(tycoon).balanceOf(EOA);
        console.log("ENS bal:"+feth(ensBal));

        await expect( ens.connect(tycoon).approve(stogie.address, unlimited)).to.emit(ens, "Approval");
        let ts = Math.floor(Date.now() / 1000);
        await expect( stogie.connect(tycoon)
            .depositWithToken(
                ensBal,
                peth("1"),
                peth("0.1"),
                ENS_ADDRESS,
                "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F",
                BigNumber.from(ts+60),
                true, false)
        ).to.emit(stogie, "Deposit").withArgs(EOA, peth("558.546143632756056003"));
        await expect(await stogie.connect(tycoon).harvest()).to.emit(stogie, "Harvest");
        let s = await getStats(EOA);
        await expect(await stogie.connect(tycoon).withdraw(s.stakeDeposit)).to.emit(stogie, "Withdraw").withArgs(EOA, peth("558.546143632756056003")).to.emit(stogie, "Harvest");
        await expect(await stogie.connect(tycoon).harvest()).to.emit(stogie, "Harvest").withArgs(EOA, EOA, peth("0")); // expecting 0 since we are not staking
        //let ts = Math.floor(Date.now() / 1000) + 1200;
        await expect(await stogie.connect(tycoon).unwrapToCIGETH(await stogie.balanceOf(EOA), 1, 1, ts)).to.emit(stogie, "Transfer").to.emit(cig, "Transfer").withArgs(CIGETH_SLP_ADDRESS, EOA, peth("3943139.975480167515576086"));

        await expect(await cig.balanceOf(EOA)).to.equal(peth("14139466.707908220050098989"));
       // let weth = await hre.ethers.getContractAt(CIG_ABI,  WETH_Address);
       // await expect(await weth.connect(tycoon).approve(router.address, unlimited)).to.emit(cig, "Approval");
        // go back to ETH
        await expect(await router.connect(tycoon).swapExactTokensForETH(
            peth("14139466"), // amountOutMin the CIG to sell,
            peth("0.01"),
            [CIG_ADDRESS, WETH_Address],
            EOA,
            Math.floor(Date.now() / 1000) + 1200, // deadline + 20 min
        )).to.emit(cig, "Transfer");
        //process.exit();

    });

    it("deposit CIG and stake", async function () {
        // test for depositWithCIG

        // buy some CIG
        await expect(await router.swapExactETHForTokens(
            peth("1"), // amountOutMin
            [WETH_Address, CIG_ADDRESS],
            EOA,
            Math.floor(Date.now() / 1000) + 1200, // deadline + 20 min
            {
                value: peth("1")
            }
        )).to.emit(cig, "Transfer");
        await expect(await stogie.connect(tycoon).harvest()).to.emit(stogie, "Harvest").withArgs(EOA, EOA, peth("0")); // not staking anything
        await cig.connect(tycoon).approve(stogie.address, unlimited);
        let bal = await cig.connect(tycoon).balanceOf(EOA);
        console.log("cig bal: ", bal);
        await expect(await stogie.connect(tycoon).depositWithCIG(
            bal,
            peth("0.01"),
            Math.floor(Date.now() / 1000) + 1200,
            true,
            false
        )).to.emit(stogie, "Deposit");
        await expect(await stogie.connect(tycoon).harvest()).to.emit(stogie, "Harvest").withArgs(EOA, EOA, peth("0.166563952930618213")); // after staking
        let s = await getStats(EOA);
        await expect(await stogie.connect(tycoon).withdraw(s.stakeDeposit)).to.emit(stogie, "Withdraw").withArgs(EOA, s.stakeDeposit).to.emit(stogie, "Harvest");
        await expect(await stogie.connect(tycoon).unwrapToCIGETH(
            await stogie.balanceOf(EOA), 1, 1, Math.floor(Date.now() / 1000) + 1200)
        ).to.emit(stogie, "Transfer").to.emit(cig, "Transfer").withArgs(CIGETH_SLP_ADDRESS, EOA, peth("2765103.424299061635547628"));
        // go back to ETH
        await expect(await router.connect(tycoon).swapExactTokensForETH(
            await cig.balanceOf(EOA), // amountOutMin the CIG to sell,
            peth("0.01"),
            [CIG_ADDRESS, WETH_Address],
            EOA,
            Math.floor(Date.now() / 1000) + 1200, // deadline + 20 min
        )).to.emit(cig, "Transfer");

    });

    it("test depositWithWETH", async function () {
       let weth = await hre.ethers.getContractAt(WETH_ABI,  WETH_Address);
        await weth.connect(tycoon).deposit( {value: peth("1")});
        await weth.connect(tycoon).approve(stogie.address, unlimited);
        await expect(await stogie.connect(tycoon).depositWithWETH(
            peth("1"),
            peth("1"),
            Math.floor(Date.now() / 1000) + 1200,
            true,
            false
        )).to.emit(stogie, "Deposit");
        let[deposit, debt] = await stogie.connect(tycoon).farmers(EOA);
        expect(deposit).to.gt(BigNumber.from("0"));
        await expect(await stogie.connect(tycoon).harvest()).to.emit(stogie, "Harvest").withArgs(EOA, EOA, peth("0.167048243745398012")); // after staking
        await expect(await stogie.connect(tycoon).withdraw(deposit)).to.emit(stogie, "Withdraw").withArgs(EOA, deposit).to.emit(stogie, "Harvest");
        await expect(await stogie.connect(tycoon).unwrapToCIGETH(
            await stogie.balanceOf(EOA), 1, 1, Math.floor(Date.now() / 1000) + 1200)
        ).to.emit(stogie, "Transfer").to.emit(cig, "Transfer").withArgs(CIGETH_SLP_ADDRESS, EOA, peth("2773134.996436447141072273"));
        // go back to ETH
        await expect(await router.connect(tycoon).swapExactTokensForETH(
            await cig.balanceOf(EOA), // amountOutMin the CIG to sell,
            peth("0.01"),
            [CIG_ADDRESS, WETH_Address],
            EOA,
            Math.floor(Date.now() / 1000) + 1200, // deadline + 20 min
        )).to.emit(cig, "Transfer");

    });

    it("test depositCigWeth", async function () {

        // First, we will need to get some CIG
        let stats = await getStats(EOA);
        let deposit = peth("1");

        //console.log(stats);
        expect(stats.stakeDeposit).to.equal(0);

        // work out how much eth needs to be sold to get equal portion of CIG
        let portion = BigNumber.from(getSwapAmount(BigInt(deposit.toString()), BigInt(stats.slpEthReserve)));

        // buy some CIG
        await expect(await router.swapExactETHForTokens(
            1, // amountOutMin
            [WETH_Address, CIG_ADDRESS],
            EOA,
            Math.floor(Date.now() / 1000) + 1200, // deadline + 20 min
            {
                value: portion
            }
        )).to.emit(cig, "Transfer").withArgs(CIGETH_SLP_ADDRESS, EOA, peth("2773030.110238247726596880"));

        await expect (await stogie.connect(tycoon).depositCigWeth(
            peth("1639100.008254948370993122"),
            deposit.sub(portion),
            1,
            1,
            Math.floor(Date.now() / 1000) + 1200,
            false,
            false

        )).to.emit(stogie, "Deposit");

        // withdraw and  sell back to eth

        [deposit, ] = await stogie.connect(tycoon).farmers(EOA);
       // console.log("deposit:", deposit);
        expect(deposit).to.gt(BigNumber.from("0"));
        //let reward = await stogie.connect(tycoon).fetchCigarettes();
        //console.log("reward: "+ await reward);
        await expect(await stogie.connect(tycoon).harvest()).to.emit(stogie, "Harvest").withArgs(EOA, EOA, peth("0.098997174644524100")); // after staking
        await expect(await stogie.connect(tycoon).withdraw(deposit)).to.emit(stogie, "Withdraw").withArgs(EOA, deposit).to.emit(stogie, "Harvest");
        await expect(await stogie.connect(tycoon).unwrapToCIGETH(
            await stogie.balanceOf(EOA), 1, 1, Math.floor(Date.now() / 1000) + 1200)
        ).to.emit(stogie, "Transfer").to.emit(cig, "Transfer").withArgs(CIGETH_SLP_ADDRESS, EOA, peth("1639100.008254948366242162"));
        // go back to ETH
        await expect(await router.connect(tycoon).swapExactTokensForETH(
            await cig.balanceOf(EOA), // amountOutMin the CIG to sell,
            peth("0.01"),
            [CIG_ADDRESS, WETH_Address],
            EOA,
            Math.floor(Date.now() / 1000) + 1200, // deadline + 20 min
        )).to.emit(cig, "Transfer");

    });

    it("test withdrawToWETH", async function () {
        let tx = {
            to: stogie.address,
            // Convert currency unit from ether to wei
            value: ethers.utils.parseEther("1")
        }
        let supply = await stogie.totalSupply();
        // test the sending on ETH to get stogies
         expect(await tycoon.sendTransaction(tx)).to.emit(stogie.address, "Transfer").withArgs(EOA, ethers.utils.parseEther("1"));
        let supply2 = await stogie.totalSupply();
        expect(supply2).gt(supply);
        let deposit;
        [deposit, ] = await stogie.connect(tycoon).farmers(EOA);
      // console.log("deposit is: "+deposit);
        let weth = await hre.ethers.getContractAt(WETH_ABI,  WETH_Address);
       await expect(await stogie.connect(tycoon).withdrawToWETH(deposit, 1,1, Math.floor(Date.now() / 1000) + 1200)).to.emit(stogie, "Withdraw").withArgs(EOA, deposit).to.emit(stogie, "Harvest").to.emit(weth, "Transfer").withArgs(stogie.address, EOA, peth("0.997028552648040182"));
        supply2 = await stogie.totalSupply();
        expect(supply).eq(supply2);
    });

    it("test withdrawToCIG", async function () {
        let tx = {
            to: stogie.address,
            // Convert currency unit from ether to wei
            value: ethers.utils.parseEther("1")
        }
        let supply = await stogie.totalSupply();
        // test the sending on ETH to get stogies
        expect(await tycoon.sendTransaction(tx)).to.emit(stogie.address, "Transfer").withArgs(EOA, ethers.utils.parseEther("1"));
        let supply2 = await stogie.totalSupply();
        expect(supply2).gt(supply);
        let deposit;
        [deposit, ] = await stogie.connect(tycoon).farmers(EOA);
        // console.log("deposit is: "+deposit);
        await expect(await stogie.connect(tycoon).withdrawToCIG(
            deposit,
            1,
            1,
            Math.floor(Date.now() / 1000) + 1200
        )).to.emit(stogie, "Withdraw").withArgs(EOA, deposit)
            .to.emit(stogie, "Harvest")
            .to.emit(cig, "Transfer").withArgs(stogie.address, EOA, peth("5519808.117320801736750534"));
        supply2 = await stogie.totalSupply();
        expect(supply).eq(supply2);

    });

    it("test withdrawCIGWETH", async function () {
        let tx = {
            to: stogie.address,
            // Convert currency unit from ether to wei
            value: ethers.utils.parseEther("1")
        }
        let supply = await stogie.totalSupply();
        // test the sending on ETH to get stogies
        expect(await tycoon.sendTransaction(tx)).to.emit(stogie.address, "Transfer").withArgs(EOA, ethers.utils.parseEther("1"));
        let supply2 = await stogie.totalSupply();
        expect(supply2).gt(supply);
        let deposit;
        [deposit, ] = await stogie.connect(tycoon).farmers(EOA);
        // withdraw to ENS
        //let ens = await hre.ethers.getContractAt(CIG_ABI,  ENS_ADDRESS); // we can use CIG_ABI since it's ERC20 compatible
        await expect(await stogie.connect(tycoon).withdrawCIGWETH(
            deposit,
            1,
            1,
            Math.floor(Date.now() / 1000) + 1200
        )).to.emit(stogie, "Withdraw").withArgs(EOA, deposit)
            .to.emit(stogie, "Harvest")
            .to.emit(cig, "Transfer").withArgs(CIGETH_SLP_ADDRESS, EOA, peth("2703337.399335917561927381"));
        supply2 = await stogie.totalSupply();
        expect(supply).eq(supply2);

    });

    it("test withdraw, deposit, wrap, deposit and unwrap", async function () {

        let tx = {
            to: stogie.address,
            // Convert currency unit from ether to wei
            value: ethers.utils.parseEther("1")
        }
        let supply = await stogie.totalSupply();
        // test the sending on ETH to get stogies
        expect(await tycoon.sendTransaction(tx)).to.emit(stogie.address, "Transfer").withArgs(EOA, ethers.utils.parseEther("1"));
        let supply2 = await stogie.totalSupply();
        expect(supply2).gt(supply);
        let deposit;
        [deposit, ] = await stogie.connect(tycoon).farmers(EOA);
        await expect(await stogie.connect(tycoon).withdraw(deposit)).to.emit(stogie, "Withdraw").withArgs(EOA, deposit).to.emit(stogie, "Harvest");
        await expect(await stogie.connect(tycoon).unwrap(deposit)).to.emit(cigeth, "Transfer").withArgs(stogie.address, EOA, deposit);
        supply2 = await stogie.totalSupply();
        expect(supply2).eq(supply);
         await expect(await stogie.connect(tycoon).deposit(deposit, false, true, false, 0, 0, ethers.utils.formatBytes32String(""), ethers.utils.formatBytes32String(""))).to.emit(stogie, "Deposit").withArgs(EOA, deposit);

        await expect(await stogie.connect(tycoon).withdraw(deposit)).to.emit(stogie, "Withdraw").withArgs(EOA, deposit).to.emit(stogie, "Harvest");
        await expect(await stogie.connect(tycoon).unwrap(deposit)).to.emit(cigeth, "Transfer").withArgs(stogie.address, EOA, deposit);

        await expect(await stogie.connect(tycoon).wrap(deposit, false, 0, 0, ethers.utils.formatBytes32String(""), ethers.utils.formatBytes32String(""))).to.emit(stogie, "Transfer").withArgs("0x0000000000000000000000000000000000000000", EOA, deposit);
        expect(await stogie.connect(tycoon).balanceOf(EOA)).eq(deposit);
        await expect(await stogie.connect(tycoon).deposit(deposit, false, false, false, 0, 0, ethers.utils.formatBytes32String(""), ethers.utils.formatBytes32String(""))).to.emit(stogie, "Transfer").withArgs(EOA, stogie.address, deposit);
        let bal = await cigeth.balanceOf(EOA);
        await expect(await stogie.connect(tycoon).wrap(bal, false, 0, 0, ethers.utils.formatBytes32String(""), ethers.utils.formatBytes32String(""))).to.emit(stogie, "Transfer").withArgs("0x0000000000000000000000000000000000000000", EOA, bal);
        await expect( stogie.connect(tycoon).wrap(deposit, false, 0, 0, ethers.utils.formatBytes32String(""), ethers.utils.formatBytes32String(""))).to.be.revertedWith("ds-math-sub-underflow");

    });
/*
    it("test fill", async function () {
        await stogie.connect(tycoon).deposit(await stogie.balanceOf(EOA), false);
        await expect(await stogie.connect(tycoon).harvest()).to.emit(stogie, "Harvest").withArgs(EOA, EOA, peth("0.989465690472307743"));
        await expect(await stogie.connect(tycoon).harvest()).to.emit(stogie, "Harvest").withArgs(EOA, EOA, peth("0.497752516061533615"));
        await expect(await stogie.connect(tycoon).harvest()).to.emit(stogie, "Harvest").withArgs(EOA, EOA, peth("0.497752512572990368"));
        await expect( stogie.connect(owner)
            .depositWithETH(
                1, // peth("1"),
                Math.floor(Date.now() / 1000) + 1200,
                true,
                true, // mint ud
                {value: peth("10")})
        ).to.emit(stogie, "Deposit").withArgs(owner.address, peth("10971.768074063004035697"));
        await expect(await stogie.connect(tycoon).fill(await cig.balanceOf(EOA))).to.emit(cig, "Transfer").withArgs(EOA, stogie.address, peth("8223147.994368543340419539")); // fills with 4873208 CIG
        let pending =
        await expect(await stogie.connect(owner).harvest()).to.emit(stogie, "Harvest").withArgs(owner.address, owner.address, peth("6239320.771440962837161386"));
        await expect(await stogie.connect(tycoon).harvest()).to.emit(stogie, "Harvest").withArgs(EOA, EOA, peth("1983832.081706683597094503"));
        let deposit;

        // owner 8544233573299167701782 + tycoon 3230888790697738610911
        // owner has about 72.5% more staked than tycoon
        [deposit, ] = await stogie.connect(tycoon).farmers(EOA);
        console.log("Tycoon deposit:"+deposit);
        //await stogie.connect(tycoon).withdraw(deposit);
        [deposit, ] = await stogie.connect(owner).farmers(owner.address);
        console.log("OWN deposit:"+deposit);
    });


 */
/*
    it("transfer stake", async function () {
        await expect( stogie.connect(owner)
            .depositWithETH(
                1, // peth("1"),
                Math.floor(Date.now() / 1000) + 1200,
                true,
                true, // mint ud
                {value: peth("10")})
        ).to.emit(stogie, "Deposit").withArgs(owner.address, peth("10971.768074063004035697"));

        [deposit, ] = await stogie.connect(tycoon).farmers(EOA);
        console.log("EDA deposit:"+deposit);

        await expect(stogie.connect(tycoon).transferStake(owner.address, 0)).to.be.revertedWith("userTo.deposit must be empty");
        [deposit, ] = await stogie.connect(owner).farmers(owner.address);
        await stogie.withdraw(deposit);
        [deposit, ] = await stogie.connect(tycoon).farmers(EOA);
        await expect(await stogie.connect(tycoon).transferStake(owner.address, 0)).to.emit(stogie, "TransferStake").withArgs(EOA, owner.address, deposit);

        await expect(await stogie.harvest()).to.emit(stogie, "Harvest").withArgs(owner.address, owner.address, peth("0.327808783357831735"));

        //await stogie.test(peth("5"), {value: peth("1")});

    });
*/
    it("test receive() and onboard, packSTOG", async function () {
        let tx = {
            to: stogie.address,
            // Convert currency unit from ether to wei
            value: ethers.utils.parseEther("1")
        }
        expect(await elizabeth.sendTransaction(tx)).to.emit(stogie.address, "Transfer").withArgs(elizabeth.address, ethers.utils.parseEther("1")).to.emit(badges, "Transfer"); // MINT 1 for elizabeth

        // onboard without depositing it
        await expect(await stogie.onboard(elizabeth.address, 1, false, false, {value: peth("10")})).to.emit(stogie, "Transfer");
        await expect(await stogie.connect(elizabeth).balanceOf(elizabeth.address)).to.equal(peth("10907.834830850940984302"));

        await expect(await stogie.connect(elizabeth).unwrap(peth("10907.834830850940984302"))).to.emit(cigeth, "Transfer").withArgs(stogie.address, elizabeth.address, peth("10907.834830850940984302")); // elizabeth should be able to get the SLP back
        await expect(await stogie.connect(elizabeth).balanceOf(elizabeth.address)).to.equal(peth("0"));
        await expect(stogie.connect(elizabeth).wrap(
            peth("10324.486644381790011032"),
            false,
            0,
            0,
            ethers.utils.formatBytes32String(""),
            ethers.utils.formatBytes32String("")
        )).to.be.revertedWith("ds-math-sub-underflow"); // need approval
        await cigeth.connect(elizabeth).approve(stogie.address, unlimited);

        await expect(await stogie.connect(elizabeth).wrap(peth("10324.486644381790011032"),false, 0, 0, ethers.utils.formatBytes32String(""), ethers.utils.formatBytes32String(""))).to.emit(stogie, "Transfer");
        await expect(await stogie.connect(elizabeth).balanceOf(elizabeth.address)).to.equal(peth("10324.486644381790011032"));


        tx = {
            to: "0x3d6A70DC23bdC3047536F00815a8AFC4c5A0E7B5", // getcig.eth
            // Convert currency unit from ether to wei
            value: ethers.utils.parseEther("1")

        }
        await expect(await elizabeth.sendTransaction(tx)).to.emit(cig, "Transfer").withArgs(cigeth.address, elizabeth.address, peth("4623889.144474397531755285"));


        await stogie.connect(elizabeth).approve(router.address, unlimited);
        await cig.connect(elizabeth).approve(router.address, unlimited);

        // to test packSTOG, we need to create a CIG/STOG pool
        await router.connect(elizabeth).addLiquidity(CIG_ADDRESS, stogie.address, peth("1000000"), peth("824"), 1, 1, elizabeth.address, Math.floor(Date.now() / 1000)+5 );

// 1562892689591694935537
        await expect(await stogie.connect(elizabeth).deposit(peth("500"), false, false, false, 0, 0, ethers.utils.formatBytes32String(""), ethers.utils.formatBytes32String(""))).to.emit(stogie, "Deposit");
        //await expect(await stogie.connect(elizabeth).harvest()).to.emit(stogie, "Harvest").withArgs(elizabeth.address, elizabeth.address, peth("2.148474746880758747"));
        console.log("Pending Cig: " + feth(await stogie.connect(elizabeth).pendingCig(elizabeth.address)));
        await expect(await stogie.connect(elizabeth).packSTOG(1, Math.floor(Date.now() / 1000) + 1200)).to.emit(stogie, "Transfer");

        // approve & transferFrom
        await expect(stogie.connect(simp).transferFrom(elizabeth.address, simp.address, peth("1"))).to.be.revertedWith("not approved");
        await stogie.connect(elizabeth).approve(simp.address, unlimited);
        await expect(await stogie.connect(simp).transferFrom(elizabeth.address, simp.address, peth("1"))).to.emit(stogie, "Transfer");
    });

    //
    it("test eip-2612", async function () {

        const chainId = await hre.network.config.chainId;

        const domain = {
            name: await stogie.name(),
            version: "1",
            chainId: chainId,
            verifyingContract: stogie.address
        };

        // set the Permit type parameters
        const types = {
            Permit: [{
                name: "owner",
                type: "address"
            },
                {
                    name: "spender",
                    type: "address"
                },
                {
                    name: "value",
                    type: "uint256"
                },
                {
                    name: "nonce",
                    type: "uint256"
                },
                {
                    name: "deadline",
                    type: "uint256"
                },
            ],
        };
        const deadline = Math.floor(Date.now() / 1000) + 4200;
        // set the Permit type values
        const values = {
            owner: owner.address,
            spender: EOA,
            value: unlimited,
            nonce: await stogie.nonces(owner.address),
            deadline: deadline,
        };
        const signature = await owner._signTypedData(domain, types, values);
        const sig = ethers.utils.splitSignature(signature);
        // verify the Permit type data with the signature
        /*
        const recovered = ethers.utils.verifyTypedData(
            domain,
            types,
            values,
            sig
        );*/
        await expect(await stogie.permit(owner.address, EOA, unlimited, deadline, sig.v, sig.r, sig.s)).to.emit(stogie, "Approval"); // make sure the sig passed
        await expect(stogie.permit(owner.address, EOA, unlimited, deadline, sig.v, sig.r, sig.s)).to.be.revertedWith("Stogie: INVALID_SIGNATURE"); // cannot reuse a sig

    });

    it("test eip-2612 wrapWithPermit", async function () {
        await stogie.onboard(owner.address, 1, false, false, {value: peth("10")});

        //let result = await stogie.farmers(owner.address);

        //await stogie.withdraw(result.deposit);
        let bal = await stogie.balanceOf(owner.address);
        await stogie.unwrap(bal);

        //const chainId = await hre.network.config.chainId;

        const domain = {
            name: await cigeth.name(),
            version: "1",
            chainId: 1,
            verifyingContract: cigeth.address
        };
        console.log("bal is: "+bal);

        // set the Permit type parameters
        const types = {
            Permit: [{
                name: "owner",
                type: "address"
            },
                {
                    name: "spender",
                    type: "address"
                },
                {
                    name: "value",
                    type: "uint256"
                },
                {
                    name: "nonce",
                    type: "uint256"
                },
                {
                    name: "deadline",
                    type: "uint256"
                },
            ],
        };
        const deadline = Math.floor(Date.now() / 1000) + 4200;
        // set the Permit type values
        const values = {
            owner: owner.address,
            spender: stogie.address,
            value: unlimited,
            nonce: await cigeth.nonces(owner.address),
            deadline: deadline,
        };
        console.log("nonce is:", await cigeth.nonces(owner.address));
        const signature = await owner._signTypedData(domain, types, values);
        const sig = ethers.utils.splitSignature(signature);

        await expect(await stogie.wrap(
            bal, // todo: support unlimited? shall we remove transfer stake?
            true, // unlimited
            deadline,
            sig.v,
            sig.r,
            sig.s)).to.emit(cigeth, "Approval");
    });

});

const WETH_ABI = [{"constant":true,"inputs":[],"name":"name","outputs":[{"name":"","type":"string"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"name":"guy","type":"address"},{"name":"wad","type":"uint256"}],"name":"approve","outputs":[{"name":"","type":"bool"}],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[],"name":"totalSupply","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"name":"src","type":"address"},{"name":"dst","type":"address"},{"name":"wad","type":"uint256"}],"name":"transferFrom","outputs":[{"name":"","type":"bool"}],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[{"name":"wad","type":"uint256"}],"name":"withdraw","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[],"name":"decimals","outputs":[{"name":"","type":"uint8"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"name":"","type":"address"}],"name":"balanceOf","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"symbol","outputs":[{"name":"","type":"string"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"name":"dst","type":"address"},{"name":"wad","type":"uint256"}],"name":"transfer","outputs":[{"name":"","type":"bool"}],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[],"name":"deposit","outputs":[],"payable":true,"stateMutability":"payable","type":"function"},{"constant":true,"inputs":[{"name":"","type":"address"},{"name":"","type":"address"}],"name":"allowance","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"payable":true,"stateMutability":"payable","type":"fallback"},{"anonymous":false,"inputs":[{"indexed":true,"name":"src","type":"address"},{"indexed":true,"name":"guy","type":"address"},{"indexed":false,"name":"wad","type":"uint256"}],"name":"Approval","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"src","type":"address"},{"indexed":true,"name":"dst","type":"address"},{"indexed":false,"name":"wad","type":"uint256"}],"name":"Transfer","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"dst","type":"address"},{"indexed":false,"name":"wad","type":"uint256"}],"name":"Deposit","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"src","type":"address"},{"indexed":false,"name":"wad","type":"uint256"}],"name":"Withdrawal","type":"event"}]

const CIG_ABI =  [{"inputs":[{"internalType":"uint256","name":"_cigPerBlock","type":"uint256"},{"internalType":"address","name":"_punks","type":"address"},{"internalType":"uint256","name":"_CEO_epoch_blocks","type":"uint256"},{"internalType":"uint256","name":"_CEO_auction_blocks","type":"uint256"},{"internalType":"uint256","name":"_CEO_price","type":"uint256"},{"internalType":"bytes32","name":"_graffiti","type":"bytes32"},{"internalType":"address","name":"_NFT","type":"address"},{"internalType":"address","name":"_V2ROUTER","type":"address"},{"internalType":"address","name":"_OC","type":"address"},{"internalType":"uint256","name":"_migration_epochs","type":"uint256"},{"internalType":"address","name":"_MASTERCHEF_V2","type":"address"}],"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"address","name":"spender","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Approval","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"called_by","type":"address"},{"indexed":false,"internalType":"uint256","name":"reward","type":"uint256"}],"name":"CEODefaulted","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"price","type":"uint256"}],"name":"CEOPriceChange","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"ChefDeposit","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"ChefWithdraw","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"uint256","name":"punkIndex","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Claim","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"Deposit","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"EmergencyWithdraw","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"Harvest","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":true,"internalType":"uint256","name":"punk_id","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"new_price","type":"uint256"},{"indexed":false,"internalType":"bytes32","name":"graffiti","type":"bytes32"}],"name":"NewCEO","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"RevenueBurned","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"reward","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"downAmount","type":"uint256"}],"name":"RewardDown","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"reward","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"upAmount","type":"uint256"}],"name":"RewardUp","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"TaxBurned","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"TaxDeposit","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"from","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Transfer","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"Withdraw","type":"event"},{"inputs":[],"name":"CEO_price","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"CEO_punk_index","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"CEO_state","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"CEO_tax_balance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"The_CEO","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"accCigPerShare","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"admin","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"},{"internalType":"address","name":"","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_spender","type":"address"},{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"burnTax","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_max_spend","type":"uint256"},{"internalType":"uint256","name":"_new_price","type":"uint256"},{"internalType":"uint256","name":"_tax_amount","type":"uint256"},{"internalType":"uint256","name":"_punk_index","type":"uint256"},{"internalType":"bytes32","name":"_graffiti","type":"bytes32"}],"name":"buyCEO","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"cigPerBlock","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_punkIndex","type":"uint256"}],"name":"claim","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"}],"name":"claims","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"decimals","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"deposit","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"depositTax","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"emergencyWithdraw","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"farmers","outputs":[{"internalType":"uint256","name":"deposit","type":"uint256"},{"internalType":"uint256","name":"rewardDebt","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"farmersMasterchef","outputs":[{"internalType":"uint256","name":"deposit","type":"uint256"},{"internalType":"uint256","name":"rewardDebt","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_user","type":"address"}],"name":"getStats","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"},{"internalType":"address","name":"","type":"address"},{"internalType":"bytes32","name":"","type":"bytes32"},{"internalType":"uint112[]","name":"","type":"uint112[]"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"graffiti","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"harvest","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_punkIndex","type":"uint256"}],"name":"isClaimed","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"lastRewardBlock","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"lpToken","outputs":[{"internalType":"contract ILiquidityPoolERC20","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"masterchefDeposits","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"migrationComplete","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"name","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"address","name":"_user","type":"address"},{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_sushiAmount","type":"uint256"},{"internalType":"uint256","name":"_newLpAmount","type":"uint256"}],"name":"onSushiReward","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_user","type":"address"}],"name":"pendingCig","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"punks","outputs":[{"internalType":"contract ICryptoPunk","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"renounceOwnership","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"rewardDown","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"rewardUp","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"rewardsChangedBlock","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"contract ILiquidityPoolERC20","name":"_addr","type":"address"}],"name":"setPool","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_price","type":"uint256"}],"name":"setPrice","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"setReward","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_startBlock","type":"uint256"}],"name":"setStartingBlock","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"stakedlpSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"symbol","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"taxBurnBlock","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"totalSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"transfer","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_from","type":"address"},{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"transferFrom","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"unwrap","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"update","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"address","name":"_user","type":"address"}],"name":"userInfo","outputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"uint256","name":"depositAmount","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"wBal","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"withdraw","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"wrap","outputs":[],"stateMutability":"nonpayable","type":"function"}];

const SLP_ABI = [{"inputs":[],"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"address","name":"spender","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Approval","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount0","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1","type":"uint256"},{"indexed":true,"internalType":"address","name":"to","type":"address"}],"name":"Burn","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount0","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1","type":"uint256"}],"name":"Mint","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount0In","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1In","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount0Out","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1Out","type":"uint256"},{"indexed":true,"internalType":"address","name":"to","type":"address"}],"name":"Swap","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint112","name":"reserve0","type":"uint112"},{"indexed":false,"internalType":"uint112","name":"reserve1","type":"uint112"}],"name":"Sync","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"from","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Transfer","type":"event"},{"inputs":[],"name":"DOMAIN_SEPARATOR","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"MINIMUM_LIQUIDITY","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"PERMIT_TYPEHASH","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"},{"internalType":"address","name":"","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"burn","outputs":[{"internalType":"uint256","name":"amount0","type":"uint256"},{"internalType":"uint256","name":"amount1","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"decimals","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"factory","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"getReserves","outputs":[{"internalType":"uint112","name":"_reserve0","type":"uint112"},{"internalType":"uint112","name":"_reserve1","type":"uint112"},{"internalType":"uint32","name":"_blockTimestampLast","type":"uint32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_token0","type":"address"},{"internalType":"address","name":"_token1","type":"address"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"kLast","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"mint","outputs":[{"internalType":"uint256","name":"liquidity","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"name","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"nonces","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"},{"internalType":"uint256","name":"deadline","type":"uint256"},{"internalType":"uint8","name":"v","type":"uint8"},{"internalType":"bytes32","name":"r","type":"bytes32"},{"internalType":"bytes32","name":"s","type":"bytes32"}],"name":"permit","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"price0CumulativeLast","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"price1CumulativeLast","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"skim","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amount0Out","type":"uint256"},{"internalType":"uint256","name":"amount1Out","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"bytes","name":"data","type":"bytes"}],"name":"swap","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"symbol","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"sync","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"token0","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"token1","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"totalSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"}],"name":"transfer","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"from","type":"address"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"}],"name":"transferFrom","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"}];

const v2RouterAddress = "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F";
const v2RouterABI = [{"inputs":[{"internalType":"address","name":"_factory","type":"address"},{"internalType":"address","name":"_WETH","type":"address"}],"stateMutability":"nonpayable","type":"constructor"},{"inputs":[],"name":"WETH","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"tokenA","type":"address"},{"internalType":"address","name":"tokenB","type":"address"},{"internalType":"uint256","name":"amountADesired","type":"uint256"},{"internalType":"uint256","name":"amountBDesired","type":"uint256"},{"internalType":"uint256","name":"amountAMin","type":"uint256"},{"internalType":"uint256","name":"amountBMin","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"addLiquidity","outputs":[{"internalType":"uint256","name":"amountA","type":"uint256"},{"internalType":"uint256","name":"amountB","type":"uint256"},{"internalType":"uint256","name":"liquidity","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"token","type":"address"},{"internalType":"uint256","name":"amountTokenDesired","type":"uint256"},{"internalType":"uint256","name":"amountTokenMin","type":"uint256"},{"internalType":"uint256","name":"amountETHMin","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"addLiquidityETH","outputs":[{"internalType":"uint256","name":"amountToken","type":"uint256"},{"internalType":"uint256","name":"amountETH","type":"uint256"},{"internalType":"uint256","name":"liquidity","type":"uint256"}],"stateMutability":"payable","type":"function"},{"inputs":[],"name":"factory","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountOut","type":"uint256"},{"internalType":"uint256","name":"reserveIn","type":"uint256"},{"internalType":"uint256","name":"reserveOut","type":"uint256"}],"name":"getAmountIn","outputs":[{"internalType":"uint256","name":"amountIn","type":"uint256"}],"stateMutability":"pure","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountIn","type":"uint256"},{"internalType":"uint256","name":"reserveIn","type":"uint256"},{"internalType":"uint256","name":"reserveOut","type":"uint256"}],"name":"getAmountOut","outputs":[{"internalType":"uint256","name":"amountOut","type":"uint256"}],"stateMutability":"pure","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountOut","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"}],"name":"getAmountsIn","outputs":[{"internalType":"uint256[]","name":"amounts","type":"uint256[]"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountIn","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"}],"name":"getAmountsOut","outputs":[{"internalType":"uint256[]","name":"amounts","type":"uint256[]"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountA","type":"uint256"},{"internalType":"uint256","name":"reserveA","type":"uint256"},{"internalType":"uint256","name":"reserveB","type":"uint256"}],"name":"quote","outputs":[{"internalType":"uint256","name":"amountB","type":"uint256"}],"stateMutability":"pure","type":"function"},{"inputs":[{"internalType":"address","name":"tokenA","type":"address"},{"internalType":"address","name":"tokenB","type":"address"},{"internalType":"uint256","name":"liquidity","type":"uint256"},{"internalType":"uint256","name":"amountAMin","type":"uint256"},{"internalType":"uint256","name":"amountBMin","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"removeLiquidity","outputs":[{"internalType":"uint256","name":"amountA","type":"uint256"},{"internalType":"uint256","name":"amountB","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"token","type":"address"},{"internalType":"uint256","name":"liquidity","type":"uint256"},{"internalType":"uint256","name":"amountTokenMin","type":"uint256"},{"internalType":"uint256","name":"amountETHMin","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"removeLiquidityETH","outputs":[{"internalType":"uint256","name":"amountToken","type":"uint256"},{"internalType":"uint256","name":"amountETH","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"token","type":"address"},{"internalType":"uint256","name":"liquidity","type":"uint256"},{"internalType":"uint256","name":"amountTokenMin","type":"uint256"},{"internalType":"uint256","name":"amountETHMin","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"removeLiquidityETHSupportingFeeOnTransferTokens","outputs":[{"internalType":"uint256","name":"amountETH","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"token","type":"address"},{"internalType":"uint256","name":"liquidity","type":"uint256"},{"internalType":"uint256","name":"amountTokenMin","type":"uint256"},{"internalType":"uint256","name":"amountETHMin","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"},{"internalType":"bool","name":"approveMax","type":"bool"},{"internalType":"uint8","name":"v","type":"uint8"},{"internalType":"bytes32","name":"r","type":"bytes32"},{"internalType":"bytes32","name":"s","type":"bytes32"}],"name":"removeLiquidityETHWithPermit","outputs":[{"internalType":"uint256","name":"amountToken","type":"uint256"},{"internalType":"uint256","name":"amountETH","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"token","type":"address"},{"internalType":"uint256","name":"liquidity","type":"uint256"},{"internalType":"uint256","name":"amountTokenMin","type":"uint256"},{"internalType":"uint256","name":"amountETHMin","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"},{"internalType":"bool","name":"approveMax","type":"bool"},{"internalType":"uint8","name":"v","type":"uint8"},{"internalType":"bytes32","name":"r","type":"bytes32"},{"internalType":"bytes32","name":"s","type":"bytes32"}],"name":"removeLiquidityETHWithPermitSupportingFeeOnTransferTokens","outputs":[{"internalType":"uint256","name":"amountETH","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"tokenA","type":"address"},{"internalType":"address","name":"tokenB","type":"address"},{"internalType":"uint256","name":"liquidity","type":"uint256"},{"internalType":"uint256","name":"amountAMin","type":"uint256"},{"internalType":"uint256","name":"amountBMin","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"},{"internalType":"bool","name":"approveMax","type":"bool"},{"internalType":"uint8","name":"v","type":"uint8"},{"internalType":"bytes32","name":"r","type":"bytes32"},{"internalType":"bytes32","name":"s","type":"bytes32"}],"name":"removeLiquidityWithPermit","outputs":[{"internalType":"uint256","name":"amountA","type":"uint256"},{"internalType":"uint256","name":"amountB","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountOut","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"swapETHForExactTokens","outputs":[{"internalType":"uint256[]","name":"amounts","type":"uint256[]"}],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountOutMin","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"swapExactETHForTokens","outputs":[{"internalType":"uint256[]","name":"amounts","type":"uint256[]"}],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountOutMin","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"swapExactETHForTokensSupportingFeeOnTransferTokens","outputs":[],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountIn","type":"uint256"},{"internalType":"uint256","name":"amountOutMin","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"swapExactTokensForETH","outputs":[{"internalType":"uint256[]","name":"amounts","type":"uint256[]"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountIn","type":"uint256"},{"internalType":"uint256","name":"amountOutMin","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"swapExactTokensForETHSupportingFeeOnTransferTokens","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountIn","type":"uint256"},{"internalType":"uint256","name":"amountOutMin","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"swapExactTokensForTokens","outputs":[{"internalType":"uint256[]","name":"amounts","type":"uint256[]"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountIn","type":"uint256"},{"internalType":"uint256","name":"amountOutMin","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"swapExactTokensForTokensSupportingFeeOnTransferTokens","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountOut","type":"uint256"},{"internalType":"uint256","name":"amountInMax","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"swapTokensForExactETH","outputs":[{"internalType":"uint256[]","name":"amounts","type":"uint256[]"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountOut","type":"uint256"},{"internalType":"uint256","name":"amountInMax","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"swapTokensForExactTokens","outputs":[{"internalType":"uint256[]","name":"amounts","type":"uint256[]"}],"stateMutability":"nonpayable","type":"function"},{"stateMutability":"payable","type":"receive"}];



