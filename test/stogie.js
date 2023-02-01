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



describe("Stogie", function () {
    let owner, simp, elizabeth, tycoon, impersonatedSigner; // accounts
    let pool, Stogie, stogie, cig, cigeth; // contracts
    let feth = utils.formatEther;
    let peth = utils.parseEther;
    let cards, EmployeeIDCards;
    const EOA = "0xc43473fa66237e9af3b2d886ee1205b81b14b2c8"; // EOA that has ETH and CIG to impersonate
    const CIG_ADDRESS = "0xcb56b52316041a62b6b5d0583dce4a8ae7a3c629"; // cig on mainnet
    const CIGETH_SLP_ADDRESS = "0x22b15c7Ee1186A7C7CFfB2D942e20Fc228F6E4Ed";

    before(async function () {
        // assuming we are at block 14148801

        [owner, simp, elizabeth] = await ethers.getSigners();
        cig = await hre.ethers.getContractAt(CIG_ABI,  CIG_ADDRESS);

        //[owner, simp, elizabeth] = await ethers.getSigners();
        cigeth = await hre.ethers.getContractAt(SLP_ABI,  CIGETH_SLP_ADDRESS);

        EmployeeIDCards = await ethers.getContractFactory("EmployeeIDCards");
        cards = await EmployeeIDCards.deploy();
        await cards.deployed();

        // deploy stogie
        Stogie = await ethers.getContractFactory("Stogie");
        stogie = await Stogie.deploy(
            CIG_ADDRESS, // cig on mainnet
            "0x22b15c7ee1186a7c7cffb2d942e20fc228f6e4ed", // Sushi SLP
            "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F", // sushi router
            "0xc0aee478e3658e2610c5f7a4a2e1777ce9e4f2ac", // sushi factory
            "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // uniswap router
            "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", // weth
            cards.address
        );
        await stogie.deployed();


        //await helpers.impersonateAccount(EOA);
        //let impersonatedSigner = await ethers.getSigner(EOA);


        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [EOA],
        });
        tycoon = await ethers.provider.getSigner(EOA);
//        console.log(tycoon, cig.address, tycoon.address, impersonatedSigner);

    });

    it("init the stogie", async function () {
/*
        await tycoon.sendTransaction({
            to: "0x0000000000000000000000000000000000000000",
            value: ethers.utils.parseEther("0.01"),
        });
*/
        console.log("pending cig: " + await cig.connect(tycoon).pendingCig(EOA));

        // harvest
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
        r.stogieBal = s2[4];// user's STOG balance
        r.cigBal = cigdata[15];// user's CIG balance
        r.slpBal = cigdata[16];// user's CIG/ETH SLP balance
        r.slpContractBal = s2[3]; // contract CIG/ETH SLP balance
        r.slpEthReserve = reserves[0]; // CIG/ETH SLP reserves, ETH
        r.slpCigReserve = reserves[1]; // CIG reserve is slp
        r.lastRewardBlock = s2[5]; // when rewards were last calculated
        r.accCigPerShare = s2[6]; // accumulated CIG per STOG share
        r.pendingCig = s2[7]; // pending CIG reward to be harvested
        r.wethBal = s2[8]; // user's WETH balance
        r.ethBal = s2[9]; // user's ETH balance
        r.cigContractApproval = s2[10]; // user's approval for Stogies to spend their CIG
        r.slpContractApproval = s2[11]; // user's approval for Stogies to spend CIG/ETH SLP
        r.ethContractApproval = s2[12]; // user's approval for stogies to spend WETH
        r.blockNumber = cigdata[9]; // current block number
        r.ethPriceInCig = s2[14]; // How much CIG for 1 ETH (ETH price in CIG)
        r.ethdaiETHRes = s2[15]; // DAI reserves of WETH/DAI
        r.ethdaiDAIRes = s2[16]; // WETH reserves of WETH/DAI
        r.ethPriceInUsd = s2[17]; // ETH price in USD
        r.slpSupply = cigdata[22]; // total supply of CIG/ETH SLP
        r.stogieSupply = s2[13];
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

        let portion = BigNumber.from(getSwapAmount(BigInt(deposit.toString()), BigInt(stats.slpEthReserve)));


        q = getAmountOut(portion, stats.slpEthReserve, stats.slpCigReserve);

        //let amountETHMin = q.sub(portion.div(BigNumber.from("1000").mul(BigNumber.from("100")))) ;
        //const SCALE = BigNumber.from("1000"); // 100 * 10
        //let percent = BigNumber.from("900"); // scale by 10 (100 = 10%)
        // 900 = 90% , 10 = 1%
        let amountCIGMin = q.sub(q.mul(BigNumber.from("10")).div(BigNumber.from("1000"))) ;
       // amountCIGMin = q.sub(portion.mul(BigNumber.from("10000000")).div(BigNumber.from("1000"))) ;

        console.log("portion:"+feth(portion));
        console.log("q:"+feth(q));
        console.log("reserve js:"+stats.slpEthReserve);
        console.log("amountCIGMin", feth(amountCIGMin));


        let ts = Math.floor(Date.now() / 1000);
        console.log("CIG bal of stogie:::::::"+await cig.balanceOf(stogie.address));
        expect(await stogie.connect(tycoon)
            .depositWithETH(
                peth("1"),
                BigNumber.from(ts+60),
                false,
                {value: deposit})
        ).to.emit(stogie, "Deposit");



        console.log("CIG bal of stogie:::::::"+await cig.balanceOf(stogie.address));
        console.log("ETH bal of stogie:::::::"+await ethers.provider.getBalance(stogie.address));
        // sanity check
        let stats2 = await getStats(EOA);
        let lpDeposited = BigNumber.from(stats2.stakeDeposit);
        console.log("lp deposited:", feth(lpDeposited));
        expect(lpDeposited).to.greaterThan(BigNumber.from(0)); // we have deposited

        console.log(stats2);

        //console.log("b"+await stogie.doNothing());
        //console.log("c"+await stogie.doNothing());

        let pending = await stogie.connect(tycoon).pendingCig(EOA);
        console.log("Pending CIGGGGGGGGGGGGGGG:", pending);

        // harvest time
        expect(await stogie.connect(tycoon).harvest()).to.emit(stogie, "Harvest");
        let stats3 = await getStats(EOA);
        //expect(parseInt(stats3.cigBal)).to.greaterThan(parseInt(stats2.cigBal)); // cig balance should increase


        console.log("1. CIG increased by:"+feth(BigNumber.from(stats3.cigBal).sub(BigNumber.from(stats2.cigBal))));
       ////
        await stogie.connect(tycoon).update();

       ///
        stats2 = await getStats(EOA);
        expect(await stogie.connect(tycoon).harvest()).to.emit(stogie, "Harvest");
        stats3 = await getStats(EOA);
        //expect(parseInt(stats3.cigBal)).to.greaterThan(parseInt(stats2.cigBal)); // cig balance should increase
        console.log("2. CIG increased by:"+feth(BigNumber.from(stats3.cigBal).sub(BigNumber.from(stats2.cigBal))));

        // test withdraw
        expect(await stogie.connect(tycoon).withdraw(BigNumber.from(stats3.stakeDeposit))).to.emit(stogie, "Withdraw");
        expect(await stogie.connect(tycoon).balanceOf(EOA)).to.equal(lpDeposited);
        return;

    });

    it("output the reserves of the pool", async function () {
        // get the reserves at block 14148801
        /*
        let [r0, r1, ] = await pool.getReserves();
        console.log("r0: " + feth(r0) + " r1: " + feth(r1));

        console.log("total LP supply: " + feth(await pool.totalSupply()));
        console.log("total LP supply: " + (await pool.totalSupply()));

         */
    });

});

