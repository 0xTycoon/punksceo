const hre = require("hardhat");
let fs = require('fs');
const {utils} = require("ethers");







var CIG_ABI = [{"inputs":[{"internalType":"uint256","name":"_cigPerBlock","type":"uint256"},{"internalType":"address","name":"_punks","type":"address"},{"internalType":"uint256","name":"_CEO_epoch_blocks","type":"uint256"},{"internalType":"uint256","name":"_CEO_auction_blocks","type":"uint256"},{"internalType":"uint256","name":"_CEO_price","type":"uint256"},{"internalType":"bytes32","name":"_graffiti","type":"bytes32"},{"internalType":"address","name":"_NFT","type":"address"},{"internalType":"address","name":"_V2ROUTER","type":"address"},{"internalType":"address","name":"_OC","type":"address"},{"internalType":"uint256","name":"_migration_epochs","type":"uint256"},{"internalType":"address","name":"_MASTERCHEF_V2","type":"address"}],"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"address","name":"spender","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Approval","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"called_by","type":"address"},{"indexed":false,"internalType":"uint256","name":"reward","type":"uint256"}],"name":"CEODefaulted","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"price","type":"uint256"}],"name":"CEOPriceChange","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"ChefDeposit","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"ChefWithdraw","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"uint256","name":"punkIndex","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Claim","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"Deposit","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"EmergencyWithdraw","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"Harvest","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":true,"internalType":"uint256","name":"punk_id","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"new_price","type":"uint256"},{"indexed":false,"internalType":"bytes32","name":"graffiti","type":"bytes32"}],"name":"NewCEO","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"RevenueBurned","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"reward","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"downAmount","type":"uint256"}],"name":"RewardDown","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"reward","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"upAmount","type":"uint256"}],"name":"RewardUp","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"TaxBurned","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"TaxDeposit","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"from","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Transfer","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"Withdraw","type":"event"},{"inputs":[],"name":"CEO_price","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"CEO_punk_index","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"CEO_state","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"CEO_tax_balance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"The_CEO","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"accCigPerShare","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"admin","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"},{"internalType":"address","name":"","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_spender","type":"address"},{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"burnTax","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_max_spend","type":"uint256"},{"internalType":"uint256","name":"_new_price","type":"uint256"},{"internalType":"uint256","name":"_tax_amount","type":"uint256"},{"internalType":"uint256","name":"_punk_index","type":"uint256"},{"internalType":"bytes32","name":"_graffiti","type":"bytes32"}],"name":"buyCEO","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"cigPerBlock","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_punkIndex","type":"uint256"}],"name":"claim","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"}],"name":"claims","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"decimals","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"deposit","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"depositTax","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"emergencyWithdraw","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"farmers","outputs":[{"internalType":"uint256","name":"deposit","type":"uint256"},{"internalType":"uint256","name":"rewardDebt","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"farmersMasterchef","outputs":[{"internalType":"uint256","name":"deposit","type":"uint256"},{"internalType":"uint256","name":"rewardDebt","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_user","type":"address"}],"name":"getStats","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"},{"internalType":"address","name":"","type":"address"},{"internalType":"bytes32","name":"","type":"bytes32"},{"internalType":"uint112[]","name":"","type":"uint112[]"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"graffiti","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"harvest","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_punkIndex","type":"uint256"}],"name":"isClaimed","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"lastRewardBlock","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"lpToken","outputs":[{"internalType":"contract ILiquidityPoolERC20","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"masterchefDeposits","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"migrationComplete","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"name","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"address","name":"_user","type":"address"},{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_sushiAmount","type":"uint256"},{"internalType":"uint256","name":"_newLpAmount","type":"uint256"}],"name":"onSushiReward","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_user","type":"address"}],"name":"pendingCig","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"punks","outputs":[{"internalType":"contract ICryptoPunk","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"renounceOwnership","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"rewardDown","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"rewardUp","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"rewardsChangedBlock","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"contract ILiquidityPoolERC20","name":"_addr","type":"address"}],"name":"setPool","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_price","type":"uint256"}],"name":"setPrice","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"setReward","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_startBlock","type":"uint256"}],"name":"setStartingBlock","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"stakedlpSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"symbol","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"taxBurnBlock","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"totalSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"transfer","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_from","type":"address"},{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"transferFrom","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"unwrap","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"update","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"address","name":"_user","type":"address"}],"name":"userInfo","outputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"uint256","name":"depositAmount","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"wBal","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"withdraw","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_value","type":"uint256"}],"name":"wrap","outputs":[],"stateMutability":"nonpayable","type":"function"}];

