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
    let punks;
    let owner, simp, elizabeth;
    let NFTMock;
    let nft, oldNft;
    const BLOCK_REWARD = '5';
    const CEO_EPOCH_BLOCKS = 5000;
    const CEO_AUCTION_BLOCKS = 5;
    const MIGRATION_EPOCHS = 1;
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
    let router, factory;
    let balances = {
        "owner" : BigNumber.from("0"),
        "simp" : BigNumber.from("0"),
        "elizabeth" : BigNumber.from("0")
    }
    let pair, lp;
    const unlimited = BigNumber.from("2").pow(BigNumber.from("256")).sub(BigNumber.from("1")); // 2**256 - 1
    const burner = "0x0000000000000000000000000000000000000000";
    const WETH_Address = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
    const PUNKS_ADDRESS = "0xb47e3cd837ddf8e4c57f05d70ab865de6e193bbb";

    before(async function () {
        [owner, simp, elizabeth] = await ethers.getSigners();
        oldCig =  await hre.ethers.getContractAt("OldCig", OLD_CIG);
        let oldCigPerBlock = await oldCig.cigPerBlock();
        console.log("old issuance is "+ feth(oldCigPerBlock));
        punks = await hre.ethers.getContractAt(PUNKS_ABI,  PUNKS_ADDRESS);
        // deploy the NFT contract
        NFTMock = await ethers.getContractFactory("NonFungibleCEO");
        nft = await NFTMock.deploy(ASSET_URL);
        await nft.deployed();
        // Deploy the new NFT contract
        CigToken = await ethers.getContractFactory("Cig");
        cig = await CigToken.deploy(
            oldCigPerBlock, // Old Cig "cigPerBlock must be near this value"
            punks.address,
            CEO_EPOCH_BLOCKS,
            CEO_AUCTION_BLOCKS,
            utils.parseEther(CEO_BUY_PRICE),
            graff32,
            nft.address,
            v2RouterAddress,
            OLD_CIG,
            MIGRATION_EPOCHS,
            MSV2
        );
        await cig.deployed();
        // tell the NFT contract about the cig token
        await nft.setCigToken(cig.address);
        //await nft.setBaseURI(ASSET_URL); // onlyCEO
        // test burning of keys
        await nft.renounceOwnership();
        await expect(nft.setBaseURI(ASSET_URL)).to.be.revertedWith('must be called by CEO');
        // owner will buy some old CIG from the pool for testing
        router =  await hre.ethers.getContractAt(v2RouterABI, v2RouterAddress);
        await router.swapExactETHForTokens(
            peth("10"), // amountOutMin
            [WETH_Address, oldCig.address],
            owner.address,
            Math.floor(Date.now() / 1000) + 1200, // deadline + 20 min
            {
                value: peth("10")
            }
        );
        balances.owner = await oldCig.balanceOf(owner.address);
        console.log("owner scored "+ feth(balances.owner)+ " CIG from Sushi!");
    });

    describe("Deployment", function () {
        it("Should be in migration state", async function () {
            expect(await cig.CEO_state()).to.be.equal("3");
            // 13974859 is the block we forked from
            let expected = 13974859 + (CEO_EPOCH_BLOCKS * MIGRATION_EPOCHS) + 2; // plus how many tx already
            expect(await cig.lastRewardBlock()).to.be.equal(expected);
        });
        it("should mint new cig tokens when old cig is wrapped", async function () {
            await expect (cig.wrap(balances.owner)).to.be.revertedWith("not approved");
            await oldCig.approve(cig.address, unlimited);
            let val = balances.owner.div(10);
             expect(await cig.wrap(val))
                 // mint new cig
                .to.emit(cig, "Transfer").withArgs(burner, owner.address, val)
                 // transfer new cig to new cig contract
                .to.emit(oldCig, "Transfer").withArgs(owner.address, cig.address, val);
             expect(await cig.totalSupply()).to.be.equal(val); // ensure supply increased
             expect(await cig.wBal(owner.address)).to.be.equal(val); // ensure deposit is recorded
            await expect(cig.wrap(unlimited)).to.be.revertedWith(""); // overflow
        });

        it("should get the old cig tokens back from new cig", async function () {
            let bal = await cig.wBal(owner.address);
            expect(await cig.unwrap(bal))
                // new cig gets burned
                .to.emit(cig, "Transfer").withArgs(owner.address, burner, bal)
                // old cig gets given back
                .to.emit(oldCig, "Transfer").withArgs(cig.address, owner.address, bal);
            expect(await cig.totalSupply()).to.be.equal(0); // ensure supply decreased back to 0
            expect(await cig.wBal(owner.address)).to.be.equal(0); // ensure deposit was cleared
            await expect( cig.unwrap(1)).to.be.reverted // cannot withdraw what we do not have (overflow_
        });

        it("claims disabled in migration", async function () {
            await expect(cig.claim(69)).to.be.revertedWith("invalid state");
        });

        it("create and seed the new cig pool", async function () {
            factory =  await hre.ethers.getContractAt(v2FactoryABI, v2FactoryAddress);
            let tx = await factory.createPair(
                WETH_Address,
                cig.address
            );
            const res = await tx.wait();
            pair = res.events[0].args[2]; // the pair is returned as an event
            console.log("created pair:" + pair);
            await cig.setPool(pair);
            expect(await cig.lpToken()).to.equal(pair);
            let [stats, The_CEO, graff] = await oldCig.getStats(owner.address); // use stats to get the price of CIG
            // deposit old cig for migration
            expect(await cig.wrap(balances.owner))
                // mint new cig
                .to.emit(cig, "Transfer").withArgs(burner, owner.address, balances.owner)
                // transfer new cig to new cig contract
                .to.emit(oldCig, "Transfer").withArgs(owner.address, cig.address, balances.owner);
            // approve new cig to router
            expect(await cig.approve(router.address, unlimited)).to.emit(cig, "Approval");
            let ethAmount = balances.owner.mul(stats[18]).div("1000000000000000000");
            console.log("ba: " + feth(balances.owner) + " Eth amount:" + feth(ethAmount) + " p:" +  feth(stats[18]));
            tx = await router.addLiquidityETH(
                cig.address,
                balances.owner,
                balances.owner,
                ethAmount,
                owner.address,
                Math.floor(Date.now() / 1000) + 1200,
                {value : peth("12")}
            );
            let result = await tx.wait();
           //console.log("LP receipt: " + JSON.stringify(result));
            lp = await hre.ethers.getContractAt(LP_ABI, pair);
            let bal = await lp.balanceOf(owner.address);
            console.log("LP balance: " + feth(bal));
            expect(await lp.approve(cig.address, unlimited)).to.emit(lp, "Approval");
            expect(await cig.deposit(bal)).to.emit(cig, "Deposit"); // should deposit
            await expect(cig.deposit(BigNumber.from("0"))).to.be.revertedWith("You cannot deposit only 0 tokens"); // no rewards
        });

        it("trigger migration", async function () {
            //throw new Error("production environment! Aborting!");
            let start = await cig.lastRewardBlock();
            let b = await ethers.provider.getBlockNumber();
            let toWait = start.sub(b);
            console.log("blocks to wait: " + toWait);
            for (let i = 0; i < toWait; i++) {
               if (i % 100 === 0) console.log(i);
                await expect(cig.migrationComplete()).to.be.revertedWith("cannot end migration yet");
            }
            let oldBal = await oldCig.balanceOf(punks.address);
            console.log(feth(oldBal));
            // make sure the NFT was transferred
            expect(await cig.migrationComplete())
                .to.emit(nft, "Transfer").withArgs(burner, "0x1e32a859d69dde58d03820F8f138C99B688D132F", 0)
                .to.emit(cig, "Transfer");
            let [oldStats, oldThe_CEO, oldGraff] = await oldCig.getStats(owner.address);
            let [newStats, newThe_CEO, newGraff] = await cig.getStats(owner.address);
            expect(oldGraff).to.be.equal(newGraff);
            expect(oldThe_CEO).to.be.equal(newThe_CEO);
            expect(oldStats[0]).to.be.equal(newStats[0]);
            expect(oldStats[1]).to.be.equal(newStats[1]);
            expect(oldStats[2]).to.be.equal(newStats[2]);
            expect(oldStats[3]).to.be.equal(newStats[3]);
            expect(oldStats[4]).to.be.equal(newStats[4]);
            expect(oldStats[5]).to.be.equal(newStats[5]);
            expect(oldStats[6]).to.be.not.equal(newStats[6]); // cig per block
            expect(oldStats[16]).to.be.equal(newStats[16]);
            expect(oldStats[21]).to.be.equal(newStats[21]);

            console.log("CEO deposit after migration:" + feth(await(cig.CEO_tax_balance())));
            // todo inspect state to ensure all migrated
            expect(await cig.balanceOf(punks.address)).to.be.equal(oldBal); // claim balance transferred
        });
        it("should claim punks", async function () {

            let punksBought = [];
            // buy some punks first
            for (let i = 8000; i < 8050; i++) {
                let result = await  punks.punksOfferedForSale(i);
                //console.log(result);
                if (result["isForSale"] === true && result["onlySellTo"] === "0x0000000000000000000000000000000000000000" ) {
                    console.log(feth(result["minValue"]));
                    if (result["minValue"].lte(peth("300"))) {
                        isClaimed = await oldCig.claims(i);
                        if (!isClaimed) {
                            console.log("punk not claimed yet");
                            await punks.buyPunk(i, {value : result["minValue"]});
                            expect(await cig.claim(i)).to.emit(cig, "Claim");
                            break;
                        }
                    }
                } else {
                    console.log("punk nfs");
                }
            }
        });

        it("should farm", async function () {
            let a = await cig.balanceOf(owner.address);
            console.log("balance before harvest:", feth(a));
            await expect( cig.harvest()).to.emit(cig, "Transfer");
            let b = await cig.balanceOf(owner.address);
            console.log("balance after harvest:", feth(b));
            expect(await b.gt(a)).to.be.equal(true);

            // send some cig to ceo
            let ceo = await cig.The_CEO();
            await expect(cig.transfer(ceo, b)).to.emit(cig, "Transfer");
            console.log("AFTER transfer:" + feth(await(cig.balanceOf(ceo))));
        });

        it("should buy ceo", async function () {

            let ceo = await cig.The_CEO();
            console.log("ceo is:", ceo);
            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [ceo],
            });

            let signer = await ethers.provider.getSigner(
                ceo
            );

            console.log("ceo has:" + feth(await(cig.balanceOf(ceo))));
            console.log("CEO deposit:" + feth(await(cig.CEO_tax_balance())));
            // set to a ver low price
            await expect(cig.connect(signer).setPrice(peth("100"))).to.emit(cig, "CEOPriceChange");

            let graff32 = new Uint8Array(32);
            let graffiti = "hello world";
            for (let i = 0; i < graffiti.length; i++) {
                graff32[i] = graffiti.charCodeAt(i);
            }
            console.log("state is: " + await cig.CEO_state());

            // 68656c6c6f20776f726c64000000000000000000000000000000000000000000
            console.log("graff is: "+Buffer.from(graff32).toString('hex'));

            await expect( cig.harvest()).to.emit(cig, "Transfer"); // grab some cig

            let [newStats, newThe_CEO, newGraff] = await cig.getStats(owner.address);
            let price = newStats[4];
            let tax = peth("10");
            let max = price.add(tax);
            console.log("CEO price is:" + feth(price), " You have:" +  feth(await cig.balanceOf(owner.address)));
            // max_spend, new_price, tax
            await expect(cig.buyCEO(max, price, tax, 4513, graff32)).to.emit(cig,"NewCEO");

        });

    });

});


