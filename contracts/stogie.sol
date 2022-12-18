// SPDX-License-Identifier: MIT
// 🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔
// Author: tycoon.eth
// Project: Hamburger Hut / Cigarettes
// About: Harberger tax marketplace & protocol for NFTs
// 🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔
pragma solidity ^0.8.17;

import "hardhat/console.sol";

/**
* This contract controls and holds value generated from harberger.sol

1. Any CIG sent to this contract is used to buy the STOG token
2. Any non-CIG token sent to this contract is sold for ETH, then sold for CIG
3. Introducing "The STOG". The STOG token is a wrapper for the CIG/ETH Liquidity Provider (LP) token.
    It represents a share of the CIG/ETH liquidity in SushiSwap.
 4. The CIG/STOG pair is on SushiSwap, from which this contract will purchase STOG by using CIG
 5. Purchased STOG will be unwrapped and deposited into the Cigarettes contract and used to produce CIG.
    CIG earnings will be used to buy more STOG.
    The stake will be locked inside Cigarettes forever, becoming Protocol Owned Liquidity.
 6. Anybody can create new STOG by adding tokens by depositing ETH and CIG.
 7. Anybody can take advantage of any arb opportunity with their STOG by trading with the CIG/STOG pool.

 Arbitrage example: The price for 1 CIG/ETH Liquidity Provider (LP) token should always be equal to the price of
 1 STOG. However, if the price of CIG moves up and ETH stays the same or also goes up, then the price of 1 LP token will
 also go up. So, someone can buy the underpriced STOG with CIG, then unwrap it to get the underlying LP tokens.

 Finally, they can destroy the LP tokens (by removing the liquidity), getting back ETH and CIG. Or, they can deposit
 the LP tokens to roll more CIG.

 In short, if the price of CIG is going up, and ETH stays the same or also goes up, then check the price of STOG as it
 may be at a discount.

 In reverse, if the price of the LP token goes down, there may be an opportunity to mint some LP tokens that trade
 at a discount, wrap them into STOG, then sell them to the CIG/STOG pool for a *profit.

 (* Results may vary depending on how deep the liquidity is and how far the difference between the price is)

*/