async function writeOutTotal(filename, content) {
    try {
        return fs.writeFileSync(filename, content)
        //file written successfully
    } catch (err) {
        console.error(err)
    }
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
async function main() {
    let feth = utils.formatEther;
    let peth = utils.parseEther;

    const CIG_ADDRESS = "0xCB56b52316041A62B6b5D0583DcE4A8AE7a3C629";
    let CIG;

    CIG = await hre.ethers.getContractAt(CIG_ABI, CIG_ADDRESS);

    let total = await CIG.totalSupply();
    writeOutTotal('./report/totalcoins', feth(total));

    let [stats, The_CEO, graffiti, reserves] = await CIG.getStats("0xCB56b52316041A62B6b5D0583DcE4A8AE7a3C629");

    let circulating = total.sub(stats[21]);


    writeOutTotal('./report/circulating', feth(circulating));

    let claimed = peth("1000000000").sub(stats[21]);

    console.log(feth(claimed));

    writeOutTotal('./report/claimed', feth(circulating));

    /*
     uint[] memory ret = new uint[](27);
        uint112[] memory reserves = new uint112[](2);
        uint256 tpb = (CEO_price / 1000) / (CEO_epoch_blocks); // 0.1% per epoch
        uint256 debt = (block.number - taxBurnBlock) * tpb;
        uint256 price = CEO_price;
        UserInfo memory info = farmers[_user];
        if (CEO_state == 2) {
            price = _calcDiscount();
        }
        ret[0] = CEO_state;
        ret[1] = CEO_tax_balance;
        ret[2] = taxBurnBlock;                     // the block number last tax burn
        ret[3] = rewardsChangedBlock;              // the block of the last staking rewards change
        ret[4] = price;                            // price of the CEO title
        ret[5] = CEO_punk_index;                   // punk ID of CEO
        ret[6] = cigPerBlock;                      // staking reward per block
        ret[7] = totalSupply;                      // total supply of CIG
        if (address(lpToken) != address(0)) {
            ret[8] = lpToken.balanceOf(address(this)); // Total LP staking
            ret[16] = lpToken.balanceOf(_user);        // not staked by user
            ret[17] = pendingCig(_user);               // pending harvest
            (reserves[0], reserves[1], ) = lpToken.getReserves();        // uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast
            ret[18] = V2ROUTER.getAmountOut(1 ether, uint(reserves[0]), uint(reserves[1])); // CIG price in ETH
            if (isContract(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2))) { // are we on mainnet?
                ILiquidityPoolERC20 ethusd = ILiquidityPoolERC20(address(0xC3D03e4F041Fd4cD388c549Ee2A29a9E5075882f));  // sushi DAI-WETH pool
                uint112 r0;
                uint112 r1;
                (r0, r1, ) = ethusd.getReserves();
                // get the price of ETH in USD
                ret[19] =  V2ROUTER.getAmountOut(1 ether, uint(r0), uint(r1));      // ETH price in USD
            }
            ret[22] = lpToken.totalSupply();       // total supply
        }
        ret[9] = block.number;                       // current block number
        ret[10] = tpb;                               // "tax per block" (tpb)
        ret[11] = debt;                              // tax debt accrued
        ret[12] = lastRewardBlock;                   // the block of the last staking rewards payout update
        ret[13] = info.deposit;                      // amount of LP tokens staked by user
        ret[14] = info.rewardDebt;                   // amount of rewards paid out
        ret[15] = balanceOf[_user];                  // amount of CIG held by user
        ret[20] = accCigPerShare;                    // Accumulated cigarettes per share
        ret[21] = balanceOf[address(punks)];         // amount of CIG to be claimed
        ret[23] = wBal[_user];                       // wrapped cig balance
        ret[24] = OC.balanceOf(_user);               // balance of old cig in old isContract
        ret[25] = OC.allowance(_user, address(this));// is old contract approved
        (ret[26], ) = OC.userInfo(_user);            // old contract stake bal
        return (ret, The_CEO, graffiti, reserves);
     */


};