const CIG_ABI =  [{"inputs":[{"internalType":"uint256","name":"_cigPerBlock","type":"uint256"},{"internalType":"address","name":"_punks","type":"address"},{"internalType":"uint256","name":"_CEO_epoch_blocks","type":"uint256"},{"internalType":"uint256","name":"_CEO_auction_blocks","type":"uint256"},{"internalType":"uint256","name":"_CEO_price","type":"uint256"},{"internalType":"bytes32","name":"_graffiti","type":"bytes32"},{"internalType":"address","name":"_NFT","type":"address"},{"internalType":"address","name":"_V2ROUTER","type":"address"},{"internalType":"address","name":"_OC","type":"address"},{"internalType":"uint256","name":"_migration_epochs","type":"uint256"},{"internalType":"address","name":"_MASTERCHEF_V2","type":"address"}],"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"address","name":"spender","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Approval","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"called_by","type":"address"},{"indexed":false,"internalType":"uint256","name":"reward","type":"uint256"}],"name":"CEODefaulted","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"price","type":"uint256"}],"name":"CEOPriceChange","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"ChefDeposit","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"ChefWithdraw","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"uint256","name":"punkIndex","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Claim","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"Deposit","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"EmergencyWithdraw","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"Harvest","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":true,"internalType":"uint256","name":"punk_id","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"new_price","type":"uint256"},{"indexed":false,"internalType":"bytes32","name":"graffiti","type":"bytes32"}],"name":"NewCEO","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"RevenueBurned","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"reward","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"downAmount","type":"uint256"}],"name":"RewardDown","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"reward","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"upAmount","type":"uint256"}],"name":"RewardUp","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"TaxBurned","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"TaxDeposit","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"from","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Transfer","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"Withdraw","type":"event"},{"inputs":[],"name":"CEO_price","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"CEO_punk_index","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"CEO_state","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"CEO_tax_balance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"The_CEO","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"accCigPerShare","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"admin","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"},{"internalType":"address","name":"","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_spender","type":"address"},{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"burnTax","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_max_spend","type":"uint256"},{"internalType":"uint256","name":"_new_price","type":"uint256"},{"internalType":"uint256","name":"_tax_amount","type":"uint256"},{"internalType":"uint256","name":"_punk_index","type":"uint256"},{"internalType":"bytes32","name":"_graffiti","type":"bytes32"}],"name":"buyCEO","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"cigPerBlock","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_punkIndex","type":"uint256"}],"name":"claim","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"}],"name":"claims","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"decimals","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"deposit","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"depositTax","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"emergencyWithdraw","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"farmers","outputs":[{"internalType":"uint256","name":"deposit","type":"uint256"},{"internalType":"uint256","name":"rewardDebt","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"farmersMasterchef","outputs":[{"internalType":"uint256","name":"deposit","type":"uint256"},{"internalType":"uint256","name":"rewardDebt","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_user","type":"address"}],"name":"getStats","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"},{"internalType":"address","name":"","type":"address"},{"internalType":"bytes32","name":"","type":"bytes32"},{"internalType":"uint112[]","name":"","type":"uint112[]"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"graffiti","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"harvest","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_punkIndex","type":"uint256"}],"name":"isClaimed","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"lastRewardBlock","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"lpToken","outputs":[{"internalType":"contract ILiquidityPoolERC20","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"masterchefDeposits","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"migrationComplete","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"name","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"address","name":"_user","type":"address"},{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_sushiAmount","type":"uint256"},{"internalType":"uint256","name":"_newLpAmount","type":"uint256"}],"name":"onSushiReward","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_user","type":"address"}],"name":"pendingCig","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"punks","outputs":[{"internalType":"contract ICryptoPunk","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"renounceOwnership","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"rewardDown","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"rewardUp","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"rewardsChangedBlock","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"contract ILiquidityPoolERC20","name":"_addr","type":"address"}],"name":"setPool","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_price","type":"uint256"}],"name":"setPrice","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"setReward","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_startBlock","type":"uint256"}],"name":"setStartingBlock","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"stakedlpSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"symbol","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"taxBurnBlock","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"totalSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"transfer","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_from","type":"address"},{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"transferFrom","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"unwrap","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"update","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"address","name":"_user","type":"address"}],"name":"userInfo","outputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"uint256","name":"depositAmount","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"wBal","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"withdraw","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"wrap","outputs":[],"stateMutability":"nonpayable","type":"function"}];

const SLP_ABI = [{"inputs":[],"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"address","name":"spender","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Approval","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount0","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1","type":"uint256"},{"indexed":true,"internalType":"address","name":"to","type":"address"}],"name":"Burn","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount0","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1","type":"uint256"}],"name":"Mint","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount0In","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1In","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount0Out","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1Out","type":"uint256"},{"indexed":true,"internalType":"address","name":"to","type":"address"}],"name":"Swap","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint112","name":"reserve0","type":"uint112"},{"indexed":false,"internalType":"uint112","name":"reserve1","type":"uint112"}],"name":"Sync","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"from","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Transfer","type":"event"},{"inputs":[],"name":"DOMAIN_SEPARATOR","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"MINIMUM_LIQUIDITY","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"PERMIT_TYPEHASH","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"},{"internalType":"address","name":"","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"burn","outputs":[{"internalType":"uint256","name":"amount0","type":"uint256"},{"internalType":"uint256","name":"amount1","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"decimals","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"factory","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"getReserves","outputs":[{"internalType":"uint112","name":"_reserve0","type":"uint112"},{"internalType":"uint112","name":"_reserve1","type":"uint112"},{"internalType":"uint32","name":"_blockTimestampLast","type":"uint32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_token0","type":"address"},{"internalType":"address","name":"_token1","type":"address"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"kLast","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"mint","outputs":[{"internalType":"uint256","name":"liquidity","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"name","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"nonces","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"},{"internalType":"uint256","name":"deadline","type":"uint256"},{"internalType":"uint8","name":"v","type":"uint8"},{"internalType":"bytes32","name":"r","type":"bytes32"},{"internalType":"bytes32","name":"s","type":"bytes32"}],"name":"permit","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"price0CumulativeLast","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"price1CumulativeLast","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"skim","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amount0Out","type":"uint256"},{"internalType":"uint256","name":"amount1Out","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"bytes","name":"data","type":"bytes"}],"name":"swap","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"symbol","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"sync","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"token0","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"token1","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"totalSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"}],"name":"transfer","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"from","type":"address"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"}],"name":"transferFrom","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"}];



