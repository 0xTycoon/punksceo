// SPDX-License-Identifier: MIT
// 🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔
// Author: tycoon.eth
// 🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔
pragma solidity ^0.8.19;

import "hardhat/console.sol";

/**

This contract introduces the "Stogies", and improves the UX for the
Cigarette Factory.

What are Stogies?

An ERC20 token that wraps the CIG/ETH SushiSwap Liquidity Pool (SLP)
token, for meme-ability and ease of use. Each Stogie represents a share of the
ETH & CIG reserves stored at 0x22b15c7ee1186a7c7cffb2d942e20fc228f6e4ed.

To work out how much is a Stogie worth, add the values of ETH and CIG in the
pool, and divide them by the total supply of the SLP token.
For example, if there are $100 worth of CIG and $100 worth of ETH in the pool,
and the total supple of the SLP token is 1000, then each token would be worth
(100+100)/1000 = 0.2, or 20 cents. Note that the SLP tokens do not have a capped
supply and new tokens can be minted by anyone, by adding more CIG & ETH to the
pool. This means that Stogies are not capped, only limited by the amount of ETH
and CIG can practically be added to the pool. For the Solidity devs, you can
read stogies.sol for the implementation of Stogies.


*/


contract Stogie {
    ICigToken private immutable cig;           // 0xCB56b52316041A62B6b5D0583DcE4A8AE7a3C629
    ILiquidityPool private immutable cigEthSLP;// 0x22b15c7ee1186a7c7cffb2d942e20fc228f6e4ed (SLP, it's also an ERC20)
    address private immutable weth;            // 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    IV2Router private immutable sushiRouter;   // 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F
    address private immutable sushiFactory;    // 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac
    IV2Router private immutable uniswapRouter; // 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
    address public stogiePool;                 // will be created with init()
    uint8 internal locked = 1;                 // reentrancy guard. 2 = entered, 1 not
    bytes32 public DOMAIN_SEPARATOR;           // EIP-2612 permit functionality
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public nonces;    // EIP-2612 permit functionality
    IIDBadges private immutable badges;        // id badges erc721
    modifier notReentrant() { // notReentrant is a reentrancy guard
        require(locked == 1, "already entered");
        locked = 2; // enter
        _;
        locked = 1; // exit
    }
    constructor(
        address _cig,
        address _CigEthSLP,
        address _sushiRouter,
        address _sushiFactory,
        address _uniswapRouter,
        address _weth,
        address _badges
    ) {
        cig = ICigToken(_cig);
        cigEthSLP = ILiquidityPool(_CigEthSLP);
        sushiRouter = IV2Router(_sushiRouter);
        sushiFactory = _sushiFactory;
        uniswapRouter = IV2Router(_uniswapRouter);
        weth = _weth;
        badges = IIDBadges(_badges);
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
        address r = address(sushiRouter);
        cig.approve(r, type(uint256).max);                          // approve Sushi to use all of our CIG
        IERC20(weth).approve(r, type(uint256).max);                 // approve Sushi to use all of our WETH
        IERC20(cigEthSLP).approve(r, type(uint256).max);            // approve Sushi to use all of our CIG/ETH SLP
        allowance[address(this)][r] = type(uint256).max;
        emit Approval(address(this), r, type(uint256).max);
        cigEthSLP.approve(address(cig), type(uint256).max);         // approve CIG to use all of our CIG/ETH SLP
    }

    /** todo test
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
    * Sending ETH to this contract will automatically issue Stogies and stake them
    *    it will also issue a badge to the user. Can only be used by addresses that
    *    have not minted. Limited yp 1 ETH or less.
    */
    receive() external payable {
        require(msg.value > 0, "need ETH");
        require(msg.value <= 1 ether, "Too much ETH");
        IWETH(weth).deposit{value:msg.value}();// wrap ETH to WETH
        _depositSingleSide(
            weth,
            msg.value,
            0,                                  // no min
            uint64(block.timestamp),            // same block
            false,                              // no surplus
            (badges.minters(msg.sender) == 0)   // mint an id?
        );
    }

    /**
    * @dev depositWithETH is used to enter CIG/ETH SLP, wrap to STOG, then stake the STOG
    *   sending ETH to this function will sell ETH to get an equal portion of CIG, then
    *   place both CIG and WETH to the CIG/ETH SLP.
    * @param _amountCigMin - Minimum CIG expected from swapping ETH portion
    * @param _deadline - Future timestamp, when to give up
    * @param _transferSurplus - should the dust be refunded? May cost more gas
    * @param _mintId mint a badge NFT for the msg.sender?
    */
    function depositWithETH(
        uint256 _amountCigMin,
        uint64 _deadline,
        bool _transferSurplus,
        bool _mintId
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
            _transferSurplus,
            _mintId
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
    * @param _mintId mint a badge NFT for the msg.sender?
    */
    function depositWithWETH(
        uint256 _amount,
        uint256 _amountCigMin,
        uint64 _deadline,
        bool _transferSurplus,
        bool _mintId
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
            _transferSurplus,
            _mintId
        );
    }

    /**
    * @dev depositWithToken is used to enter CIG/ETH SLP, wrap to STOG, then
    *   stake the STOG.
    *   This function will sell a token to get WETH, then sell a portion of WETH
    *   to get an equal portion of CIG, then stake, by placeing both CIG and
    *   WETH to the CIG/ETH SLP.
    * @param _amount - How much token to use, assuming approved before
    * @param _amountCigMin - Minimum CIG expected from swapping ETH portion
    *   (final output swap)
    * @param _amountWethMin - Minimum WETH expected from swapping _token
    *   (1st hop swap)
    * @param _token address of the token we are entering in with
    * @param _router address of router to use (Sushi or Uniswap)
    * @param _deadline - Future timestamp, when to give up
    * @param _transferSurplus - Should the dust be refunded? May cost more gas
    * @param _mintId mint a badge NFT for the msg.sender?
    */
    function depositWithToken(
        uint256 _amount,
        uint256 _amountCigMin,
        uint256 _amountWethMin,
        address _token,
        address _router,
        uint64 _deadline,
        bool _transferSurplus,
        bool _mintId
    ) external payable notReentrant returns(
        uint[] memory swpAmt, uint cigAdded, uint ethAdded, uint liquidity
    ) {
        require(
            (_token != weth) && (_token != address(cig)),
            "must not be WETH or CIG"
        );
        require(_amount > 0, "no token sent");
        safeERC20TransferFrom(
            IERC20(_token),
            msg.sender,
            address(this),
            _amount
        ); // take their token
        swpAmt = _swapTokenToWETH(_amount, _amountWethMin, _router, _token, _deadline);
        // now we have WETH
        return _depositSingleSide(
            weth,
            swpAmt[1],
            _amountCigMin,
            _deadline,
            _transferSurplus,
            _mintId
        );
    }

    /**
    * swap all tokens to WETH. Internal function used when depositing with token
    *    other than CIG or WETH
    */
    function _swapTokenToWETH(
        uint256 _amount,
        uint256 _amountWethMin,
        address _router,
        address _token,
        uint64 _deadline
    ) internal returns (uint[] memory swpAmt) {
        IV2Router r;
        if (_router == address(uniswapRouter)) {
            r = IV2Router(uniswapRouter);                   // use Uniswap for intermediate swap
        } else {
            r = sushiRouter;
        }
        if (IERC20(_token).allowance(address(this), address(r)) < _amount) {
            IERC20(_token).approve(
                address(r), type(uint256).max
            );                                              // unlimited approval
        }
        // swap the _token to WETH
        address[] memory path;
        path = new address[](2);
        path[0] = _token;
        path[1] = weth;
        swpAmt = r.swapExactTokensForTokens(
            _amount,
            _amountWethMin,                                // min ETH that must be received
            path,
            address(this),
            _deadline
        );
        return swpAmt;
    }

    /**
    * @dev deposit with CIG single side liquidity
    * @param _amount in CIG to deposit
    * @param _amountWethMin minimum CIG we expect to get
    * @param _deadline - Future timestamp, when to give up
    * @param _transferSurplus - Should the dust be refunded? May cost more gas
    * @param _mintId mint a badge NFT for the msg.sender?
    */
    function depositWithCIG(
        uint256 _amount,
        uint256 _amountWethMin,
        uint64 _deadline,
        bool _transferSurplus,
        bool _mintId
    ) external payable notReentrant returns(
        uint[] memory swpAmt, uint cigAdded, uint ethAdded, uint liquidity
    ) {
        cig.transferFrom(msg.sender, address(this), _amount); // tage their CIG
        return _depositSingleSide(
            address(cig),
            _amount,
            _amountWethMin,
            _deadline,
            _transferSurplus,
            _mintId
        );
    }

    /**
    * @param _amountOutMin if the fromToken is CIG, _amountOutMin is min ETH we
    *   must get after swapping from CIG.
    *   if fromToken is WETH, _amountOutMin is min CIG we must get, after
    *   swapping WETH.
    *   if fromToken is CIG, _amountOutMin is min WETH we must get, after
    *   swapping the token to WETH.
    */
    function _depositSingleSide(
        address _fromToken,
        uint256 _amount,
        uint256 _amountOutMin,
        uint64 _deadline,
        bool _transferSurplus,
        bool _mintId
    ) internal returns(
        uint[] memory swpAmt, uint addedA, uint addedB, uint liquidity
    ) {
        address[] memory path;
        path = new address[](2);
        uint112 r; // reserve
        if (_fromToken == address(cig)) {
            (,r,) = cigEthSLP.getReserves();           // _reserve1 is CIG
            path[0] = _fromToken;
            path[1] = weth;
        } else if (_fromToken == weth) {
            (r,,) = cigEthSLP.getReserves();           // _reserve0 is ETH
            path[0] = weth;
            path[1] = address(cig);                    // swapping a portion to CIG
        } else {
            revert("invalid token");
        }
        uint256 a = _getSwapAmount(_amount, r);        // amount to swap to get equal amounts
        /*
        Swap "a" amount of path[0] for path[1] to get equal portions.
        */
        swpAmt = sushiRouter.swapExactTokensForTokens(
            a,
            _amountOutMin,                             // min amount that must be received
            path,
            address(this),
            _deadline
        );
        uint256 token0Amt = _amount - swpAmt[0];       // how much of IERC20(path[0]) we have left
        (addedA, addedB, liquidity) = sushiRouter.addLiquidity(
            path[0],
            path[1],
            token0Amt,                                 // Amt of the single-side token
            swpAmt[1],                                 // Amt received from the swap
            1,                                         // we've already checked slippage
            1,                                         // ditto
            address(this),
            block.timestamp
        );
        _wrap(address(this), address(this), liquidity);// wrap our liquidity to Stogie
        /* update user's account of STOG, so they can withdraw it later */
        _addStake(msg.sender, liquidity, _mintId);     // update the user's account
        if (!_transferSurplus) {
            return (swpAmt, addedA, addedB, liquidity);
        }
        uint temp;
        if (token0Amt > addedA) {
            unchecked{temp = token0Amt - addedA;}
            safeERC20Transfer(
                IERC20(_fromToken),
                msg.sender,
                temp);                                 // send surplus token back
        }
        if (swpAmt[1] > addedB) {
            unchecked{temp = swpAmt[1] - addedB;}
            IERC20(weth).transfer(
            msg.sender, temp);                         // send surplus WETH back
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
    * @param _mintId - mint a badge NFT?
    */
    function depositCigWeth(
        uint256 _amountCIG,
        uint256 _amountWETH,
        uint256 _amountCIGMin,
        uint256 _amountWETHMin,
        uint64 _deadline,
        bool _transferSurplus,
        bool _mintId
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
            _amountCIGMin,                               // minimum CIG to get
            _amountWETHMin,                              // minimum WETH to get
            address(this),
            _deadline
        );
        _wrap(address(this), address(this), liquidity);  // wrap our liquidity to Stogie
        _addStake(msg.sender, liquidity, _mintId);       // update the user's account
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
    * @dev withdrawToETH unstake, remove liquidity & swap CIG portion to WETH.
    *    Also, CIG will be harvested and sold for WETH.
    *    Note: UI should check to see how much WETH is expected to be output
    *    by estimating the removal of liquidity and then simulating the swap.
    * @param _liquidity, The amount of liquidity tokens to remove.
    * @param _amountCIGMin, The minimum amount of CIG that must be received for
    *   the transaction not to revert.
    * @param _amountWETHMin, The minimum amount of WETH that must be received for
     *   the transaction not to revert.
    * @param _deadline block number of expiry
    */
    function withdrawToWETH(
        uint _liquidity,
        uint _amountCIGMin,  // input
        uint _amountWETHMin, // output
        uint _deadline
    ) external returns(uint out) {
        out = _withdrawSingleSide(
            msg.sender,
            address(cig),
            weth,
            _liquidity,
            _amountCIGMin,
            _amountWETHMin,
            _deadline
        );
        IERC20(weth).transfer(
            msg.sender,
            out
        );         // send WETH back
        return out;
    }

    /**
    * @dev withdrawToCIG unstake, remove liquidity & swap ETH portion to CIG.
    *    Note: UI should check to see how much CIG is expected to be output
    *    by estimating the removal of liquidity and then simulating the swap.
    * @param _liquidity amount of Stog to remove
    * @param  _amountWETHMin min out WETH  when removing liquidity
    * @param _amountCIGMin  min out CIG  when removing liquidity
    * @param _deadline timestamp in seconds
    */
    function withdrawToCIG(
        uint256 _liquidity,
        uint _amountWETHMin,
        uint _amountCIGMin,
        uint _deadline
    ) external returns (uint out) {
        out = _withdrawSingleSide(
            msg.sender,
            weth,
            address(cig),
            _liquidity,
            _amountWETHMin,
            _amountCIGMin,
            _deadline
        );
        cig.transfer(
            msg.sender,
            out
        );         // send CIG back
        return out;
    }

    /**
    * @param _amount, how much STOG to withdraw
    * @param _token, address of token to withdraw to
    * @param _router, address of V2 router to use for the swap (Uni/Sushi)
    * @param _amountCIGMin, The minimum amount of CIG that must be received
    *   for the transaction not to revert, when removing liquidity
    * @param _amountWETHMin, The minimum amount of WETH that must be received
    *   for the transaction not to revert, when removing liquidity
    * @param _amountTokenMin, the min amount of _token to receive, when the
    *   WETH to _token
    * @param _deadline, expiry block number
    */
    function withdrawToToken(
        uint256 _amount,
        address _token,
        address _router,
        uint _amountCIGMin,
        uint _amountWETHMin,
        uint _amountTokenMin,
        uint _deadline
    ) external notReentrant returns (uint out) {
        require(
            (_token != weth) && (_token != address(cig)),
            "must not be WETH or CIG"
        );
        /* Withdraw to WETH first, then WETH to _token */
        out = _withdrawSingleSide(
            msg.sender,
            address(cig),
            weth,
            _amount,
            _amountCIGMin,
            _amountWETHMin,
            _deadline
        );
        IV2Router r;
        if (_router == address(uniswapRouter)) {
            r = IV2Router(uniswapRouter); // use Uniswap for intermediate swap
        } else {
            r = sushiRouter;
        }
        // swap the WETH to _token
        address[] memory path;
        path = new address[](2);
        path[0] = weth;
        path[1] = _token;
        uint[] memory swpAmt = r.swapExactTokensForTokens(
            out,
            _amountTokenMin,              // min _token that must be received
            path,
            address(this),
            _deadline
        );
        out = swpAmt[1];
        safeERC20Transfer(
            IERC20(_token),
            msg.sender,
            out
        );                                // send token back
        return out;
    }

    /**
     * @dev withdrawCIGWETH harvests CIG, withdraws and un-stakes STOG, then
     *    burns STOG down to WETH & CIG, which is returned back to the caller.
     * @param _liquidity, amount of STOG to withdraw
     * @param _amountCIGMin, The minimum amount of CIG that must be received
     *   for the transaction not to revert, when removing liquidity
     * @param _amountWETHMin, The minimum amount of ETH that must be received
     *   for the transaction not to revert, when removing liquidity
     * @param _deadline, expiry block number
     */
    function withdrawCIGWETH(
        uint256 _liquidity,
        uint _amountCIGMin,
        uint _amountWETHMin,
        uint _deadline
    ) external returns(uint amtCIGOut, uint amtWETHout, uint harvested) {
        harvested = _withdraw(
            _liquidity,
            msg.sender,
            address(this)
        );                         // harvest and withdraw on behalf of msg.sender
        cig.transfer(
            msg.sender,
            harvested
        );                         // send harvested CIG
        _unwrap(
            address(this),
            _liquidity
        );                         // Unwrap STOG to CIG/ETH SLP token, burning STOG
        (amtCIGOut, amtWETHout) = sushiRouter.removeLiquidity(
            address(cig),
            weth,
            _liquidity,
            _amountCIGMin,
            _amountWETHMin,
            msg.sender,
            _deadline
        );                          // This burns the CIG/SLP token, gives us CIG & WETH
        return (amtCIGOut, amtWETHout, harvested);
    }

    /**
    @param _farmer, the user we harvest and collect for
    @param _tokenA, input token address
    @param _tokenB, output token address
    @param _liquidity, amount of SLP to withdraw
    @param _amountAMin, min amount of _tokenA we expect to get after removal
    @param _amountBMin, min amount of _tokenB we expect to get after removal
    @param _deadline, expiry block number
    */
    function _withdrawSingleSide(
        address _farmer,
        address _tokenA,
        address _tokenB,
        uint _liquidity,
        uint _amountAMin,
        uint _amountBMin,
        uint _deadline
    ) internal returns(
        uint output
    ) {
        uint harvested = _withdraw(
            _liquidity,
            _farmer,
            address(this)
        );                          // harvest and withdraw on behalf of the user.
        _unwrap(
            address(this),
            _liquidity
        );                          // Unwrap STOG to CIG/ETH SLP token, burning STOG
        (uint amtAOutput, uint amtBOutput) = sushiRouter.removeLiquidity(
            _tokenA,
            _tokenB,
            _liquidity,
            _amountAMin,
            _amountBMin,
            address(this),
            _deadline
        );                          // This burns the CIG/SLP token, gives us _tokenA & _tokenB
        /*
        Swap the _tokenA portion to _tokenB
        */
        address[] memory path;
        path = new address[](2);
        path[0] = _tokenA;
        path[1] = _tokenB;
        uint256 swapInput = amtAOutput;
        /*
        If outputting to WETH, sell harvested CIG to WETH, otherwise
        add it to the total output
        */
        if (_tokenB == address(weth)) {
            swapInput += harvested; // swap harvested CIG to WETH
        } else {
            amtBOutput += harvested;// add the harvested CIG to amtB total
        }
        uint[] memory swpAmt;
        swpAmt = sushiRouter.swapExactTokensForTokens(
            swapInput,
            1,                      // assuming reserves won't change since last swap
            path,
            address(this),
            _deadline
        );
        // swpAmt[0] is the input
        // swpAmt[1] is output
        return (swpAmt[1] + amtBOutput);
    }


    /** todo test
    * @dev wrap LP tokens to STOG
    */
    function wrap(uint256 _amountLP) external {
        require(_amountLP != 0, "_amountLP cannot be 0"); // Has enough?
        _wrap(msg.sender, msg.sender, _amountLP);
    }

    /**
    * @dev unwrap STOG to LP tokens
    */
    function unwrap(uint256 _amountSTOG) external {
        _unwrap(msg.sender, _amountSTOG);
    }


    /** todo test
    * @dev unwrap STOG to CIG and ETH tokens
    */
    function unwrapToCIGETH(
        uint256 _amountSTOG,
        uint _amountCIGMin,
        uint _amountWETHMin,
        uint _deadline) external returns(uint amtCIGOut, uint amtWETHout) {
        _transfer(msg.sender, address(this), _amountSTOG);            // take their STOG
        (amtCIGOut, amtWETHout) = sushiRouter.removeLiquidity(
            address(cig),
            weth,
            _amountSTOG,
            _amountCIGMin,
            _amountWETHMin,
            msg.sender,                                               // return CIG/ETH to user
            _deadline
        );
        _burn(_amountSTOG);                                           // Burn the STOG
    }

    /** todo test
    * @dev Harvest CIG, then use our CIG holdings to buy STOG, then stake the STOG.
    * @param _amountSTOGMin min amount of STOG we should get after swapping the
    *   harvested CIG.
    */
    function packSTOG(
        uint _amountSTOGMin,
        uint64 _deadline
    ) external {
        UserInfo storage user = farmers[msg.sender];
        uint harvested = _harvest(
            user,
            address(this)
        );                                      // harvest CIG first
        /* swap harvested CIG to STOG */
        address[] memory path;
        path = new address[](2);
        path[0] = address(cig);
        path[1] = address(this);
        uint[] memory swpAmt;
        swpAmt = sushiRouter.swapExactTokensForTokens(
            harvested,
            _amountSTOGMin,                     // min amount that must be received
            path,
            address(this),
            _deadline
        );
        // stake the STOG for the user
        _addStake(msg.sender, swpAmt[1], false);// update the user's account
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
    /** todo test
    * @dev transfer transfers tokens for a specified address
    * @param _to The address to transfer to.
    * @param _value The amount to be transferred.
    */
    function transfer(address _to, uint256 _value) public returns (bool) {
        _transfer(msg.sender, _to, _value);
        return true;
    }
    /** todo test
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
        _transfer(_from, _to, _value);
        return true;
    }
    /** todo test
    * @dev Approve tokens of mount _value to be spent by _spender
    * @param _spender address The spender
    * @param _value the stipend to spend
    */
    function approve(address _spender, uint256 _value) external returns (bool) {
        _approve(msg.sender, _spender, _value);
        return true;
    }
    /**
    * @dev burn some STOG tokens
    * @param _amount The amount to burn
    */
    function _burn(uint256 _amount) internal {
        balanceOf[address(this)] = balanceOf[address(this)] - _amount;
        totalSupply = totalSupply - _amount;
        emit Transfer(address(this), address(0), _amount);
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
    * @param _from address to unwrap for
    * @param _amount how much
    */
    function _unwrap(address _from, uint256 _amount) internal {
        if (_from != address(this)) {
            _transfer(_from, address(this), _amount);     // take STOG
            cigEthSLP.transfer(_from, _amount);           // give SLP back
        }
        _burn(_amount);                                   // burn STOG
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
    ) internal returns (bool) {
        //require(_value <= balanceOf[_from], "value exceeds balance"); // SafeMath already checks this
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
    // UserInfo keeps track of user LP deposits and withdrawals
    struct UserInfo {
        uint256 deposit;    // How many LP tokens the user has deposited.
        uint256 rewardDebt; // keeps track of how much reward was paid out
    }
    mapping (address => UserInfo) public farmers;                   // keeps track of staking deposits and rewards
    event Deposit(address indexed user, uint256 amount);            // when depositing LP tokens to stake
    event Harvest(address indexed user, address to, uint256 amount);// when withdrawing LP tokens form staking
    event Withdraw(address indexed user, uint256 amount);           // when withdrawing LP tokens, no rewards claimed
    event TransferStake(address indexed from, address indexed to, uint256 amount); // when a stake is transferred

    /**
    * @dev update updates the accCigPerShare value and harvests CIG from the Cigarette Token contract to
    *  be distributed to STOG stakers
    * @return cigReward - the amount of CIG that was credited to this contract
    */
    function fetchCigarettes() public returns (uint256 cigReward){
        (uint256 supply,) = cig.farmers(address(this));       // how much is staked in total
        if (supply == 0) {
            return 0;
        }
        uint256 b0 = cig.balanceOf(address(this));
        cig.harvest();                                        // harvest rewards
        uint256 b1 = cig.balanceOf(address(this));
        cigReward = b1 - b0;                                  // this is how much new CIG we received
        if (cigReward == 0) {
            return 0;
        }
        accCigPerShare = accCigPerShare + (cigReward * 1e12 / supply);
        return cigReward;
    }

    /**
    * todo remove this
    */
    function test(uint256 _user) view external returns(uint256) {
        UserInfo storage user = farmers[msg.sender];
        uint256 depositRatio = (10 ether * 1e12) / (uint256(30 ether) ) ;


        //333333333333000000

        // 1460706847345

        console.log("tycoon has        :", user.deposit);
        console.log("total             :", balanceOf[address(this)]);
        //console.log("tycoon should have:",  balanceOf[address(this)] * 1e12 / depositRatio);
        // return depositRatio;
        uint256 out = 1 ether;
        return out *  depositRatio / 1e12;
    }


    /** todo test
    * Fill the contract with additional CIG for rewards
    */
    function fill(uint256 _amount) external {
        require (_amount > 1 ether, "insert coin");
        cig.transferFrom(msg.sender, address(this), _amount);
        (uint256 supply,) = cig.farmers(address(this));            // how much is staked in total
        require (supply > 0, "nothing staking");
        accCigPerShare = accCigPerShare + (_amount * 1e12 / supply);
    }

    /**
    * @dev pendingCig returns the amount of cig to be claimed
    * @param _user the address to report
    * @return the amount of CIG they can claim
    */
    function pendingCig(address _user) view public returns (uint256) {
        uint256 _acps = accCigPerShare;                       // accumulated cig per share
        UserInfo storage user = farmers[_user];
        (uint256 supply,) = cig.farmers(address(this));       // how much is staked in total
        uint256 cigReward = cig.pendingCig(address(this));    // get our pending reward
        if (cigReward == 0 || supply == 0) {
            return 0;
        }
        _acps = _acps + (cigReward * 1e12 / supply);
        return (user.deposit * _acps / 1e12) - user.rewardDebt;
    }

    /** todo test
    * @dev deposit STOG tokens to stake
    */
    function deposit(uint256 _amount, bool _mintId) public {
        require(_amount != 0, "You cannot deposit only 0 tokens");           // Has enough?
        require(_transfer(address(msg.sender), address(this), _amount));     // transfer STOG to this contract
        _addStake(msg.sender, _amount, _mintId);                             // update the user's account
    }

    /**
    * @dev wrapAndDeposit is used for migration, it will wrap old SLP tokens to
    * Stogies & deposit in staking
    */
    function wrapAndDeposit(uint256 _amount, bool _mintId) external {
        require(_amount != 0, "You cannot deposit only 0 tokens"); // Has enough?
        _wrap(msg.sender, address(this), _amount);
        _addStake(msg.sender, _amount, _mintId);                   // update the user's account
    }

    /**
    * @dev _addStake updates how many STOG has been deposited for the user
    * @param _user address of user we are updating the stake for
    */
    function _addStake(
        address _user,
        uint256 _amount,
        bool _mintId
    ) internal {
        UserInfo storage user = farmers[_user];
        user.deposit += _amount;
        user.rewardDebt += _amount * accCigPerShare / 1e12;
        cig.deposit(_amount);                 // forward the SLP to the factory
        emit Deposit(_user, _amount);
        if (_mintId) {
            badges.issueID(_user);           // mint nft
        }
    }

    /** todo test
    * @dev transferStake transfers a stake to a new address
    *   _to must not have any stake. Harvests the stake before transfer
    *   _tokenID optionally, transfer the ID card NFT
    */
    function transferStake(address _to, uint256 _tokenID) external {
        UserInfo storage userFrom = farmers[msg.sender];
        require (userFrom.deposit > 0, "from deposit must not be empty");
        console.log("userFrom.deposit:", userFrom.deposit);
        UserInfo storage userTo = farmers[_to];
        require (userTo.deposit == 0, "userTo.deposit must be empty");
        // harvest, move stake, remove old index, assign new index
        _harvest(userFrom, msg.sender);
        userTo.deposit = userFrom.deposit;
        userTo.rewardDebt = userFrom.rewardDebt;
        emit TransferStake(msg.sender, _to, userFrom.deposit);
        userFrom.deposit = 0;
        userFrom.rewardDebt = 0;
        if (badges.ownerOf(_tokenID) == msg.sender) {
            badges.transferFrom(msg.sender, _to, _tokenID);
        }
    }

    /**
    * @dev withdraw takes out the LP tokens. This will also harvest.
    * @param _amount the amount to withdraw
    * @return harvested amount of CIG harvested
    */
    function withdraw(uint256 _amount) public returns (uint256 harvested) {
        return _withdraw(_amount, msg.sender, msg.sender);
    }

    /**
    * @dev _withdraw harvest from the CIG factory, withdraw on behalf of
    *    _farmer,  and send back the STOG
    */
    function _withdraw(
        uint256 _amount,
        address _farmer,
        address _to
    ) internal returns (uint256 harvested) {
        UserInfo storage user = farmers[_farmer];
        require(user.deposit >= _amount, "no STOG deposited");
        /* update() will harvest CIG for everyone before emergencyWithdraw, this important. */
        fetchCigarettes();                                                  // fetch CIG rewards for everyone
        /*
        Due to a bug in the Cig contract, we can only use emergencyWithdraw().
        This will take out the entire TVL first, subtract the _amount and
        deposit back the remainder. emergencyWithdraw() doesn't return
        the amount of tokens withdrawn, thus we use difference between b0 and
        b1 to work it out.
        */
        (uint256 bal, ) = cig.farmers(address(this));
        cig.emergencyWithdraw();
        uint256 butt = bal - _amount;
        if (butt > 0) {
            cig.deposit(butt);                                     // put the SLP back into the factory, sans _amount
        }
        /* harvest beforehand, so _withdraw can safely decrement their reward count */
        harvested = _harvest(user, _to);                           // distribute the user's reward
        _unstake(user, _amount);                                   // update accounting for withdrawal
        if (_to != address(this)) {
            _transfer(address(this), address(_to), _amount);       // send STOG back
        }
        emit Withdraw(_farmer, _amount);
        return harvested;
    }

    /**
    * @dev Internal withdraw, updates internal accounting after withdrawing LP
    * @param _amount to subtract
    */
    function _unstake(UserInfo storage _user, uint256 _amount) internal {
        require(_user.deposit >= _amount, "Balance is too low");
        _user.deposit -= _amount;
        uint256 _rewardAmount = _amount * accCigPerShare / 1e12;
        _user.rewardDebt -= _rewardAmount;
    }

    /**
    * @dev harvest redeems pending rewards & updates state
    * @return received is the amount that was harvested
    */
    function harvest() public returns (uint256 received) {
        UserInfo storage user = farmers[msg.sender];
        fetchCigarettes();                          // harvest CIG from factory v1
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
        uint256[] memory, // ret
        uint256[] memory, // cigdata
        address,          // theCEO
        bytes32,          // graffiti
        uint112[] memory  // reserves
    ) {
        uint[] memory ret = new uint[](23);
        uint[] memory cigdata;
        address theCEO;
        bytes32 graffiti;
        ILiquidityPool ethusd = ILiquidityPool(address(0xC3D03e4F041Fd4cD388c549Ee2A29a9E5075882f));
    uint112[] memory reserves = new uint112[](2);
        (cigdata, theCEO, graffiti, reserves) = cig.getStats(_user); //  new uint[](27);
        UserInfo memory info = farmers[_user];
        uint256 t = uint256(badges.minters(_user));   // timestamp of id card mint
        ret[0] = info.deposit;                         // how much STOG staked by user
        ret[1] = info.rewardDebt;                      // amount of rewards paid out for user
        (ret[2],) = cig.farmers(address(this));        // contract's STOGE balance
        ret[3] = cigEthSLP.balanceOf(address(this));   // contract CIG/ETH SLP balance
        ret[4] = balanceOf[_user];                     // user's STOG balance
        ret[5] = lastRewardBlock;                      // when rewards were last calculated
        ret[6] = accCigPerShare;                       // accumulated CIG per STOG share
        ret[7] = pendingCig(_user);                    // pending CIG reward to be harvested
        ret[8] = IERC20(weth).balanceOf(_user);        // user's WETH balance
        ret[9] = _user.balance;                        // user's ETH balance
        ret[10] = cig.allowance(_user, address(this)); // user's approval for Stogies to spend their CIG
        ret[11] = cigEthSLP.allowance(
            _user, address(this));                     // user's approval for Stogies to spend CIG/ETH SLP
        ret[12] = IERC20(weth)
        .allowance(_user, address(this));              // user's approval to spend WETH
        ret[13] = totalSupply;                         // total supply of STOG

        (uint112 r7, uint112 r8,) = cigEthSLP.getReserves();   // CIG/ETH SLP reserves, ret[7] is ETH, ret[8] is CIG
        ret[14] = sushiRouter.getAmountOut(
            1 ether, uint(r8), uint(r7));      // How much CIG for 1 ETH (ETH price in CIG)
        (ret[15], ret[16],) = ethusd.getReserves();    // WETH/DAI reserves (15 = DAI, 16 = WETH)
        ret[17] = sushiRouter.getAmountOut(
            1 ether, ret[15], ret[16]);                // ETH price in USD
        ret[18] = r7;                                  // ETH reserve of CIG/ETH
        ret[19] = r8;                                  // CIH reserve of CIG/ETH
        ret[20] = block.timestamp;                     // current timestamp
        ret[21] = cig.balanceOf(address(this));        // CIG in contract
        ret[22] = t;                                   // timestamp of id card mint (damn you stack too deep)
        return (ret, cigdata, theCEO, graffiti, reserves);
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

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(IERC20).interfaceId ||
            interfaceId == type(IERC2612).interfaceId;
    }
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

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

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
    function getStats(address _user) external view returns(uint256[] memory, address, bytes32, uint112[] memory);
    function farmers(address _user) external view returns (uint256 deposit, uint256 rewardDebt);
    //function stakedlpSupply() external view returns(uint256);

    //function withdraw(uint256 _amount) external // bugged, use emergencyWithdraw() instead.
}

interface IIDBadges {
    function balanceOf(address _holder) external view returns (uint256);
    function transferFrom(address,address,uint256) external;
    function issueID(address _to) external;
    function ownerOf(uint256 _id) external view returns (address);
    function minters(address) external view returns(uint64);
}

interface IERC2612 {
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
    function nonces(address owner) external view returns (uint);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}