const {expect} = require("chai");
const {ContractFactory, utils, BigNumber} = require('ethers');
const keccak256 = require('keccak256')
const fs = require("fs");
const {MerkleTree} = require("merkletreejs");

const balances = {

};

describe("Rescue", function () {

    let feth = utils.formatEther;
    let peth = utils.parseEther;
    let rescue, RescueMission;
    let tree, leaves, leavesIndex = {};
    let TokenMock, tok;
    let info;
    const unlimited = BigNumber.from("2").pow(BigNumber.from("256")).sub(BigNumber.from("1"));

    before(async function () {
        //process.exit(1); // USE THIS TO STOP THE TEST
        [owner, simp, elizabeth] = await ethers.getSigners();
        balances[owner.address] = 1000000; // add owner to a list of balances
        balances[elizabeth.address] = 300000;
        balances["0xc43473fa66237e9af3b2d886ee1205b81b14b2c8"] = 1;
        RescueMission = await ethers.getContractFactory("RescueMission");
        getLeaves = function() {
            let ret = [];
            for (const address in balances) {
                let n = ethers.utils.solidityPack([ "uint160", "uint256" ], [address, peth(balances[address]+"")])
                console.log("xxxxx n:"+n)
                n = keccak256(n);
                ret.push(n);
                leavesIndex[address] = n;
            }
            return ret;
        }
        leaves = getLeaves();

        tree = new MerkleTree(leaves, keccak256, { sort: true });

        TokenMock = await ethers.getContractFactory("PoolTokenMock");
        tok = await TokenMock.deploy(simp.address);
        await tok.deployed();
        await tok.mint(owner.address, peth("50000000"));

        OldCig = await ethers.getContractFactory("PoolTokenMock");
        oldCig = await OldCig.deploy(simp.address);
        await oldCig.deployed();
        await oldCig.mint(owner.address, peth("5000000"));
        await oldCig.mint(elizabeth.address, peth("1000000"));

    });

    describe("TestProof", function () {

        it("Should test the merkle tree", async function () {

            const root = tree.getHexRoot();
            rescue = await RescueMission.deploy(
                root,
                5,
                tok.address,
                oldCig.address,
                '0xd36ddAe4D9B4b3aAC4FDE830ea0c992752719a21');
            await rescue.deployed();
            let proof = tree.getHexProof(leavesIndex[owner.address]);
            info = await rescue.getInfo(
                owner.address,
                peth(balances[owner.address]+""),
                proof
            );
            console.log("it should be a large value: " + feth(info[3]));
            await rescue.open();


            let ok = await rescue.verify(
                owner.address,
                peth(balances[owner.address]+""),
                root,
                proof);
            console.log("valid:"+ok);
            console.log("root:"+root);
            console.log("proof"+proof);
            expect (ok).to.equal(true);

            expect (await rescue.verify(
                owner.address,
                peth(balances[owner.address]+ 1 +""),
                root,
                proof)).to.equal(false);
            // fund the contract
            expect(await tok.transfer(rescue.address, peth("5000000"))).to.emit(tok, "Transfer");


        });

        it("Should rescue", async function () {
            let proof = tree.getHexProof(leavesIndex[owner.address]);
            info = await rescue.getInfo(
                owner.address,
                peth(balances[owner.address]+""),
                proof
            );

            await oldCig.approve(rescue.address, unlimited);

            // can we claim 100 k?
            expect(await rescue.rescue(
                peth("100000"),
                owner.address,
                peth(balances[owner.address]+""),
                proof
                )).to.emit(rescue, "Rescue").withArgs(owner.address, owner.address, peth("100000"));

            await expect(rescue.rescue(
                peth("100000"),
                owner.address,
                peth(balances[owner.address]+""),
                proof
            )).to.be.revertedWith("max amount already claimed");

            let info2 = await rescue.getInfo(
                owner.address,
                peth(balances[owner.address]+""),
                proof
            );
            // verify the state
            expect(info2[0]).to.equal("1");                         // always 1 if proof is valid
            expect(info[1].sub(peth("100000"))).to.equal(info2[1]); // contract's CIG went down by 100 k
            expect(info2[2]).to.equal(peth("100000"));              // user claimed 100k
            expect(info2[3]).to.equal(peth("100000"));              // max should be 100 k
            expect(parseInt(info2[4].toString())).to.greaterThan(0);// should not change
            expect(parseInt(info2[5].toString())).to.greaterThan(0);// might change but we cannot be sure
            expect(info[6].add(peth("100000"))).to.equal(info2[6]); // new CIG went up by 100k
            expect(info[7].sub(peth("100000"))).to.equal(info2[7]); // user's old cig should decrease by 100 ok
            expect(info2[8]).to.equal(unlimited.toString());        // unlimited approval

        });

        it("Should rescue with increased limit", async function () {

            let proof = tree.getHexProof(leavesIndex[owner.address]);

            function sleep(ms) {
                return new Promise((resolve) => {
                    setTimeout(resolve, ms);
                });
            }

            info = await rescue.getInfo(
                owner.address,
                peth(balances[owner.address]+""),
                proof
            );
            //console.log(info);

            console.log("waiting 5 sec");
            await sleep(5000); // wait 4 sec

            await expect(rescue.kill()).to.be.revertedWith("cannot kill yet");

            let info2 = await rescue.getInfo(
                owner.address,
                peth(balances[owner.address]+""),
                proof
            );
            //console.log(info2);
            expect(parseInt(info2[3].toString())).to.greaterThan(100000); // max should increase now
            // claim another 100k
            expect(await rescue.rescue(
                peth("200000"),
                owner.address,
                peth(balances[owner.address]+""),
                proof
            )).to.emit(rescue, "Rescue").withArgs(owner.address, owner.address, peth("200000"));

            console.log("here: " + feth(info2[3]));

            expect(parseInt(info2[3].toString())).to.greaterThan(300000); // max should increase now

            await oldCig.connect(elizabeth).approve(rescue.address, unlimited);
            proof = tree.getHexProof(leavesIndex[elizabeth.address]);
            expect(await rescue.connect(elizabeth).rescue(
                peth("300000"),
                elizabeth.address,
                peth(balances[elizabeth.address]+""),
                proof
            )).to.emit(rescue, "Rescue").withArgs(elizabeth.address, elizabeth.address, peth("300000"));
        });
    });
});