// Sushiswap v2 router
const v2RouterAddress = "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F";
const v2RouterABI = [{"inputs":[{"internalType":"address","name":"_factory","type":"address"},{"internalType":"address","name":"_WETH","type":"address"}],"stateMutability":"nonpayable","type":"constructor"},{"inputs":[],"name":"WETH","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"tokenA","type":"address"},{"internalType":"address","name":"tokenB","type":"address"},{"internalType":"uint256","name":"amountADesired","type":"uint256"},{"internalType":"uint256","name":"amountBDesired","type":"uint256"},{"internalType":"uint256","name":"amountAMin","type":"uint256"},{"internalType":"uint256","name":"amountBMin","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"addLiquidity","outputs":[{"internalType":"uint256","name":"amountA","type":"uint256"},{"internalType":"uint256","name":"amountB","type":"uint256"},{"internalType":"uint256","name":"liquidity","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"token","type":"address"},{"internalType":"uint256","name":"amountTokenDesired","type":"uint256"},{"internalType":"uint256","name":"amountTokenMin","type":"uint256"},{"internalType":"uint256","name":"amountETHMin","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"addLiquidityETH","outputs":[{"internalType":"uint256","name":"amountToken","type":"uint256"},{"internalType":"uint256","name":"amountETH","type":"uint256"},{"internalType":"uint256","name":"liquidity","type":"uint256"}],"stateMutability":"payable","type":"function"},{"inputs":[],"name":"factory","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountOut","type":"uint256"},{"internalType":"uint256","name":"reserveIn","type":"uint256"},{"internalType":"uint256","name":"reserveOut","type":"uint256"}],"name":"getAmountIn","outputs":[{"internalType":"uint256","name":"amountIn","type":"uint256"}],"stateMutability":"pure","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountIn","type":"uint256"},{"internalType":"uint256","name":"reserveIn","type":"uint256"},{"internalType":"uint256","name":"reserveOut","type":"uint256"}],"name":"getAmountOut","outputs":[{"internalType":"uint256","name":"amountOut","type":"uint256"}],"stateMutability":"pure","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountOut","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"}],"name":"getAmountsIn","outputs":[{"internalType":"uint256[]","name":"amounts","type":"uint256[]"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountIn","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"}],"name":"getAmountsOut","outputs":[{"internalType":"uint256[]","name":"amounts","type":"uint256[]"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountA","type":"uint256"},{"internalType":"uint256","name":"reserveA","type":"uint256"},{"internalType":"uint256","name":"reserveB","type":"uint256"}],"name":"quote","outputs":[{"internalType":"uint256","name":"amountB","type":"uint256"}],"stateMutability":"pure","type":"function"},{"inputs":[{"internalType":"address","name":"tokenA","type":"address"},{"internalType":"address","name":"tokenB","type":"address"},{"internalType":"uint256","name":"liquidity","type":"uint256"},{"internalType":"uint256","name":"amountAMin","type":"uint256"},{"internalType":"uint256","name":"amountBMin","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"removeLiquidity","outputs":[{"internalType":"uint256","name":"amountA","type":"uint256"},{"internalType":"uint256","name":"amountB","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"token","type":"address"},{"internalType":"uint256","name":"liquidity","type":"uint256"},{"internalType":"uint256","name":"amountTokenMin","type":"uint256"},{"internalType":"uint256","name":"amountETHMin","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"removeLiquidityETH","outputs":[{"internalType":"uint256","name":"amountToken","type":"uint256"},{"internalType":"uint256","name":"amountETH","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"token","type":"address"},{"internalType":"uint256","name":"liquidity","type":"uint256"},{"internalType":"uint256","name":"amountTokenMin","type":"uint256"},{"internalType":"uint256","name":"amountETHMin","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"removeLiquidityETHSupportingFeeOnTransferTokens","outputs":[{"internalType":"uint256","name":"amountETH","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"token","type":"address"},{"internalType":"uint256","name":"liquidity","type":"uint256"},{"internalType":"uint256","name":"amountTokenMin","type":"uint256"},{"internalType":"uint256","name":"amountETHMin","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"},{"internalType":"bool","name":"approveMax","type":"bool"},{"internalType":"uint8","name":"v","type":"uint8"},{"internalType":"bytes32","name":"r","type":"bytes32"},{"internalType":"bytes32","name":"s","type":"bytes32"}],"name":"removeLiquidityETHWithPermit","outputs":[{"internalType":"uint256","name":"amountToken","type":"uint256"},{"internalType":"uint256","name":"amountETH","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"token","type":"address"},{"internalType":"uint256","name":"liquidity","type":"uint256"},{"internalType":"uint256","name":"amountTokenMin","type":"uint256"},{"internalType":"uint256","name":"amountETHMin","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"},{"internalType":"bool","name":"approveMax","type":"bool"},{"internalType":"uint8","name":"v","type":"uint8"},{"internalType":"bytes32","name":"r","type":"bytes32"},{"internalType":"bytes32","name":"s","type":"bytes32"}],"name":"removeLiquidityETHWithPermitSupportingFeeOnTransferTokens","outputs":[{"internalType":"uint256","name":"amountETH","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"tokenA","type":"address"},{"internalType":"address","name":"tokenB","type":"address"},{"internalType":"uint256","name":"liquidity","type":"uint256"},{"internalType":"uint256","name":"amountAMin","type":"uint256"},{"internalType":"uint256","name":"amountBMin","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"},{"internalType":"bool","name":"approveMax","type":"bool"},{"internalType":"uint8","name":"v","type":"uint8"},{"internalType":"bytes32","name":"r","type":"bytes32"},{"internalType":"bytes32","name":"s","type":"bytes32"}],"name":"removeLiquidityWithPermit","outputs":[{"internalType":"uint256","name":"amountA","type":"uint256"},{"internalType":"uint256","name":"amountB","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountOut","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"swapETHForExactTokens","outputs":[{"internalType":"uint256[]","name":"amounts","type":"uint256[]"}],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountOutMin","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"swapExactETHForTokens","outputs":[{"internalType":"uint256[]","name":"amounts","type":"uint256[]"}],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountOutMin","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"swapExactETHForTokensSupportingFeeOnTransferTokens","outputs":[],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountIn","type":"uint256"},{"internalType":"uint256","name":"amountOutMin","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"swapExactTokensForETH","outputs":[{"internalType":"uint256[]","name":"amounts","type":"uint256[]"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountIn","type":"uint256"},{"internalType":"uint256","name":"amountOutMin","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"swapExactTokensForETHSupportingFeeOnTransferTokens","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountIn","type":"uint256"},{"internalType":"uint256","name":"amountOutMin","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"swapExactTokensForTokens","outputs":[{"internalType":"uint256[]","name":"amounts","type":"uint256[]"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountIn","type":"uint256"},{"internalType":"uint256","name":"amountOutMin","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"swapExactTokensForTokensSupportingFeeOnTransferTokens","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountOut","type":"uint256"},{"internalType":"uint256","name":"amountInMax","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"swapTokensForExactETH","outputs":[{"internalType":"uint256[]","name":"amounts","type":"uint256[]"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amountOut","type":"uint256"},{"internalType":"uint256","name":"amountInMax","type":"uint256"},{"internalType":"address[]","name":"path","type":"address[]"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"deadline","type":"uint256"}],"name":"swapTokensForExactTokens","outputs":[{"internalType":"uint256[]","name":"amounts","type":"uint256[]"}],"stateMutability":"nonpayable","type":"function"},{"stateMutability":"payable","type":"receive"}];

let v2FactoryAddress = "0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac";
let v2FactoryABI = [{"inputs":[{"internalType":"address","name":"_feeToSetter","type":"address"}],"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"token0","type":"address"},{"indexed":true,"internalType":"address","name":"token1","type":"address"},{"indexed":false,"internalType":"address","name":"pair","type":"address"},{"indexed":false,"internalType":"uint256","name":"","type":"uint256"}],"name":"PairCreated","type":"event"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"}],"name":"allPairs","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"allPairsLength","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"tokenA","type":"address"},{"internalType":"address","name":"tokenB","type":"address"}],"name":"createPair","outputs":[{"internalType":"address","name":"pair","type":"address"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"feeTo","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"feeToSetter","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"},{"internalType":"address","name":"","type":"address"}],"name":"getPair","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"migrator","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"pairCodeHash","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"pure","type":"function"},{"inputs":[{"internalType":"address","name":"_feeTo","type":"address"}],"name":"setFeeTo","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_feeToSetter","type":"address"}],"name":"setFeeToSetter","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_migrator","type":"address"}],"name":"setMigrator","outputs":[],"stateMutability":"nonpayable","type":"function"}];

