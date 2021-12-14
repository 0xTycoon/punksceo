const {expect} = require("chai");
const {ContractFactory, utils, BigNumber} = require('ethers');

describe("Cig", function () {

    let CigToken;
    let cig;
    let PunkMock;
    let pm;
    let owner, simp, elizabeth;
    let PoolMock;
    let pt;
    let NFTMock;
    let nft;
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
    // MasterChefV2 contract
    let MSV2 = '0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d'; // 0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d is the production
    const tax_denominator = BigNumber.from("1000"); // %0.1
    const hre = require("hardhat");

    let feth = utils.formatEther;
    let peth = utils.parseEther;

    let ASSET_URL = "ipfs://2727838744/something/238374/";

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

        CigToken = await ethers.getContractFactory("Cig");
        cig = await CigToken.deploy(
            100,
            utils.parseEther(BLOCK_REWARD),
            pm.address,
            CEO_EPOCH_BLOCKS,
            CEO_AUCTION_BLOCKS,
            utils.parseEther(CEO_BUY_PRICE),
            MSV2,
            graff32,
            nft.address,
            v2.address
        );
        await cig.deployed();

        // tell the NFT contract about the cig token
        await nft.setCigToken(cig.address);
        //await nft.setBaseURI(ASSET_URL); // onlyCEO

        // test burning of keys
        await nft.renounceOwnership();

        await expect(nft.setBaseURI(ASSET_URL)).to.be.revertedWith('must be called by CEO');

    });

    describe("Deployment", function () {

        it("Should return the pool once it is changed", async function () {
            expect(await cig.name()).to.equal("Cigarette Token");
            await cig.setPool(pt.address);
            expect(await cig.lpToken()).to.equal(pt.address);
        });

        it("Should use a punk to claim some coins", async function () {
            // test if we claim
            expect(await cig.claim(4513))
                .to.emit(cig, 'Claim').withArgs(owner.address, 4513, utils.parseEther(CLAIM_AMOUNT))
                .to.emit(cig, 'Transfer').withArgs(pm.address, owner.address, utils.parseEther(CLAIM_AMOUNT));
            expect(await cig.balanceOf(owner.address)).to.equal(utils.parseEther(CLAIM_AMOUNT));
            // cannot claim a punk twice
            await expect(cig.claim(4513))
                .to.be.revertedWith('punk already claimed');
            // out of range
            await expect(cig.claim(10000))
                .to.be.revertedWith('invalid punk');
            //
            await expect(cig.claim(4))
                .to.be.revertedWith('punk 404');

        });

        it("Should buy a ceo and pay tax", async function () {
            let [stats, The_CEO, graff] = await cig.getStats(owner.address);
            let totalSupply = stats[7];
            // approve the cig contract (not necessary, just testing)
            expect(await cig.approve(cig.address, peth(CEO_BUY_PRICE)))
                .to.emit(cig, 'Approval').withArgs(owner.address, cig.address, peth(CEO_BUY_PRICE));
            expect(await cig.allowance(owner.address, cig.address))
                .to.equal(peth(CEO_BUY_PRICE));
            // buy the CEO title (reverts due to insufficient tax)
            let tax = peth(CEO_BUY_PRICE).div(tax_denominator)
            let insufficient = tax.sub("1");
            await expect(cig.buyCEO(peth(CEO_BUY_PRICE), insufficient, 4513, graff32))
                .to.be.revertedWith("insufficient tax");

            // buy the CEO title (reverts due to price being under)
            await expect(cig.buyCEO(peth('0.0000009'), tax, 4513, graff32))
                .to.be.revertedWith("price 2 smol");
            // buy the CEO title
            console.log("total supply before:" + feth(totalSupply));

            expect(await cig.buyCEO(peth(CEO_BUY_PRICE), peth(CEO_TAX_DEPOSIT), 4513, graff32))
                .to.emit(cig, "NewCEO").withArgs(owner.address, 4513, peth(CEO_BUY_PRICE), BigNumber.from(graff32))
                .to.emit(cig, "TaxDeposit").withArgs(owner.address, peth(CEO_TAX_DEPOSIT))
                .to.emit(cig, "Transfer").withArgs(cig.address, "0x0000000000000000000000000000000000000000", peth(CEO_BUY_PRICE))
                .to.emit(cig, "RevenueBurned").withArgs(owner.address, peth(CEO_BUY_PRICE))
            ;
            expect(await nft.ownerOf(0)).to.be.equal(owner.address); // check NFT transferred

            expect(await nft.tokenURI(0)).to.equal(ASSET_URL + "0.json");

            let expectedSupply = totalSupply.sub(peth(CEO_BUY_PRICE));
            // check the total supply, an amount of CEO_BUY_PRICE should be burned
            expect(await cig.totalSupply()).to.be.equal(expectedSupply);
            // check to make sure the CEO has been set
            expect(await cig.The_CEO()).to.be.equal(owner.address);
            [stats, The_CEO, graff] = await cig.getStats(owner.address);
            //console.log("%s stats %s", stats);
            expect(stats[0]).to.be.equal(1); // CEO_state
            expect(stats[1]).to.be.equal(peth(CEO_TAX_DEPOSIT)); // CEO_tax_balance
            expect(stats[2]).to.be.equal(17); // taxBurnBlock (last tax burn)
            expect(stats[3]).to.be.equal(0); // rewards_block_number
            expect(stats[4]).to.be.equal(peth(CEO_BUY_PRICE)); // CEO_price
            expect(stats[5]).to.be.equal(4513); // CEO_punk_index
            expect(stats[6]).to.be.equal(peth(BLOCK_REWARD)); // cigPerBlock
            expect(stats[7]).to.be.equal(peth(MINT_SUPPLY).sub(peth(CEO_BUY_PRICE))); // MINT_SUPPLY minus what was burned
            expect(stats[8]).to.be.equal(0); // lpToken.balanceOf
            expect(graff).to.be.equal(BigNumber.from(graff32));
            // 9 - block.number
            // 10 - tpb (tax per block)
            // 11 - debt
            // 13 - pending cig reward
            // 14 - user.deposit
            // 15 - user.rewardDebt

        });

        it("Should burn tax then default on debt", async function () {
            await cig.update(); // advance a block (to incur a tax liability)
            let [stats, ceo, graff] = await cig.getStats(owner.address);
            let tpb = stats[10]; // tax per block
            let bal = stats[1]; // tax deposit balance
            let debt = stats[11]; // 5
            // only 1 block advanced
            console.log("bal:"
                + feth(bal)
                + " debt:"
                + feth(debt)
                + " tpb:"
                + feth(tpb)
                + " blocks:"
                + stats[9].sub(stats[2])); // CEO tax balance
            expect(tpb.mul(stats[9].sub(stats[2]))).to.be.equal(debt);


            let toBurn = tpb.mul(stats[9].sub(stats[2])); // debt
            expect(await cig.burnTax())
                .to.emit(cig, 'TaxBurned').withArgs(owner.address, toBurn.add(tpb)); // add tpb since one more block passed

            // every time we call burnTax it subtracts tpb from bal
            // this just makes sure that the accounting is correct
            [stats] = await cig.getStats(owner.address);

            console.log("bal:"
                + feth(stats[1])
                + " debt:"
                + feth(stats[11])
                + " tpb:"
                + feth(stats[10])
                + " blocks:"
                + stats[9].sub(stats[2]));

            let advanceBlocks = stats[1].div(stats[10]);
            console.log("advanceBlocks: " + advanceBlocks);
            // advance blocks (we need to wait before we can set the price again)
            //return;
            for (let i = 0; i < (advanceBlocks - CEO_EPOCH_BLOCKS); i++) { // just 1 before default
                console.log("i:" + i + " adv" + advanceBlocks);
                // with each block, tax is deducted from the deposit
                await expect(cig.setPrice(utils.parseEther(CEO_BUY_PRICE)))
                    .to.emit(cig, 'CEOPriceChange').withArgs(utils.parseEther(CEO_BUY_PRICE))
                    .to.emit(cig, "TaxBurned").withArgs(owner.address, tpb)
                ;
            }
            for (let i = 0; i < CEO_EPOCH_BLOCKS; i++) {
                //console.log("i:" + i);
                await expect(cig.burnTax()).to.emit(cig, "TaxBurned");
            }
            // expecting a default on debt, expecting a reward of 'tpb' to the caller
            await expect(cig.burnTax())
                .to.emit(cig, 'CEODefaulted').withArgs(owner.address, tpb)
                .to.emit(cig, 'Transfer').withArgs("0x0000000000000000000000000000000000000000", owner.address, tpb)
            ;
        });

                it("apply a discount for each epoch", async function () {
                    let [stats] = await cig.getStats(owner.address);
                    let initialPrice = stats[4];
                    console.log("price is" + stats[4]);
                    expect(stats[0]).to.be.equal(2); // state 2 means the CEO defaulted
                    expect(stats[4]).to.be.equal(peth(CEO_BUY_PRICE)); // no discount yet
                    for (let i = 0; i < CEO_AUCTION_BLOCKS; i++) {
                        await cig.update();
                    }
                    [stats] = await cig.getStats(owner.address);
                    expect(stats[4]).to.be.equal(initialPrice.sub(initialPrice.div(10))); // a 10% discount applied
                    for (let i = 0; i < CEO_AUCTION_BLOCKS * 9; i++) {
                        await cig.update();
                        //[stats] = await cig.getStats(owner.address);
                        //console.log
                    }
                    [stats] = await cig.getStats(owner.address);
                    expect(stats[4]).to.be.equal(peth('0.000001')); // further 10% discount applied
                    console.log("price is" + stats[4]);
                });

                       // approve the cig contract to spend our pool token
                       it("Should use some cig to liquidity mine", async function () {
                           console.log("balance BEFORE is: " + utils.formatEther(await cig.balanceOf(owner.address)));

                           // approve and deposit LP tokens
                           await expect(pt.approve(cig.address, utils.parseEther('5'))).to.emit(pt, 'Approval');
                           await expect(cig.deposit(utils.parseEther('5'))).to.emit(cig, 'Deposit');
                           // liquidity mining started!
                           await cig.update(); // mine for 1 block
                           // check how many we mined
                           let pcig = await cig.pendingCig(owner.address);
                           console.log("pending cig:" + utils.formatEther(pcig));
                           expect(pcig).to.be.equal(utils.parseEther(BLOCK_REWARD));
                           // claim the cig
                           await expect(cig.deposit('0'))
                               .to.emit(cig, 'Transfer')
                               .withArgs(
                                   cig.address, owner.address,
                                   utils.parseEther(BLOCK_REWARD).mul(2) // multiply by 2 since 2 blocks passed
                               );
                           pcig = await cig.pendingCig(owner.address);

                           console.log("balance is: " + utils.formatEther(await cig.balanceOf(owner.address)));

                           // mine from another account
                           await expect(pt.connect(simp).mint(simp.address, utils.parseEther('15')))
                               .to.emit(pt, "Transfer"); // mint some test tokens
                           await expect(pt.connect(simp).approve(cig.address, utils.parseEther('15'))).to.emit(pt, 'Approval'); // approve cig to spend 15
                           await cig.deposit('0'); // claim for owner account
                           // owner has 5 cig
                           // after simp deposits, owner will own 1/4 of the pool, so 1.25 per block
                           // simp will be getting 3.75 per block
                           await expect(cig.connect(simp).deposit(utils.parseEther('15'))).to.emit(cig, 'Deposit');
                           // owner should have 5
                           await cig.update(); // mine


                           // check the stats for both accounts
                           pcig = await cig.pendingCig(owner.address);
                           console.log("pending cig owner:" + utils.formatEther(pcig));
                           pcig = await cig.pendingCig(simp.address);
                           console.log("pending cig simp:" + utils.formatEther(pcig));
                       });

                       it("should withdraw pool tokens correctly", async function () {
                           let [stats] = await cig.getStats(owner.address);
                           let pending = await cig.pendingCig(owner.address);
                           let perBlock = stats[6].div(stats[8].div(stats[13])); // work out the individual reward per block
                           console.log("perBlock isssss: " + perBlock + " " + feth(stats[8]) + " " + feth(stats[13]) + " " + feth(stats[6]));
                           console.log("LP deposit " + stats[13], "pending " + pending);
                           expect(stats[13]).to.equal(peth("5"));
                           await expect(cig.withdraw(stats[13]))
                               .to.emit(cig, "Withdraw").withArgs(owner.address, stats[13]) // LP token
                               // add an additional block reward
                               .to.emit(cig, "Transfer").withArgs(cig.address, owner.address, pending.add(perBlock)) // block reward
                           ;
                           let info = await cig.userInfo(cig.address);
                           expect(info.deposit).to.be.equal(0);
                           // pending cig should be 0 after the withdrawal
                           expect(await cig.pendingCig(owner.address)).to.be.equal("0");
                           // we should have CIGs in our wallet
                           expect(await cig.balanceOf(owner.address)).to.be.equal(pending.add(perBlock).add(stats[15]));
                           // we should have the LP tokens in our wallet
                           expect(await pt.balanceOf(owner.address)).to.be.equal(peth("5"));

                           // emergency withdraw time
                           [stats] = await cig.getStats(simp.address);
                           await expect(cig.connect(simp).emergencyWithdraw())
                               .to.emit(cig, 'EmergencyWithdraw').withArgs(simp.address, stats[13]);
                           // we should have the LP tokens in our wallet
                           expect(await pt.balanceOf(simp.address)).to.be.equal(peth("15"));
                           // there should be no more LP tokens deposited
                           expect(await pt.balanceOf(cig.address)).to.be.equal("0");
                       });

                               it("Should test CEO takeover", async function () {
                                   let [stats] = await cig.getStats(owner.address);
                                   console.log("LP deposit " + stats[13]);
                                   await expect(cig.transfer(elizabeth.address, stats[15]))
                                       .to.emit(cig, "Transfer").withArgs(owner.address, elizabeth.address, stats[15]);
                                   // elizabeth will become the CEO
                                   await expect(cig.connect(elizabeth)
                                       .buyCEO(peth("1"), stats[15].sub(peth("1")), 6942, graff32))
                                       .to.emit(cig, "NewCEO").withArgs(elizabeth.address, 6942, peth("1"), BigNumber.from(graff32))
                                       .to.emit(cig, "TaxDeposit")
                                   ;

                                   // simp starts to liquidity mine!

                                   await expect(cig.connect(simp).deposit(await pt.balanceOf(simp.address)))
                                       .to.emit(cig, "Deposit");
                                   await cig.update(); // mine
                                   await cig.update(); // mine
                                   // simp does a harvest
                                   await expect(cig.connect(simp).deposit(0))
                                       .to.emit(cig, "Transfer");
                                   console.log("simp farmed:" + feth(await cig.pendingCig(simp.address)) + "and has:" + feth(await cig.balanceOf(simp.address)));
                                   // and now simp does a takeover!
                                   [stats] = await cig.getStats(elizabeth.address);
                                   let elizabethExpectedRefund = stats[1].sub(stats[11]).sub(stats[10]);  // tax_deposit - accrued_debt - 1_block_debt

                                   [stats] = await cig.getStats(simp.address);
                                   console.log("it should burn " + feth("5000000000000000") + " but we have " + feth(stats[10]))
                                   await expect(cig.connect(simp)
                                       .buyCEO(peth("1"), stats[15].sub(peth("1")), 6942, graff32))
                                       .to.emit(cig, "NewCEO").withArgs(simp.address, 6942, peth("1"), BigNumber.from(graff32))
                                       // return previous ceo's tac deposit
                                       .to.emit(cig, "Transfer").withArgs(cig.address, elizabeth.address, elizabethExpectedRefund)
                                       // store new CEO tax deposit
                                       .to.emit(cig, "Transfer").withArgs(simp.address, cig.address, stats[15].sub(peth("1")))
                                       // take payment for the title
                                       .to.emit(cig, "Transfer").withArgs(simp.address, cig.address, peth("1"))
                                       // burn the paymeny for the title
                                       .to.emit(cig, "Transfer").withArgs(cig.address, "0x0000000000000000000000000000000000000000", peth("1"))

                                       // elizabeth's tax should be burned
                                       .to.emit(cig, "Transfer").withArgs(cig.address, "0x0000000000000000000000000000000000000000", stats[10].add(stats[11]))
                                   ;
                               });

                               // ratios:
                               // 1000 wei gives 0.1%
                               // 100  wei gives 1%
                               // 40   wei gives 2.5%
                               // 20   wei gives 5%
                               // 10   wei gives 10%
                               // 5    wei gives 20%
                               // 4    wei gives 25%
                               // and so on...
                               it("Should increase the block rewards", async function () {
                                   let [stats] = await cig.getStats(simp.address);
                                   let cpb = stats[6]; //peth("100");
                                   let expectedIncrease = cpb.div(BigNumber.from(5));
                                   let expectedNewReward = cpb.add(expectedIncrease);
                                   console.log("cpb:" + feth(cpb) + " expectedIncrease: " + feth(expectedIncrease) + " expectedNewReward: " + feth(expectedNewReward) + " percent:" + feth(expectedIncrease.div(cpb)));

                                   await expect(cig.connect(simp).rewardUp())
                                       .to.emit(cig, "RewardUp").withArgs(expectedNewReward, expectedIncrease);

                                   await expect(cig.connect(simp).rewardUp())
                                       .to.be.revertedWith("wait more blocks");

                                   await expect(cig.connect(elizabeth).rewardUp())
                                       .to.be.revertedWith("only CEO can call this");

                                   // this routine will keep increasing the CIG rewards until the cap is reached
                                   for (let i = 0; i < 650; i++) {
                                       let diff = parseInt(stats[9].sub(stats[3].toString()));

                                       if (diff === CEO_EPOCH_BLOCKS * 2) {
                                           await expect(cig.connect(simp).rewardUp()).to.emit(cig, "RewardUp");
                                           //await expect(cig.connect(simp).rewardUp()).to.be.revertedWith("wait more blocks");
                                           console.log("reward up");
                                           [stats] = await cig.getStats(simp.address);
                                           console.log("reward:" + feth(stats[6]) + " dif:" + parseInt(stats[9].sub(stats[3].toString())));
                                       } else {
                                           await expect(cig.connect(simp).rewardUp())
                                               .to.be.revertedWith("wait more blocks");
                                       }
                                       [stats] = await cig.getStats(simp.address);
                                       // must never go over the cap
                                       expect(parseFloat(feth(stats[6]))).to.be.lessThanOrEqual(1000);
                                   }
                                   // See if we can call deposit to harvest rewards
                                   await expect(await cig.connect(simp).deposit(peth("0"))).to.emit(cig, "Transfer");
                               });

                               it("Should decrease the block rewards", async function () {
                                   await cig.setReward(peth("0.1"));

                                   let [stats] = await cig.getStats(simp.address);
                                   console.log("moo:" + (stats[9].sub(stats[3])));
                                   for (let i = 0; i < CEO_EPOCH_BLOCKS * 2; i++) {
                                       await cig.update();
                                   }

                                   //return;
                                   let cpb = stats[6]; //peth("100");
                                   let expectedIncrease = cpb.div(BigNumber.from(5));
                                   let expectedNewReward = cpb.sub(expectedIncrease);
                                   console.log("cpb:" + feth(cpb) + " expectedIncrease: " + feth(expectedIncrease) + " expectedNewReward: " + feth(expectedNewReward) + " percent:" + feth(expectedIncrease.div(cpb)));

                                   await expect(cig.connect(simp).rewardDown())
                                       .to.emit(cig, "RewardDown").withArgs(expectedNewReward, expectedIncrease);

                                   await expect(cig.connect(simp).rewardDown())
                                       .to.be.revertedWith("wait more blocks");

                                   await expect(cig.connect(elizabeth).rewardDown())
                                       .to.be.revertedWith("only CEO can call this");


                                   // this routine will keep increasing the CIG rewards until the cap is reached
                                   for (let i = 0; i < 650; i++) {
                                       let diff = parseInt(stats[9].sub(stats[3].toString()));

                                       if (diff === CEO_EPOCH_BLOCKS * 2) {
                                           await expect(cig.connect(simp).rewardDown()).to.emit(cig, "RewardDown");
                                           //await expect(cig.connect(simp).rewardUp()).to.be.revertedWith("wait more blocks");
                                           console.log("reward down");
                                           [stats] = await cig.getStats(simp.address);
                                           console.log("reward:" + feth(stats[6]) + " dif:" + parseInt(stats[9].sub(stats[3].toString())));
                                       } else {
                                           await expect(cig.connect(simp).rewardDown())
                                               .to.be.revertedWith("wait more blocks");
                                       }
                                       [stats] = await cig.getStats(simp.address);
                                       // must never go over the cap
                                       expect(parseFloat(feth(stats[6]))).to.be.greaterThanOrEqual(0.0001);
                                   }
                                   // See if we can call deposit to harvest rewards
                                   await expect(await cig.connect(simp).deposit(peth("0"))).to.emit(cig, "Transfer");
                               });
     //   /*
                                       it("Should burn admin keys", async function () {
                                           // burn admin key
                                           await cig.renounceOwnership();

                                           await expect(cig.setReward(peth("1"))).to.be.revertedWith("Only admin can call this");

                                           await expect(cig.setStartingBlock(peth("1"))).to.be.revertedWith("Only admin can call this");

                                           await expect(cig.setPool(pt.address)).to.be.revertedWith("Only admin can call this");

                                       });
                       //        */
    });


});

// matches https://ethereum-waffle.readthedocs.io/en/latest/matchers.html