contract Stogie {

    ICigToken private immutable cig;           // 0xCB56b52316041A62B6b5D0583DcE4A8AE7a3C629
    ILiquidityPool private immutable cigEthSLP;// 0x22b15c7ee1186a7c7cffb2d942e20fc228f6e4ed (SLP, it's also an ERC20)
    address private immutable weth;            // 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    IV2Router private immutable sushiRouter;   // 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F
    address private immutable sushiFactory;    // 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac
    address public stogiePool;                 // will be created with init()
    uint8 internal locked = 1;                 // reentrancy guard. 2 = entered, 1 not
    bytes32 public DOMAIN_SEPARATOR;           // EIP-2612 permit functionality
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public nonces;    // EIP-2612 permit functionality
    address private immutable idCards;         // id cards erc721
    constructor(
        address _cig,
        address _CigEthSLP,
        address _sushiRouter,
        address _sushiFactory,
        address _weth,
        address _idCards
    ) {
        cig = ICigToken(_cig);
        cigEthSLP = ILiquidityPool(_CigEthSLP);
        sushiRouter = IV2Router(_sushiRouter);
        sushiFactory = _sushiFactory;
        weth = _weth;
        idCards = _idCards;
        uint chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        ); // EIP-2612
    }

    // todo remove doNothing()
    uint256 public c  = 0;
    function doNothing() external returns (uint) {
        c++;
        return block.number;
    }

    modifier notReentrant() { // notReentrant is a reentrancy guard
        require(locked == 1, "already entered");
        locked = 2; // enter
        _;
        locked = 1; // exit
    }

    /**
    * @dev permit is eip-2612 compliant
    */
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'Stogie: EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'Stogie: INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }

    /**
    * @dev depositWithETH is used to enter CIG/ETH SLP, wrap to STOG, then stake the STOG
    *   sending ETH to this function will sell ETH to get an equal portion of CIG, then
    *   place both CIG and WETH to the CIG/ETH SLP.
    * @param _amountCigMin - Minimum CIG expected from swapping ETH portion
    * @param _deadline - Future timestamp, when to give up
    * @param _transferSurplus - should the dust be refunded? May cost more gas
    */
    function depositWithETH(
        uint256 _amountCigMin,
        uint64 _deadline,
        bool _transferSurplus
    ) external payable returns( /* don't need notReentrant */
        uint[] memory swpAmt, uint cigAdded, uint ethAdded, uint liquidity
    ) {
        require(msg.value > 0, "no ETH sent");
        IWETH(weth).deposit{value:msg.value}(); // wrap ETH to WETH
        return _depositSingleSide(
            weth,
            msg.value,
            _amountCigMin,
            _deadline,
            _transferSurplus
        );
    }

    /**
    * @dev depositWithWETH is used to enter CIG/ETH SLP, wrap to STOG, then stake the STOG
    *   This function will sell WETH to get an equal portion of CIG, then
    *   place both CIG and WETH to the CIG/ETH SLP.
    * @param _amount - How much WETH to use, assuming approved before
    * @param _amountCigMin - Minimum CIG expected from swapping ETH portion
    * @param _deadline - Future timestamp, when to give up
    * @param _transferSurplus - Should the dust be refunded? May cost more gas
    */
    function depositWithWETH(
        uint256 _amount,
        uint256 _amountCigMin,
        uint64 _deadline,
        bool _transferSurplus
    ) external payable returns( /* don't need notReentrant */
        uint[] memory swpAmt, uint cigAdded, uint ethAdded, uint liquidity
    ) {
        require(_amount > 0, "no WETH sent");
        safeERC20TransferFrom(
            IERC20(weth),
            msg.sender,
            address(this),
            _amount
        ); // take their WETH
        return _depositSingleSide(
            weth,
            _amount,
            _amountCigMin,
            _deadline,
            _transferSurplus
        );
    }

    /**
    * @dev depositWithToken is used to enter CIG/ETH SLP, wrap to STOG, then stake the STOG
    *   This function will sell a token to get WETH, then an equal portion of CIG, then
    *   place both CIG and WETH to the CIG/ETH SLP.
    * @param _amount - How much token to use, assuming approved before
    * @param _amountCigMin - Minimum CIG expected from swapping ETH portion
    * @param _token address of the token we are entering in with
    * @param _deadline - Future timestamp, when to give up
    * @param _transferSurplus - Should the dust be refunded? May cost more gas
    */
    function depositWithToken(
        uint256 _amount,
        uint256 _amountCigMin,
        address _token,
        uint64 _deadline,
        bool _transferSurplus
    ) external payable notReentrant returns(
        uint[] memory swpAmt, uint cigAdded, uint ethAdded, uint liquidity
    ) {
        require(_amount > 0, "no token sent");
        safeERC20TransferFrom(
            IERC20(_token),
            msg.sender,
            address(this),
            _amount
        ); // take their token
        return _depositSingleSide(
            _token,
            _amount,
            _amountCigMin,
            _deadline,
            _transferSurplus
        );
    }


    /**
    * @param _amountOutMin if the fromToken is CIG, _amountOutMin is min ETH we
    *   must get after swapping from CIG.
    *   if fromToken is ETH, _amountOutMin is min CIG we must get, after
    *   swapping ETH.
    *   if fromToken is other, _amountOutMin is min CIG we must get, after
    *   swapping the token to ETH then to CIG.
    */
    function _depositSingleSide(
        address fromToken,
        uint256 _amount,
        uint256 _amountOutMin,
        uint64 _deadline,
        bool _transferSurplus
    ) internal returns(
        uint[] memory swpAmt, uint addedA, uint addedB, uint liquidity
    ) {

        address[] memory path;
        path = new address[](2);
        uint112 r; // reserve
        if (fromToken == address(cig)) {
            (,r,) = cigEthSLP.getReserves();             // _reserve1 is CIG
            path[0] = fromToken;
            path[1] = weth;
        } else {
            if (fromToken != weth) {
                address pair = IUniswapV2Factory(sushiFactory).getPair(
                    fromToken, address(weth));           // find the token's WETH pair
                require (pair != address(0), "no liquidity for token");
                // swap the fromToken to WETH
                path[0] = fromToken;
                path[1] = weth;
                swpAmt = sushiRouter.swapExactTokensForTokens(
                    _amount,
                    1,                                   // min that must be received
                    path,
                    address(this),
                    _deadline
                );
                _amount = swpAmt[1];                     // now we have WETH
            }
            (r,,) = cigEthSLP.getReserves();             // _reserve0 is ETH
            path[0] = weth;
            path[1] = address(cig);                      // swapping a portion to CIG
        }
        uint256 a = _getSwapAmount(_amount, r);          // amount to swap to get equal amounts
        /*
        Swap "a" amount of path[0] for path[1] to get equal portions.
        */
        swpAmt = sushiRouter.swapExactTokensForTokens(
            a,
            _amountOutMin,                              // min amount that must be received
            path,
            address(this),
            _deadline
        );
        uint256 token0Amt = _amount - swpAmt[0];         // how much of IERC20(path[0]) we have left
        (addedA, addedB, liquidity) = sushiRouter.addLiquidity(
            path[0],
            path[1],
            token0Amt,                                  // Amt of the single-side token
            swpAmt[1],                                  // Amt received from the swap
            1,                                          // we've already checked slippage
            1,                                          // ditto
            address(this),
            block.timestamp
        );
        _wrap(address(this), address(this), liquidity); // wrap our liquidity to Stogie
        UserInfo storage user = farmers[msg.sender];
        update(); // updates the CIG factory
        /* _deposit updates user's account of STOG, so they can withdraw it later */
        _deposit(user, liquidity);                      // update the user's account
        cig.deposit(liquidity);                         // forward the SLP to the factory
        emit Deposit(msg.sender, liquidity);
        IIDCards(idCards).issueID(msg.sender);          // mint nft
        if (!_transferSurplus) {
            return (swpAmt, addedA, addedB, liquidity);
        }
        if (token0Amt > addedA) {
        unchecked{cig.transfer(
            msg.sender, token0Amt - addedA);}          // send surplus CIG back
        }
        if (swpAmt[1] > addedB) {
        unchecked{IERC20(weth).transfer(
            msg.sender, swpAmt[1] - addedB);}        // send surplus WETH back
        }
    }

    // Given some asset amount and reserves, returns an amount of the other asset representing equivalent value
    // Useful for calculating optimal token amounts before adding liq
    // todo
    function _quote(uint amountA, ILiquidityPool pool) internal view returns (uint amountB) {
        //require(amountA > 0, 'UniswapV2Library: INSUFFICIENT_AMOUNT');
        //require(reserveA > 0 && reserveB > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        (uint reserveA, uint reserveB,) = pool.getReserves();
        amountB = amountA * reserveB / reserveA;
    }

    /**
    *
    */
    function depositWithCIG(
        uint256 _amount,
        uint256 _amountWethMin,
        uint64 _deadline,
        bool _transferSurplus
    ) internal returns(
        uint[] memory swpAmt, uint cigAdded, uint ethAdded, uint liquidity
    ) {
       cig.transferFrom(msg.sender, address(this), _amount);
        (,uint112 _reserve1,) = cigEthSLP.getReserves();// _reserve1 is CIG
        uint256 a = _getSwapAmount(_amount, _reserve1); // a is amount of to swap to WETH to get equal portions
        /* now sell "a" mount of CIG to get WETH.   */
        address[] memory path;
        path = new address[](2);
        path[0] = address(cig);
        path[1] = weth;
        swpAmt = sushiRouter.swapExactTokensForTokens(
            _amount - a,
            _amountWethMin,                             // min WETH that must be received
            path,
            address(this),
            _deadline
        );
        uint256 amountCIG = _amount - swpAmt[0];
        (ethAdded, cigAdded, liquidity) = sushiRouter.addLiquidity(
            weth,
            address(cig),
            swpAmt[1],                                  // WETH to add
            amountCIG,                                  // CIG to add
            1,                                          // we've already checked slippage
            1,                                          // ditto
            address(this),
            block.timestamp
        );
        _wrap(address(this), address(this), liquidity); // wrap our liquidity to Stogie
        UserInfo storage user = farmers[msg.sender];
        update(); // updates the CIG factory
        /* _deposit updates user's account of STOG, so they can withdraw it later */
        _deposit(user, liquidity);                      // update the user's account
        cig.deposit(liquidity);                         // forward the SLP to the factory
        emit Deposit(msg.sender, liquidity);
        IIDCards(idCards).issueID(msg.sender);          // mint nft
        if (!_transferSurplus) {
            return (swpAmt, cigAdded, ethAdded, liquidity);
        }
        if (swpAmt[1] > cigAdded) {
        unchecked{cig.transfer(
            msg.sender, swpAmt[1]- cigAdded);}          // send surplus CIG back
        }
        if (amountCIG > ethAdded) {
        unchecked{IERC20(weth).transfer(
            msg.sender, amountCIG - ethAdded);}        // send surplus WETH back
        }
    }

    /**
    * @dev mint STOG using CIG and WETH
    * @param _amountCIG - amount of CIG we want to add
    * @param _amountWETH - amount of WETH we want to add
    * @param _amountCIGMin - minimum CIG that will be tolerated
    * @param _amountWETHMin - minimum WETH that will be tolerated
    * @param _deadline - timestamp when to expire
    * @param _transferSurplus - send back any change?
    */
    function depositCigWeth(
        uint256 _amountCIG,
        uint256 _amountWETH,
        uint256 _amountCIGMin,
        uint256 _amountWETHMin,
        uint64 _deadline,
        bool _transferSurplus
    ) external returns(
        uint cigAdded, uint ethAdded, uint liquidity)
    {
        IERC20(cig).transferFrom(msg.sender, address(this), _amountCIG);
        IERC20(weth).transferFrom(msg.sender, address(this), _amountWETH);
        (cigAdded, ethAdded, liquidity) = sushiRouter.addLiquidity(
            address(cig),
            weth,
            _amountCIG,                                  // CIG
            _amountWETH,                                 // WETH amount
            _amountCIGMin,                               //
            _amountWETHMin,                              //
            address(this),
            _deadline
        );
        UserInfo storage user = farmers[msg.sender];
        update(); // updates the CIG factory
        /* _deposit updates user's account of STOG, so they can withdraw it later*/
        _deposit(user, liquidity);                       // update the user's account
        cig.deposit(liquidity);                          // forward the SLP to the factory
        emit Deposit(msg.sender, liquidity);
        IIDCards(idCards).issueID(msg.sender);           // mint nft
        if (!_transferSurplus) {
            return(cigAdded, ethAdded, liquidity);
        }
        if (_amountCIG > cigAdded) {
        unchecked{cig.transfer(
            msg.sender, _amountCIG- cigAdded);}          // send surplus CIG back
        }
        if (_amountWETH > ethAdded) {
        unchecked{IERC20(weth).transfer(
            msg.sender, _amountWETH-ethAdded
        );}                                              // send surplus WETH back
        }
        return(cigAdded, ethAdded, liquidity);
    }



    /**
    * @param _amount how many STOG to withdraw
    */
    function withdrawToETH(uint256 _amount) external {

    }

    function withdrawToToken(uint256 _amount, address _token) external {

    }




    /**
    * @dev wrap LP tokens to STOG
    */
    function wrap(uint256 _amountLP) external {
        _wrap(msg.sender, msg.sender, _amountLP);
    }

    /**
    * @dev unwrap STOG to LP tokens
    */
    function unwrap(uint256 _amountSTOG) external {
        _unwrap(msg.sender, _amountSTOG);
    }

    /**
    * @dev Sell any token we hold for CIG, except for SLP and STOG
    */
    function sellTokenForCIG(address _token, address _pool) external {
        //require (_token != STOGPool, "cannot sell our STOGPool tokens");
        //require (_token != address(this), "cannot sell our me");
    }

    /**
    * @dev Harvest CIG, then use our CIG holdings to buy STOG, then stake the STOG.
    */
    function packSTOG() external {

        // harvest CIG first

        // buy STOG

        // unwrap to get LP

        // stake the LP

    }


    /**
    * @dev init will create the CIG/STOG pool for the first time
    *   It will also set all the approvals. It's assumed that LP tokens
    *   and CIG support unlimited approvals when set to type(uint256).max
    */
    function setup(uint _amountCIG, uint256 _amountCigEthSLP) external returns
    (address pool, uint token0, uint token1, uint liquidity) {
        require (stogiePool == address(0), "already initialized");
        address r = address(sushiRouter);
        cig.approve(r, type(uint256).max);                          // approve Sushi to use all of our CIG
        IERC20(weth).approve(r, type(uint256).max);                 // approve Sushi to use all of our WETH
        IERC20(cigEthSLP).approve(r, type(uint256).max);            // approve Sushi to use all of our CIG/ETH SLP
        _approve(address(this), r, type(uint256).max);              // approve Sushi to use all of our STOG
        cigEthSLP.approve(address(cig), type(uint256).max);         // approve CIG to use all of our CIG/ETH SLP
        cig.transferFrom(msg.sender, address(this), _amountCIG);    // take their CIG
        uint256 bal = cigEthSLP.balanceOf(msg.sender);
        require (bal >= _amountCigEthSLP, "not enough CIG/ETH SLP");
        _wrap(msg.sender, address(this), _amountCigEthSLP);         // take their CIG/ETH SLP, wrap, minting new STOG to here
        (token0, token1, liquidity) = sushiRouter
        .addLiquidity(
            address(cig),                                           // token0 (CIG)
            address(this),                                          // token1 (STOG)
                _amountCIG,                                         // amount of token 0 (CIG)
                _amountCigEthSLP,                                   // amount of token 1 (STOG)
            1,
            1,
            address(this),                                          // this contract will keep the underlying SLP
            block.timestamp
        );                                                          // create CIG/STOG pair
        stogiePool = IUniswapV2Factory(sushiFactory).getPair(
            address(cig), address(this));                           // save the pair address
        return (stogiePool, token0, token1, liquidity);
    }

    function _poolAndMint(
        address _token0,
        address _token1,
        uint256 _amount0,
        uint256 _amount1
    ) internal
    returns (uint amount0, uint amount1, uint liquidity) {
        ILiquidityPool p = ILiquidityPool(stogiePool);
        require (address(p) != address(0), "init not called");
        (amount0, amount1, liquidity) = sushiRouter.addLiquidity(
            _token0,
            _token1,
            _amount0,
            _amount1,
            1,
            1,
            address(this),
            block.timestamp
        );
        require (liquidity > 0, "failed to add to pool");
        _mint(msg.sender, liquidity); // mint STOG for the sender
    }

    /**
     * @dev _sqrt is the babylonian method from Uniswap Math.sol
     */
    function _sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    /**
    * @dev _getSwapAmount calculates how much _a we need to sell to have an equal portion when adding
       liquidity to a pool, that has a reserve balance of _r in that token. Includes 3% fee
       @param _a amount in
       @param _r reserve of _a in
    */
    function _getSwapAmount(uint256 _r, uint256 _a) internal pure returns (uint256){
        return (_sqrt((_a * ((_r * 3988000) + (_a * 3988009)))) - (_a * 1997)) / 1994;
    }

    /**
    * ERC20 functionality
    */
    string public constant name = "Stogies Token";
    string public constant symbol = "STOG";
    uint8 public constant decimals = 18;
    uint256 public totalSupply = 0;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    /**
    * @dev transfer transfers tokens for a specified address
    * @param _to The address to transfer to.
    * @param _value The amount to be transferred.
    */
    function transfer(address _to, uint256 _value) public returns (bool) {
        //require(_value <= balanceOf[msg.sender], "value exceeds balance"); // SafeMath already checks this
        balanceOf[msg.sender] = balanceOf[msg.sender] - _value;
        balanceOf[_to] = balanceOf[_to] + _value;
        emit Transfer(msg.sender, _to, _value);
        return true;
    }
    /**
    * @dev transferFrom transfers tokens from one address to another
    * @param _from address The address which you want to send tokens from
    * @param _to address The address which you want to transfer to
    * @param _value uint256 the amount of tokens to be transferred
    */
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) external returns (bool){
        uint256 a = allowance[_from][msg.sender]; // read allowance
        //require(_value <= balanceOf[_from], "value exceeds balance"); // SafeMath already checks this
        if (a != type(uint256).max) {             // not infinite approval
            require(_value <= a, "not approved");
            unchecked{allowance[_from][msg.sender] = a - _value;}
        }
        balanceOf[_from] = balanceOf[_from] - _value;
        balanceOf[_to] = balanceOf[_to] + _value;
        emit Transfer(_from, _to, _value);
        return true;
    }
    /**
    * @dev Approve tokens of mount _value to be spent by _spender
    * @param _spender address The spender
    * @param _value the stipend to spend
    */
    function approve(address _spender, uint256 _value) external returns (bool) {
        _approve(msg.sender, _spender, _value);
        return true;
    }
    /**
    * @dev burn some tokens
    * @param _from The address to burn from
    * @param _amount The amount to burn
    */
    function _burn(address _from, uint256 _amount) internal {
        balanceOf[_from] = balanceOf[_from] - _amount;
        totalSupply = totalSupply - _amount;
        emit Transfer(_from, address(0), _amount);
    }

    /**
    * @dev mint new tokens
    * @param _to The address to mint to.
    * @param _amount The amount to be minted.
    */
    function _mint(address _to, uint256 _amount) internal {
        require(_to != address(0), "ERC20: mint to the zero address");
        unchecked {totalSupply = totalSupply + _amount;}
        unchecked {balanceOf[_to] = balanceOf[_to] + _amount;}
        emit Transfer(address(0), _to, _amount);
    }

    /**
    * @dev _wrap takes CIG/ETH SLP from _form and mints STOG to _to.
    * @param _from the address to take the CIG/ETH SLP tokens from
    * @param _to the address to send the STOG to in return
    */
    function _wrap(address _from, address _to, uint256 _amount) internal {
        if (_from != address(this)) {
            cigEthSLP.transferFrom(_from, address(this), _amount);// take SLP
        }
        _mint(_to, _amount);                                      // give newly minted STOG
    }

    /**
    * @dev _unwrap redeems STOG for SLP, burning STOG
    */
    function _unwrap(address _for, uint256 _amount) internal {
        ILiquidityPool(stogiePool).transferFrom(_for, address(this), _amount);// take STOG
        cigEthSLP.transfer(_for, _amount);                                    // give SLP back
        _burn(_for, _amount);                                                 // burn STOG

    }

    /**
    * @dev _transfer transfers STOG tokens from one address to another without checking allowance,
       internal only
    * @param _from address The address which you want to send tokens from
    * @param _to address The address which you want to transfer to
    * @param _value uint256 the amount of tokens to be transferred
    */
    function _transfer(
        address _from,
        address _to,
        uint256 _value
    ) internal returns (bool){
        balanceOf[_from] = balanceOf[_from] - _value;
        balanceOf[_to] = balanceOf[_to] + _value;
        emit Transfer(_from, _to, _value);
        return true;
    }

    /**
    * @dev _approve is an unsafe approval, for internal calls only
    * @param _from account to pull funds from
    * @param _spender address that will pull the funds
    * @param _value amount to approve in wei
    */
    function _approve(address _from, address _spender, uint256 _value) internal  {
        allowance[_from][_spender] = _value;
        emit Approval(_from, _spender, _value);
    }

    /**
    * STOG staking
    */
    uint256 accCigPerShare; // Accumulated cigarettes per share, times 1e12.
    uint256 lastRewardBlock;
    uint256 employeeHeight; // the next available employee id
    // UserInfo keeps track of user LP deposits and withdrawals
    struct UserInfo {
        uint256 deposit;    // How many LP tokens the user has deposited.
        uint256 rewardDebt; // keeps track of how much reward was paid out
    }
    mapping (uint256 => address) cardOwners;
    mapping (address => UserInfo) public farmers;                    // keeps track of staking deposits and rewards
    event Deposit(address indexed user, uint256 amount);            // when depositing LP tokens to stake
    event Harvest(address indexed user, address to, uint256 amount);// when withdrawing LP tokens form staking
    event Withdraw(address indexed user, uint256 amount);           // when withdrawing LP tokens, no rewards claimed
    event EmergencyWithdraw(address indexed user, uint256 amount);  // when withdrawing LP tokens, no rewards claimed


    /**
    * @dev update updates the accCigPerShare value and harvests CIG from the Cigarette Token contract to
    *  be distributed to STOG stakers
    * @return cigReward - the amount of CIG that was credited to this contract
    */
    function update() public returns (uint256 cigReward){
        if (block.number <= lastRewardBlock) {
            return 0;                                         // can only be called once per block
        }
        uint256 b0 = cig.balanceOf(address(this));
        cig.harvest();                                        // harvest rewards
        uint256 b1 = cig.balanceOf(address(this));
        cigReward = b1 - b0;                                  // this is how much new CIG we received
        uint256 supply = balanceOf[address(this)];            // how much is staked in total
        if (supply == 0) {
            lastRewardBlock = block.number;
            return cigReward;
        }
        accCigPerShare = accCigPerShare + (cigReward * 1e12 / supply);
        lastRewardBlock = block.number;
        return cigReward;
    }

    /**
    * @dev pendingCig returns the amount of cig to be claimed
    * @param _user the address to report
    * @return the amount of CIG they can claim
    */
    function pendingCig(address _user) view public returns (uint256) {
        uint256 _acps = accCigPerShare;                       // accumulated cig per share
        UserInfo storage user = farmers[_user];
        uint256 supply = balanceOf[address(this)];            // how much is staked in total
        if (block.number > lastRewardBlock && supply != 0) {
            uint256 cigReward = cig.pendingCig(address(this));// get our pending reward
            _acps = _acps + (cigReward * 1e12 / supply);
        }
        return (user.deposit * _acps / 1e12) - user.rewardDebt;
    }

    /**
    * @dev deposit STOG tokens to stake
    */
    function deposit(uint256 _amount) public {
        require(_amount != 0, "You cannot deposit only 0 tokens");           // Has enough?
        UserInfo storage user = farmers[msg.sender];
        update();                                                            // updates the CIG factory
        _deposit(user, _amount);                                             // update the user's account
        require(_transfer(address(msg.sender), address(this), _amount));     // transfer STOG to this contract
        cig.deposit(_amount);                                                // forward the SLP to the factory
        emit Deposit(msg.sender, _amount);
        IIDCards(idCards).issueID(msg.sender);
    }

    /**
    * @dev _deposit updates how many STOG has been deposited for the user
    */
    function _deposit(UserInfo storage _user, uint256 _amount) internal {
        _user.deposit += _amount;
        _user.rewardDebt += _amount * accCigPerShare / 1e12;
    }


    /**
    * @dev transferStake transfers a stake to a new address
    *  _to must not have any stake. Harvests the stake before transfer
    */
    function transferStake(address _to, bool transferID) external {
        UserInfo storage userFrom = farmers[msg.sender];
        require (userFrom.deposit > 0, "from deposit must not be empty");
        UserInfo storage userTo = farmers[_to];
        require (userTo.deposit == 0, "userTo.deposit not empty");
        // harvest, move stake, remove old index, assign new index
        _harvest(userFrom, msg.sender);
        userTo.deposit = userFrom.deposit;
        userTo.rewardDebt = userFrom.rewardDebt;
        userFrom.deposit = 0;
        userFrom.rewardDebt = 0;
        if (transferID) {
            uint id = IIDCards(idCards).cardOwners(msg.sender);
            IIDCards(idCards).safeTransferFrom(msg.sender, _to, id);
        }
    }


    /**
    * @dev withdraw takes out the LP tokens
    * @param _amount the amount to withdraw
    * @return harvested amount of CIG harvested
    */
    function withdraw(uint256 _amount) public returns (uint256 harvested) {
        UserInfo storage user = farmers[msg.sender];
        /* update() will harvest CIG for everyone before emergencyWithdraw, this important. */
        update();                                                       // fetch CIG rewards for everyone

        /* use difference between b0 and b1 to work out how many tokens were received */
        uint256 b0 = cigEthSLP.balanceOf(address(this));
        cig.emergencyWithdraw();                                        // take out the SLP from the factory
        uint256 b1 = cigEthSLP.balanceOf(address(this));
        cigEthSLP.transfer(msg.sender, _amount);                        // give SLP back

        uint256 butt = b1 - b0 - _amount;
        if (butt > 0) {
            cig.deposit(butt);                                          // put the SLP back into the factory, sans _amount
        }
        /* harvest beforehand, so _withdraw can safely decrement their reward count */
        harvested = _harvest(user, msg.sender);                         // distribute the user's reward
        _withdraw(user, _amount);                                       // update accounting for withdrawal
        require(_transfer(address(this), address(msg.sender), _amount));// send STOG back
        emit Withdraw(msg.sender, _amount);
        return harvested;
    }

    /**
    * @dev Internal withdraw, updates internal accounting after withdrawing LP
    * @param _amount to subtract
    */
    function _withdraw(UserInfo storage _user, uint256 _amount) internal {
        require(_user.deposit >= _amount, "Balance is too low");
        _user.deposit -= _amount;
        uint256 _rewardAmount = _amount * accCigPerShare / 1e12;
        _user.rewardDebt -= _rewardAmount;
    }

    /**
    * @dev harvest redeems pending rewards & updates state
    * @return received is the amount that was harvested
    */
    function harvest() public returns (uint256 received){
        UserInfo storage user = farmers[msg.sender];
        update();
        return _harvest(user, msg.sender);
    }

    /**
    * @dev Internal harvest
    * @param _to the amount to harvest
    */
    function _harvest(UserInfo storage _user, address _to) internal returns(uint256 delta) {
        uint256 potentialValue = _user.deposit * accCigPerShare / 1e12;
        delta = potentialValue - _user.rewardDebt;
        cig.transfer(_to, delta);                                 // give them their rewards
        _user.rewardDebt = _user.deposit * accCigPerShare / 1e12; // Recalculate their reward debt
        emit Harvest(msg.sender, _to, delta);

        return delta;
    }

    /**
    * @dev getStats gets all the current stats & states of the contract
    * @param _user the user address to lookup
    */
    function getStats(address _user) external view returns (
        uint256[] memory                               // ret
    ) {
        uint[] memory ret = new uint[](59);
     //   return ret;
        UserInfo memory info = farmers[_user];
        ILiquidityPool ethusd = ILiquidityPool(
            address(
                0xC3D03e4F041Fd4cD388c549Ee2A29a9E5075882f
            ));                                        // sushi DAI-WETH pool
        ret[0] = info.deposit;                         // how much STOG staked by user
        ret[1] = info.rewardDebt;                      // amount of rewards paid out for user
        ret[2] = balanceOf[address(this)];             // contract's STOGE balance
        ret[3] = balanceOf[_user];                     // user's STOG balance
        ret[4] = cig.balanceOf(_user);                 // user's CIG balance
        ret[5] = cigEthSLP.balanceOf(_user);           // user's CIG/ETH SLP balance
        ret[6] = cigEthSLP.balanceOf(address(this));   // contract CIG/ETH SLP balance
        (ret[7], ret[8],) = cigEthSLP.getReserves();   // CIG/ETH SLP reserves, ret[7] is ETH, ret[8] is CIG
        ret[9] = lastRewardBlock;                      // when rewards were last calculated
        ret[10] = accCigPerShare;                      // accumulated CIG per STOG share
        ret[11] = pendingCig(_user);                   // pending CIG reward to be harvested
        ret[12] = IERC20(weth).balanceOf(_user);       // user's WETH balance
        ret[13] = _user.balance;                       // user's ETH balance
        ret[14] = cig.allowance(_user, address(this)); // user's approval to spend CIG
        ret[15] = cigEthSLP.allowance(
            _user, address(this));                     // user's approval to spend STOG
        ret[16] = IERC20(weth)
            .allowance(_user, address(this));          // user's approval to spend WETH
        ret[17] = block.number;                        // current block number
        ret[18] = sushiRouter.getAmountOut(
            1 ether, uint(ret[8]), uint(ret[7]));      // How much CIG for 1 ETH (ETH price in CIG)
        (ret[19], ret[20],) = ethusd.getReserves();    // ETH/DAI reserves
        ret[21] = sushiRouter.getAmountOut(
            1 ether, ret[19], ret[20]);                // ETH price in USD
        ret[22] = cigEthSLP.totalSupply();             // total supply of CIG/ETH SLP
        ret[23] = totalSupply;                         // total supply of STOG
        ret[24] = cig.totalSupply();                   // total supply of CIG
        ret[25] = cigEthSLP.balanceOf(address(cig));   // total amount of CIG/ETH in Cigarettes contract
        ret[26] = cig.cigPerBlock();                   // number of new CIG entering the supply
        (ret[27],ret[28],) =
            ILiquidityPool(stogiePool).getReserves();  // reserves of CIG/STOG pool
        ret[29] = uint256(uint160(
                ILiquidityPool(stogiePool).token0())); // address of token0 / ret[27]
        ret[30] = block.timestamp;                     // current timestamp
        ret[31] = cig.balanceOf(address(this));        // CIG in contract
        return ret;
    }

    function safeERC20Transfer(IERC20 _token, address _to, uint256 _amount) internal {
        bytes memory payload = abi.encodeWithSelector(_token.transfer.selector, _to, _amount);
        (bool success, bytes memory returndata) = address(_token).call(payload);
        require(success, "safeERC20Transfer failed");
        if (returndata.length > 0) { // check return value if it was returned
            require(abi.decode(returndata, (bool)), "safeERC20Transfer failed did not succeed");
        }
    }

    function safeERC20TransferFrom(IERC20 _token, address _from, address _to, uint256 _amount) internal {
        bytes memory payload = abi.encodeWithSelector(_token.transferFrom.selector, _from, _to, _amount);
        (bool success, bytes memory returndata) = address(_token).call(payload);
        require(success, "safeERC20TransferFrom failed");
        if (returndata.length > 0) { // check return value if it was returned
            require(abi.decode(returndata, (bool)), "safeERC20TransferFrom did not succeed");
        }
    }
}