let LP_ABI =
    [{"inputs":[],"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"address","name":"spender","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Approval","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount0","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1","type":"uint256"},{"indexed":true,"internalType":"address","name":"to","type":"address"}],"name":"Burn","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount0","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1","type":"uint256"}],"name":"Mint","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"sender","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount0In","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1In","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount0Out","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount1Out","type":"uint256"},{"indexed":true,"internalType":"address","name":"to","type":"address"}],"name":"Swap","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint112","name":"reserve0","type":"uint112"},{"indexed":false,"internalType":"uint112","name":"reserve1","type":"uint112"}],"name":"Sync","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"from","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Transfer","type":"event"},{"inputs":[],"name":"DOMAIN_SEPARATOR","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"MINIMUM_LIQUIDITY","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"PERMIT_TYPEHASH","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"},{"internalType":"address","name":"","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"burn","outputs":[{"internalType":"uint256","name":"amount0","type":"uint256"},{"internalType":"uint256","name":"amount1","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"decimals","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"factory","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"getReserves","outputs":[{"internalType":"uint112","name":"_reserve0","type":"uint112"},{"internalType":"uint112","name":"_reserve1","type":"uint112"},{"internalType":"uint32","name":"_blockTimestampLast","type":"uint32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_token0","type":"address"},{"internalType":"address","name":"_token1","type":"address"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"kLast","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"mint","outputs":[{"internalType":"uint256","name":"liquidity","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"name","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"nonces","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"},{"internalType":"uint256","name":"deadline","type":"uint256"},{"internalType":"uint8","name":"v","type":"uint8"},{"internalType":"bytes32","name":"r","type":"bytes32"},{"internalType":"bytes32","name":"s","type":"bytes32"}],"name":"permit","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"price0CumulativeLast","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"price1CumulativeLast","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"skim","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"amount0Out","type":"uint256"},{"internalType":"uint256","name":"amount1Out","type":"uint256"},{"internalType":"address","name":"to","type":"address"},{"internalType":"bytes","name":"data","type":"bytes"}],"name":"swap","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"symbol","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"sync","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"token0","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"token1","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"totalSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"}],"name":"transfer","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"from","type":"address"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"}],"name":"transferFrom","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"}];

const PUNKS_ABI = [{"constant":true,"inputs":[],"name":"name","outputs":[{"name":"","type":"string"}],"payable":false,"type":"function"},{"constant":true,"inputs":[{"name":"","type":"uint256"}],"name":"punksOfferedForSale","outputs":[{"name":"isForSale","type":"bool"},{"name":"punkIndex","type":"uint256"},{"name":"seller","type":"address"},{"name":"minValue","type":"uint256"},{"name":"onlySellTo","type":"address"}],"payable":false,"type":"function"},{"constant":false,"inputs":[{"name":"punkIndex","type":"uint256"}],"name":"enterBidForPunk","outputs":[],"payable":true,"type":"function"},{"constant":true,"inputs":[],"name":"totalSupply","outputs":[{"name":"","type":"uint256"}],"payable":false,"type":"function"},{"constant":false,"inputs":[{"name":"punkIndex","type":"uint256"},{"name":"minPrice","type":"uint256"}],"name":"acceptBidForPunk","outputs":[],"payable":false,"type":"function"},{"constant":true,"inputs":[],"name":"decimals","outputs":[{"name":"","type":"uint8"}],"payable":false,"type":"function"},{"constant":false,"inputs":[{"name":"addresses","type":"address[]"},{"name":"indices","type":"uint256[]"}],"name":"setInitialOwners","outputs":[],"payable":false,"type":"function"},{"constant":false,"inputs":[],"name":"withdraw","outputs":[],"payable":false,"type":"function"},{"constant":true,"inputs":[],"name":"imageHash","outputs":[{"name":"","type":"string"}],"payable":false,"type":"function"},{"constant":true,"inputs":[],"name":"nextPunkIndexToAssign","outputs":[{"name":"","type":"uint256"}],"payable":false,"type":"function"},{"constant":true,"inputs":[{"name":"","type":"uint256"}],"name":"punkIndexToAddress","outputs":[{"name":"","type":"address"}],"payable":false,"type":"function"},{"constant":true,"inputs":[],"name":"standard","outputs":[{"name":"","type":"string"}],"payable":false,"type":"function"},{"constant":true,"inputs":[{"name":"","type":"uint256"}],"name":"punkBids","outputs":[{"name":"hasBid","type":"bool"},{"name":"punkIndex","type":"uint256"},{"name":"bidder","type":"address"},{"name":"value","type":"uint256"}],"payable":false,"type":"function"},{"constant":true,"inputs":[{"name":"","type":"address"}],"name":"balanceOf","outputs":[{"name":"","type":"uint256"}],"payable":false,"type":"function"},{"constant":false,"inputs":[],"name":"allInitialOwnersAssigned","outputs":[],"payable":false,"type":"function"},{"constant":true,"inputs":[],"name":"allPunksAssigned","outputs":[{"name":"","type":"bool"}],"payable":false,"type":"function"},{"constant":false,"inputs":[{"name":"punkIndex","type":"uint256"}],"name":"buyPunk","outputs":[],"payable":true,"type":"function"},{"constant":false,"inputs":[{"name":"to","type":"address"},{"name":"punkIndex","type":"uint256"}],"name":"transferPunk","outputs":[],"payable":false,"type":"function"},{"constant":true,"inputs":[],"name":"symbol","outputs":[{"name":"","type":"string"}],"payable":false,"type":"function"},{"constant":false,"inputs":[{"name":"punkIndex","type":"uint256"}],"name":"withdrawBidForPunk","outputs":[],"payable":false,"type":"function"},{"constant":false,"inputs":[{"name":"to","type":"address"},{"name":"punkIndex","type":"uint256"}],"name":"setInitialOwner","outputs":[],"payable":false,"type":"function"},{"constant":false,"inputs":[{"name":"punkIndex","type":"uint256"},{"name":"minSalePriceInWei","type":"uint256"},{"name":"toAddress","type":"address"}],"name":"offerPunkForSaleToAddress","outputs":[],"payable":false,"type":"function"},{"constant":true,"inputs":[],"name":"punksRemainingToAssign","outputs":[{"name":"","type":"uint256"}],"payable":false,"type":"function"},{"constant":false,"inputs":[{"name":"punkIndex","type":"uint256"},{"name":"minSalePriceInWei","type":"uint256"}],"name":"offerPunkForSale","outputs":[],"payable":false,"type":"function"},{"constant":false,"inputs":[{"name":"punkIndex","type":"uint256"}],"name":"getPunk","outputs":[],"payable":false,"type":"function"},{"constant":true,"inputs":[{"name":"","type":"address"}],"name":"pendingWithdrawals","outputs":[{"name":"","type":"uint256"}],"payable":false,"type":"function"},{"constant":false,"inputs":[{"name":"punkIndex","type":"uint256"}],"name":"punkNoLongerForSale","outputs":[],"payable":false,"type":"function"},{"inputs":[],"payable":true,"type":"constructor"},{"anonymous":false,"inputs":[{"indexed":true,"name":"to","type":"address"},{"indexed":false,"name":"punkIndex","type":"uint256"}],"name":"Assign","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"from","type":"address"},{"indexed":true,"name":"to","type":"address"},{"indexed":false,"name":"value","type":"uint256"}],"name":"Transfer","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"from","type":"address"},{"indexed":true,"name":"to","type":"address"},{"indexed":false,"name":"punkIndex","type":"uint256"}],"name":"PunkTransfer","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"punkIndex","type":"uint256"},{"indexed":false,"name":"minValue","type":"uint256"},{"indexed":true,"name":"toAddress","type":"address"}],"name":"PunkOffered","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"punkIndex","type":"uint256"},{"indexed":false,"name":"value","type":"uint256"},{"indexed":true,"name":"fromAddress","type":"address"}],"name":"PunkBidEntered","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"punkIndex","type":"uint256"},{"indexed":false,"name":"value","type":"uint256"},{"indexed":true,"name":"fromAddress","type":"address"}],"name":"PunkBidWithdrawn","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"punkIndex","type":"uint256"},{"indexed":false,"name":"value","type":"uint256"},{"indexed":true,"name":"fromAddress","type":"address"},{"indexed":true,"name":"toAddress","type":"address"}],"name":"PunkBought","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"punkIndex","type":"uint256"}],"name":"PunkNoLongerForSale","type":"event"}]