interface IUniswapV2Router {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    )
    external
    returns (
        uint amountA,
        uint amountB,
        uint liquidity
    );

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
}

interface IUniswapV2Factory {
    function getPair(address token0, address token1) external view returns (address);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint wad) external;
}


interface IV2Router {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
    external
    payable
    returns (uint[] memory amounts);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) external pure returns(uint256 amountOut);
}

/*
 * @dev Interface of the ERC20 standard as defined in the EIP.
 * 0xTycoon was here
 */
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface ILiquidityPool is IERC20 {
    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast);
    function token0() external view returns (address);
}

interface ICigToken is IERC20 {
    struct UserInfo {
        uint256 deposit;    // How many LP tokens the user has deposited.
        uint256 rewardDebt; // keeps track of how much reward was paid out
    }
    function emergencyWithdraw() external; // make sure to call harvest before calling this
    function harvest() external;
    function deposit(uint256 _amount) external;
    function pendingCig(address) external view returns (uint256);
    function cigPerBlock() external view returns (uint256);
    //function farmers(address _user) external view returns (UserInfo);
    //function stakedlpSupply() external view returns(uint256);

    //function withdraw(uint256 _amount) external // bugged, use emergencyWithdraw() instead.
}

interface IIDCards {
    function balanceOf(address _holder) external view returns (uint256);
    function safeTransferFrom(address,address,uint256) external;
    function cardOwners(address) external view returns (uint256);
    function issueID(address _to) external;
}