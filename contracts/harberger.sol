// SPDX-License-Identifier: MIT
// 🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔
// Author: tycoon.eth
// Project: Hamburger Hut
// About: Harberger tax marketplace & protocol for NFTs
// 🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔
pragma solidity ^0.8.17;

import "hardhat/console.sol";

/**

Welcome to BurgerMarket 🍔, a unique NFT marketplace where the NFTs are always for sale!

Say good-bye to royalties!
BurgerMarket provides an alternative revenue model for NFTs, based on Harberger Taxes.

For CryptoPunk owners
====

You can deposit your punk into the contract and that will issue you a NFT that wraps your punk.
This wrapped punk is then called a "Deed" and you become the "Initiator" of the deed.
The twist here is that when you create a wrapped punk, that wrapped punk will be always be for sale, and whoever holds
this wrapped punk will need to pay a tax.

The rate of the tax depends on the price of the NFT. You can change the price at any time while you are holding
this deed. The rate may vary and it's configured by the Initiator when the deed is first created. For example,
the usual rate may be %0.1 per day. So, if your "buy" price is 10 WETH, then it means somebody will need to pay 0.01 ETH
per day to hold the wrapped punk in their wallet.

If someone buys the wrapped punk, a portion of the revenue from the sale will be sent to you, the "Initiator".
This also can be set up so that a portion goes to the previous owner (seller).

Want your punk back? No problem, just take-over the wrapped punk by buying back the deed, then take take it out
after 2 days of holding it.

For .eth name owners
====

Got a cool .eth .eth name, and you want to make some money by renting it out?
Wrap your .eth in the BurgerMarket wrapper, and you may.

People who takeover your .eth name will need to pay a fee that will be distributed to you.
Additionally, when someone else does a takeover of the .eth name, a portion of the revenue from the sale will be sent
to you, the "Initiator". This also can be set up so that a portion goes to the previous owner (seller).

Also, the person who taken over the .eth name will have full control over it - they will be able to set
their own address, content and other records for that name.

Want your .eth back? You can do a takeover any time, then unwrap it.

For ERC721 owners
===

Got a cool NFT that everyone wants to take turns in holding? Wrap it on BurgerMarket.

By wrapping your grail on BurgerMarket, you can let others hold your NFT without having to worry if you'll ever
get it back.

The wrapped version of your NFT

Burger Market Rules:
===

- Deposited tax refunds: If someone does a takeover, any tax deposit you may have will be returned to you.
- You cannot transfer the Deed to any other wallet. The only way to transfer it by buying the deed. (BuyDeed function)
- Unwrapping: The NFT can be taken out by the Initiator, if they also hold the deed.
The Initiator is required to wait 2 days in order to take out the NFT.
This means that the Initiator will need to be a holder of the deed for at least 2 days.
- if the NFT being wrapped as a Deed is an ENS, then reclaim() is called after wrapping. Reclaim will be called again
after un-wrapping. Additionally, the holder of the deed can administer the .eth name as if they own it. This means
they can set the ENS records, such as the address, content hash, text records and so on.
- You cannot buy a deed from yourself
- When paying tax, the revenue is split to the initiator and any remaining revenue is burned. It can be configured
so that all revenue goes to the initiator.
- When paying tax for a deed which you are also the "initiator", the revenue from consuming the tax is burned rather
than split with you. This is to encourage you to sell the deed. Otherwise, if the tax went to you, then you'd be
just paying yourself, which would not make any sense.
- When buying a deed, the revenue from the sale can be split with the initiator and seller, according to a percentage.
- The percentage that the revenue is split can only be configured once by the initiator once, during deed creation.
- You can only pay tax from the holder's account, nobody else can pay tax for you.

todo: finish rules comment

*/

contract Harberger {

    /**
     * Enums 🍔
     */

    enum State {
        New,     // initial
        OnSale,  // Deed can be bought
        Auction, // owner default on tax and deed is sold off under a dutch auction
        TakenOut // NFT was taken out from the deed
    }

    /**
     * Structs 🍔
     */

    struct Deed {
        uint256 nftTokenID; // the token id of the NFT that is wrapped in this deed
        uint256 price;      // takeover price in 'priceToken'
        uint256 taxBalance; // amount of tax pre-paid
        bytes32 graffiti;   // a 32 character graffiti set when buying a deed
        address initiator;  // address of the creator of the deed
        address holder;     // address of current holder and tax payer
        address nftContract;// address of the NFT that is wrapped in this deed
        IERC20 priceToken;  // address of the payment token
        uint64 taxBurnBlock;// block number when tax was last burned
        uint64 blockStamp;  // block number when NFT transferred owners
        uint32 index;       // stores the index for deed enumeration
        uint16 [2] rates;   // a number between 1 and 1000, eg 1 represents 0.1%, 11 = %1.1 333 = 33.3
                            // rate[0] is the tax %, rate[1] is the share to split on each sale
        State state;        // what state the deed is in, described above
    }

    /**
     * Storage 🍔
     */

    mapping(uint256 => Deed) public deeds;                              // a deed is also an NFT
    uint256 public deedHeight;                                          // highest deedID
    mapping(address => uint256) private balances;                       // counts of ownership
    mapping(address => mapping(uint256 => uint256)) private ownedDeeds; // track enumeration
    mapping(uint256 => string) public names;                            // .eth names wrapped in the deeds
    uint8 internal locked = 1;                                          // reentrancy guard. 2 = entered, 1 not

    /**
     * Constants - initialized at deployment 🍔
     */

    uint256 private immutable epochBlocks;           // secs per day divided by 12 (86400 / 12), assuming 12 sec blocks
    uint256 private immutable auctionBlocks;         // 3600 blocks
    ICigtoken private immutable cig;                 // 0xCB56b52316041A62B6b5D0583DcE4A8AE7a3C629
    IENSRegistrar private immutable dotEthReg;       // 0x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85
    IENSResolver private immutable dotEthRes;        // 0x4976fb03C32e5B8cfe2b6cCB31c09Ba78EBaBa41
    ICryptoPunks private immutable punks;            // 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB
    ICryptoPunksTokenURI private immutable punksURI; // 0xd8e916c3016be144eb2907778cf972c4b01645fc
    address public constant BURN_ADDR = address(0);

    /**
     * Constants - hard-coded 🍔
     */

    uint private constant SCALE = 1e3;
    bytes4 private constant RECEIVED = 0x150b7a02; // bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))
    uint256 private constant MIN_PRICE = 1e12;     // 0.000001

    /**
     * Modifiers 🍔
     */

    modifier notReentrant() { // notReentrant is a reentrancy guard
        require(locked == 1, "already entered");
        locked = 2; // enter
        _;
        locked = 1; // exit
    }

    /**
     * Events 🍔
     */

    // NewDeed is fired when a new deed is created
    event NewDeed(uint256 indexed deedID, address indexed user);
    // Takeover is fired when a deed is bought and ownership is transferred
    event Takeover(uint256 indexed deedID, address indexed user, uint256 new_price, bytes32 graffiti);
    // TaxDeposit
    event TaxDeposit(uint256 indexed deedID, address indexed user, uint256 amount);     // when tax is deposited
    // RevenueSplit when tax revenue is paid out and split between owner and initiator
    event RevenueSplit(
        uint256 indexed deedID,
        address indexed user,
        uint256 amount,
        uint16 split,
        address indexed initiator);
    // Defaulted when owner defaulted on tax
    event Defaulted(uint256 indexed deedID, address indexed called_by, uint256 reward);
    // PriceChange // when owner changed price
    event PriceChange(uint256 indexed deedID, uint256 price);
    // Takeout when NFT taken out from deed
    event Takeout(uint256 indexed deedID, address indexed user);

    /**
    * @dev Construct the Hamburger Hut 🍔
    * @param _epochBlocks - how many blocks is 1 epoch
    * @param _auctionBlocks - how many blocks for each dutch auction discount
    * @param _cig - cigarette token address
    * @param _ensReg - ENS .eth registry address (an ERC721)
    * @param _ensRes - EMS .eth resolver address
    * @param _punks - CryptoPunks contract address
    * @param _punksURI - CryptoPunks URI info contract
    */
    constructor(
        uint256 _epochBlocks,   // 7200, secs per day divided by 12 (86400 / 12), assuming 12 sec blocks
        uint256 _auctionBlocks, // 3600 blocks, every 12 hours, assuming 12 sec blocks
        address _cig,           // 0xCB56b52316041A62B6b5D0583DcE4A8AE7a3C629
        address _ensReg,        // 0x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85 (BaseRegistrarImplementation - ERC721)
        address _ensRes,        // 0x4976fb03C32e5B8cfe2b6cCB31c09Ba78EBaBa41
        address _punks,         // 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB
        address _punksURI       // 0xd8e916c3016be144eb2907778cf972c4b01645fc
    ){
        epochBlocks = _epochBlocks;
        auctionBlocks = _auctionBlocks;
        cig = ICigtoken(_cig);
        dotEthReg = IENSRegistrar(_ensReg);
        dotEthRes = IENSResolver(_ensRes);
        punks = ICryptoPunks(_punks);
        punksURI = ICryptoPunksTokenURI(_punksURI);
    }

    /**
    * @dev create a new Deed by wrapping an NFT, putting it under a Harberger tax system
    *   A new Deed token will be issued with the next available id.
    * @param _nftContract address of the nft to wrap, can be an ERC721 or a punk
    * @param _tokenID the token id from the _nftContract address
    * @param _price initial price, in '_priceToken'
    * @param _tax_amount amount of tax to pre-pay
    * @param _priceToken address of the ERC20 to use as the payment token
    * @param _taxRate a number between 1 and 1000, eg 1 represents 0.1%, 11 = %1.1 333 = 33.3
    * @param _shareRate of revenue that goes to initiator, remainder is burned. The type is same as _taxRate
    * @param _ensName .eth name, required if nft is an ENS .eth (without the .eth suffix, normalized)
    */
    function newDeed(
            address _nftContract,
            uint256 _tokenID,
            uint256 _price,
            uint256 _tax_amount,
            address _priceToken,
            uint16 _taxRate,
            uint16 _shareRate,
            string calldata _ensName
    ) external notReentrant returns (uint256 deedID) {
        require(_shareRate > 0, "tax rate cannot be 0");
        require(_taxRate > 0, "tax rate cannot be 0");
        require(_price > MIN_PRICE, "price cannot be < 0.000001");
        unchecked{deedID = ++deedHeight;}                                                 // starts from 1
        Deed storage d = deeds[deedID];
        d.initiator = msg.sender;
        d.nftContract = _nftContract;
        d.nftTokenID = _tokenID;
        d.priceToken = IERC20(_priceToken);
        d.price = _price;
        d.rates[0] = _taxRate;
        d.rates[1] = _shareRate;
        d.state = State.OnSale;
        if (d.nftContract == address(punks)) {                                            // if it's a punk
            punks.buyPunk(_tokenID);                                                      // wrap the punk
        } else {
            IERC721(d.nftContract).safeTransferFrom(msg.sender, address(this), _tokenID); // wrap the nft
            if (d.nftContract == address(dotEthReg)) {                                    // if it's a .eth name
                require (node(_ensName) == bytes32(_tokenID), 'invalid .eth name');
                names[deedID] = _ensName;
                dotEthReg.reclaim(_tokenID, address(this));                               // become the controller
            }
        }
        if (_tax_amount > 0) {
            safeERC20TransferFrom(d.priceToken, msg.sender, address(this), _tax_amount);  // take tax deposit
            d.taxBalance = _tax_amount;                                                   // record tax deposit
        }
        _mint(msg.sender, deedID);                                                        // mint a deed as an ERC721
        emit NewDeed(deedID, msg.sender);
        return deedID;
    }

    /**
    * @dev buyDeed buys the deed and transfers it to the new holder.
    * @param _deedID the deed id
    * @param _max_spend in wei. Since d.price can change after signing the tx,
    *   this can protect the buyer in  case the the d.price gets set to a high
    *   value
    * @param _new_price the new takeover price
    * @param _tax_amount amount token to deposit for paying tax
    * @param _graffiti a graffiti message can be set to anything
    * @param _to address of the ultimate holder of the deed once the title has
    *   been purchased. (`msg.sender` can buy deeds for `_to`)
    */
    function buyDeed(
        uint256 _deedID,
        uint256 _max_spend,
        uint256 _new_price,
        uint256 _tax_amount,
        bytes32 _graffiti,
        address _to
    ) external notReentrant {
        Deed memory d = deeds[_deedID];
        require (d.initiator != address(0), "no such deed");
        if (d.state == State.OnSale && (d.taxBurnBlock != uint64(block.number))) {
            d.state = _consumeTax(
                _deedID,
                d.price,
                d.rates[0],
                d.rates[1],
                d.taxBurnBlock,
                d.taxBalance,
                d.holder,
                d.initiator,
                d.priceToken
            );                                                             // _consumeTax can change d.state to 2
            deeds[_deedID].taxBurnBlock = uint64(block.number);            // store the block number of last burn
        }
        if (d.state == State.Auction) {
            // Auction state. The price goes down 10% every `CEO_auction_blocks` blocks
            d.price = _calcDiscount(d.price, d.taxBurnBlock);
            d.holder = address(this);                                      // contract takes ownership during auction
        }
        require (_max_spend >= d.price + _tax_amount , "overpaid");        // prevent from over-payment
        require (_new_price >= MIN_PRICE, "price 2 smol");                 // price cannot be under 0.000001
        require (_tax_amount >= _new_price / 1000, "insufficient tax" );   // at least %0.1 fee paid for 1 epoch
        require (msg.sender != d.holder, "you already own it");            // cannot buy from yourself
        require (_to != d.holder, "_to already owns it");                  // cannot buy for someone who owns it
        safeERC20TransferFrom(
            d.priceToken, msg.sender, address(this), d.price + _tax_amount
        );                                                                 // pay for the deed + deposit tax
        _splitRevenue(
            d.priceToken,
            d.price,
            d.rates[1],
            d.initiator,
            d.holder
        );                                                                  // split the revenue from the sale
        emit RevenueSplit(_deedID, msg.sender, d.price, d.rates[1], d.initiator);
        if (d.taxBalance > 0) {
            safeERC20Transfer(d.priceToken, d.holder, d.taxBalance);        // return deposited tax back to old holder
            // deeds[_deedID].taxBalance                                    // not needed, will be overwritten
        }
        deeds[_deedID].taxBalance = _tax_amount;                            // store the tax deposit amount
        console.log("! msg.sender bal:", balanceOf(msg.sender));
        console.log("! holder bal:", balanceOf(d.holder));
        console.log("! contract bal:", balanceOf(address(this)));
        console.log("! state:", uint(d.state));
        console.log("transfer,", d.holder, " to: ", _to);
        _transfer(d.holder, _to, _deedID);                                  // transfer deed to buyer
        deeds[_deedID].price = _new_price;                                  // set the new price
        deeds[_deedID].blockStamp = uint64(block.number);                   // record the block of state change
        deeds[_deedID].state = State.OnSale;                                // make available for sale
        deeds[_deedID].graffiti = _graffiti;                                // save the graffiti
        emit TaxDeposit(_deedID, _to, _tax_amount);
        emit Takeover(_deedID, _to, _new_price, _graffiti);
    }

    /**
    * @dev depositTax pre-pays tax for the existing holder.
    * It may also burn any tax debt the holder may have.
    * @param _amount amount of tax to pre-pay
    */
    function depositTax(uint256 _deedID, uint256 _amount) notReentrant external {
        Deed memory d = deeds[_deedID];
        require (d.state == State.OnSale, "not active");
        require (d.holder == msg.sender, "only holdoor");
        if (_amount > 0) {
            safeERC20TransferFrom(d.priceToken, msg.sender, address(this), _amount); // place the tax on deposit
            d.taxBalance += _amount;
            deeds[_deedID].taxBalance = d.taxBalance;                                // record the deposit balance
            emit TaxDeposit(_deedID, msg.sender, _amount);
        }
        if (d.taxBurnBlock != uint64(block.number)) {
            _consumeTax(
                _deedID,
                d.price,
                d.rates[0],
                d.rates[1],
                d.taxBurnBlock,
                d.taxBalance,
                d.holder,
                d.initiator,
                d.priceToken);                                                       // settle any tax debt
            deeds[_deedID].taxBurnBlock = uint64(block.number);
        }
    }

    /**
    * @dev consumeTax is called to consume tax.
    * It removes the holder if tax is unpaid.
    * 1. deduct tax, update last update
    * 2. if not enough tax, remove & begin auction
    * 3. reward the caller by minting a reward from the amount indebted
    * A Dutch auction begins where the price decreases 10% every hour.
    */

    function consumeTax(uint256 _deedID) notReentrant external  {
        Deed memory d = deeds[_deedID];
        require (d.state == State.OnSale, "deed not active");
        if (d.taxBurnBlock == uint64(block.number)) return;
        _consumeTax(
            _deedID,
            d.price,
            d.rates[1],
            d.rates[0],
            d.taxBurnBlock,
            d.taxBalance,
            d.holder,
            d.initiator,
            d.priceToken);
        deeds[_deedID].taxBurnBlock = uint64(block.number);
    }

    /**
     * @dev setPrice changes the price for the holder title.
     * @param _price the price to be paid. The new price most be larger tan MIN_PRICE and not default on debt
     * @return state State
     */
    function setPrice(uint256 _deedID, uint256 _price) external notReentrant returns (State state) {
        Deed memory d = deeds[_deedID];
        require (d.holder == msg.sender, "only holdoor");
        require (d.state == State.OnSale, "deed not active");
        require (_price >= MIN_PRICE, "price 2 smol");
        require (d.taxBalance >= _price / SCALE * d.rates[0], "price would default"); // need at least tax for 1 epoch
        if (block.number != d.taxBurnBlock) {
            state = _consumeTax(
                _deedID,
                d.price,
                d.rates[0],
                d.rates[1],
                d.taxBurnBlock,
                d.taxBalance,
                d.holder,
                d.initiator,
                d.priceToken);
            deeds[_deedID].taxBurnBlock = uint64(block.number);
        }
        // The state is not OnSale if owner defaulted on tax
        if (state == State.OnSale) {
            deeds[_deedID].price = _price;                                            // set the new price
            emit PriceChange(_deedID, _price);
        }
        return state;
    }

    /**
    * @dev takeout allows the deed's initiator to unwrap and remove the nft
    */
    function takeout(uint256 _deedID) external notReentrant returns (State state) {
        Deed memory d = deeds[_deedID];
        require (d.holder == msg.sender, "only holdoor");
        require (d.state == State.OnSale, "deed not active");
        require (d.blockStamp + (epochBlocks*2) >= block.number, "must wait 2 epochs");
        require (d.initiator == msg.sender, "only initinatoor");
        if (d.taxBurnBlock == uint64(block.number)) return d.state;
        state = _consumeTax(
            _deedID,
            d.price,
            d.rates[0],
            d.rates[1],
            d.taxBurnBlock,
            d.taxBalance,
            d.holder,
            d.initiator,
            d.priceToken);
        if (state != State.OnSale) { // defaulted on tax?
            return state;
        }
        deeds[_deedID].state = State.TakenOut;
        deeds[_deedID].taxBurnBlock = uint64(block.number);
        if (d.nftContract == address(punks)) {                               // if punk
            punks.offerPunkForSaleToAddress(d.nftTokenID, 0, msg.sender);    // allow initiator to take it out
        } else {
            if (d.nftContract == address(dotEthReg)) {                       // if ENS
                dotEthReg.reclaim(d.nftTokenID, msg.sender);                 // relinquish the controller
            }
            IERC721(d.nftContract).safeTransferFrom(
                address(this),
                msg.sender,
                d.nftTokenID
            );                                                                // send back the NFT
            delete names[_deedID];
        }
        if (d.taxBalance > 0) {
            safeERC20Transfer(d.priceToken, d.holder, d.taxBalance);          // return deposited tax back to old holder
            deeds[_deedID].taxBalance = 0;                                    // not needed, will be overwritten
        }
        _transfer(d.holder, address(0), _deedID);                             // burn the deed
        emit Takeout(d.nftTokenID, msg.sender);
        return State.TakenOut;
    }

    /**
    * @dev _consumeTax distributes any tax debt. Boots the owner if defaulted, assuming called
    *    assuming that the deed's state is State.OnSale
    * @return State state.Auction if defaulted
    */
    function _consumeTax(
        uint256 _deedID,
        uint256 _price,
        uint16 _taxRate,
        uint16 _split,
        uint64 _taxBurnBlock,
        uint256 _taxBalance,
        address _holder,
        address _initiator,
        IERC20 _token
    ) internal returns(State /*state*/) {
        State s = State.OnSale;                                 // assume it's on sale
        uint256 tpb = _price / SCALE * _taxRate / epochBlocks;  // calculate tax-per-block
        uint256 debt = (block.number - _taxBurnBlock) * tpb;
        if (_taxBalance !=0 && _taxBalance >= debt) {           // Does holder have enough deposit to pay debt?
            deeds[_deedID].taxBalance = _taxBalance - debt;     // update tax balance
        } else {
            // Holder defaulted
            s = State.Auction;                                  // initiate a Dutch auction.
            debt = _taxBalance;                                 // debt exceeds _taxBalance, it's all we can pay
            deeds[_deedID].state = s;                           // save to Auction state
            deeds[_deedID].taxBalance = 0;                      // update the tax balance
            _transfer(_holder, address(this), _deedID);         // Strip the deed from the holder
            emit Defaulted(_deedID, msg.sender, _taxBalance);
        }
        _splitRevenue(
            _token,
            debt,
            _split,
            _initiator,
            BURN_ADDR                                           // holder's portion burned
        );                                                      // distribute only to _initiator (burn _holder's)
        emit RevenueSplit(
            _deedID,
            msg.sender,
            debt,
            _split,
            _initiator
        );
        return s;
    }

    /**
    * @dev _calcDiscount calculates the discount for the holder title based on how many blocks passed
    */
    function _calcDiscount(uint256 _price, uint64 _taxBurnBlock) internal view returns (uint256) {
    unchecked {
        uint256 d = (_price / 10)           // 10% discount
        // multiply by the number of discounts accrued
        * (block.number - _taxBurnBlock) / auctionBlocks;
        if (d > _price) {
            // overflow assumed, reset to MIN_PRICE
            return MIN_PRICE;
        }
        uint256 price = _price - d;
        if (price < MIN_PRICE) {
            price = MIN_PRICE;
        }
        return price;
    }
    }

    /**
    * @return _ret - array of uin256 with state info
    * @return deed - deed state selected by _deedID
    * @return symbol - ERC20 symbol of deed.
    */
    function getInfo(address _user, uint256 _deedID) view public returns (
        uint256[] memory,                                                     // ret
        Deed memory deed,
        string memory symbol,
        string memory nftName,
        string memory nftSymbol,
        string memory nftTokenURI
    ) {
        uint[] memory ret = new uint[](12);
        deed = deeds[_deedID];
        ret[0] = 0; // todo empty, add some value here
        ret[1] = epochBlocks;
        ret[2] = auctionBlocks;
        ret[3] = cig.balanceOf(_user);
        ret[4] = cig.allowance(_user, address(this));
        if (deed.state != State.New) {
            ret[5] = IERC20(deed.priceToken).balanceOf(_user);
            ret[6] = IERC20(deed.priceToken).allowance(_user, address(this));
        }
        ret[7] = deedHeight;
        ret[8] = balanceOf(_user);                                            // deed balance
        ret[9] = cig.taxBurnBlock();
        ret[10] = cig.CEO_price();
        if (deed.state != State.New) {
            ret[11] = uint256(IERC20(deed.priceToken).decimals());
            symbol = IERC20(deed.priceToken).symbol();
            if (deed.nftContract == address(punks)) {
                nftName = "CryptoPunks";
                nftSymbol =  unicode"Ͼ";
            } else if (deed.nftContract == address(dotEthReg)) {
                nftName = names[_deedID];                                     // the .eth name
                nftSymbol = "";
            } else if (IERC721(deed.nftContract).supportsInterface(type(IERC721Metadata).interfaceId)) {
                nftName = IERC721(deed.nftContract).name();
                nftSymbol = IERC721(deed.nftContract).symbol();
            }
            nftTokenURI = tokenURI(_deedID);
            if (deed.state == State.Auction) {
                deed.price = _calcDiscount(deed.price, deed.taxBurnBlock);
            }
        }
        return (ret, deed, symbol, nftName, nftSymbol, nftTokenURI);
    }

    /**
    * @dev distribute revenue
    * @param _token The token to distribute
    * @param _amount The amount to distribute
    * @param _split The % to send to initiator
    * @param _initiator address to send the revenue split
    * @param _holder send remainder to here. (May be 0x0 to burn it)
    */
    function _splitRevenue(
        IERC20 _token,
        uint256 _amount,
        uint16 _split,
        address _initiator,
        address _holder
    ) internal {

        if (_split == 1000) {
            safeERC20Transfer(_token, _initiator, _amount);           // distribute all
        } else if (_split > 0) {
            uint256 distribute = _amount / SCALE * _split;
            safeERC20Transfer(_token, _initiator, distribute);        // distribute portion
            safeERC20Transfer(_token, _holder, _amount - distribute); // send remainder _holder (or to BURN_ADDR)
        } else if (_split == 0) {
            safeERC20Transfer(_token, _holder, _amount);              // send all to _holder (may be BURN_ADDR)
        }

    }

    function safeERC20Transfer(IERC20 _token, address _to, uint256 _amount) internal {
        bytes memory payload = abi.encodeWithSelector(_token.transfer.selector, _to, _amount);
        (bool success, bytes memory returndata) = address(_token).call(payload);
        require(success, "safeERC20Transfer failed");
        if (returndata.length > 0) { // check return value if it was returned
            require(abi.decode(returndata, (bool)), "safeERC20Transfer failed");
        }
    }

    function safeERC20TransferFrom(IERC20 _token, address _from, address _to, uint256 _amount) internal {
        bytes memory payload = abi.encodeWithSelector(_token.transferFrom.selector, _from, _to, _amount);
        (bool success, bytes memory returndata) = address(_token).call(payload);
        require(success, "safeERC20TransferFrom failed");
        if (returndata.length > 0) { // check return value if it was returned
            require(abi.decode(returndata, (bool)), "safeERC20TransferFrom failed");
        }
    }

    /***
    * ENS Hamburgers 🍔
    * Proxy functions for ENS .eth names 🍔
    */

    bytes32 public constant ADDR_DOT_ETH_NODE = 0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae;

    function node(string memory _n) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(ADDR_DOT_ETH_NODE, keccak256(abi.encodePacked(_n))));
    }

    /**
    * @dev getENSInfo
    */
    function getENSInfo(
        bytes32 _node,
        uint _coinType,
        bytes32 _DNSName,
        uint16 _DNSResource,
        string[6] calldata _keys
    ) view public returns (
        address addr,
        bytes memory coinAddr,
        bytes memory contentHash,
        bytes memory DNSRecord,
        string memory name,
        bytes32 x, bytes32 y,
        string[6] memory text
    ) {
        addr = dotEthRes.addr(_node);
        if (_coinType > 0) {
            coinAddr = dotEthRes.addr(_node, _coinType);
        }
        contentHash = dotEthRes.contenthash(_node);
        if (_DNSName != 0x0) {
            DNSRecord = dotEthRes.dnsRecord(_node, _DNSName, _DNSResource);
        }
        name = dotEthRes.name(_node);
        (x, y) = dotEthRes.pubkey(_node);
        for(uint i = 0; i < 6; i++) {
            text[i] = dotEthRes.text(_node, _keys[i]);
        }
        return (addr, coinAddr, contentHash, DNSRecord, name, x, y, text);
    }

    /**
    * @dev setENSInfo only holder of a deed that is State.OnSale can use
    */
    function setENSInfo(
        uint256 _deedID,
        address _addr,
        uint _coinType,
        bytes memory _coinAddr,
        bytes memory _contentHash,
        bytes memory _DNSRecord,
        string memory _name,
        bytes32 _x, bytes32 _y,
        string[6] calldata _keys,
        string[6] calldata _values
    ) external {
        Deed memory deed = deeds[_deedID];
        require (deed.holder == msg.sender, "only holder of deed");
        require (deed.state == State.OnSale, "deed must be on sale");
        require (deed.nftContract == address(dotEthReg), "not .eth reg");
        bytes32 node = bytes32(deed.nftTokenID);
        dotEthRes.setAddr(node, _addr);
        if (_coinType > 0) {
            dotEthRes.setAddr(node, _coinType, _coinAddr);
        }
        if (_contentHash.length > 0) {
            dotEthRes.setContenthash(node, _contentHash);
        }
        if (_DNSRecord.length > 0) {
            dotEthRes.setDNSRecords(node, _DNSRecord);
        }
        if (bytes(_name).length > 0) {
            dotEthRes.setName(node, _name);
        }
        if (_x > 0x0) {
            dotEthRes.setPubkey(node, _x, _y);
        }
        for(uint i = 0; i < 6; i++) {
            dotEthRes.setText(node, _keys[i], _values[i]);
        }
    }


    /***
    * ERC721 Hamburgers 🍔
    */

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    //event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId); // not needed
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /// @notice Count NFTs tracked by this contract
    /// @return A count of valid NFTs tracked by this contract, where each one of
    ///  them has an assigned and queryable owner not equal to the zero address
    function totalSupply() external view returns (uint256) {
        return deedHeight;
    }

    /// @notice Enumerate valid NFTs
    /// @dev Throws if `_index` >= `totalSupply()`.
    /// @param _index A counter less than `totalSupply()`
    /// @return The token identifier for the `_index`th NFT,
    ///  (sort order not specified)
    function tokenByIndex(uint256 _index) external view returns (uint256) {
        require (_index < deedHeight, "index out of range");
        return ++_index; // index starts from 0
    }

    /// @notice Enumerate NFTs assigned to an owner
    /// @dev Throws if `_index` >= `balanceOf(_owner)` or if
    ///  `_owner` is the zero address, representing invalid NFTs.
    /// @param _owner An address where we are interested in NFTs owned by them
    /// @param _index A counter less than `balanceOf(_owner)`
    /// @return The token identifier for the `_index`th NFT assigned to `_owner`,
    ///   (sort order not specified)
    function tokenOfOwnerByIndex(address _owner, uint256 _index) external view returns (uint256) {
        require (_index < balances[_owner], "index out of range");
        require (_owner != address(0), "invalid _owner");
        return ownedDeeds[_owner][_index];
    }

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address _holder) public view returns (uint256) {
        require (_holder != address(0));
        return balances[_holder];
    }

    function name() public pure returns (string memory) {
        return "Burger NFT Market";
    }

    function symbol() public pure returns (string memory) {
        return "BURGER";
    }

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 _tokenId) public view returns (string memory) {
        require (_tokenId > 0 && _tokenId < deedHeight+1, "index out of range");
        Deed storage d = deeds[_tokenId];
        if (d.nftContract == address(punks)) {
            return punksURI.tokenURI(_tokenId);
        }
        if (d.nftContract == address(dotEthReg)) {
            //ens names do not have tokenURI, see https://metadata.ens.domains/docs
            return string(
            abi.encodePacked('https://metadata.ens.domains/mainnet/0x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85/',
            _tokenId
            ));
        }
        return IERC721Metadata(d.nftContract).tokenURI(d.nftTokenID);
    }

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 _tokenId) public view returns (address) {
        require (_tokenId > 0 && _tokenId < deedHeight+1, "index out of range");
        Deed storage d = deeds[_tokenId];
        address holder = d.holder;
        require (holder != address(0), "not minted.");
        return holder;
    }

    /**
    * @dev Throws unless `msg.sender` is the current owner, an authorized
    *  operator, or the approved address for this NFT. Throws if `_from` is
    *  not the current owner. Throws if `_to` is the zero address. Throws if
    *  `_tokenId` is not a valid NFT.
    * @param _from The current owner of the NFT
    * @param _to The new owner
    * @param _tokenId The NFT to transfer
    */
    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes memory _data) external  {
        require(msg.sender == address(this), "not allowed"); // transfer can only be made with buyDeed
    }

    /**
    * @dev Throws unless `msg.sender` is the current owner, an authorized
    *  operator, or the approved address for this NFT. Throws if `_from` is
    *  not the current owner. Throws if `_to` is the zero address. Throws if
    *  `_tokenId` is not a valid NFT.
    * @param _from The current owner of the NFT
    * @param _to The new owner
    * @param _tokenId The NFT to transfer
    */
    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external  {
        require(msg.sender == address(this), "not allowed"); // transfer can only be made with buyDeed
    }

    function transferFrom(address _from, address _to, uint256 _tokenId) external  {
        require(msg.sender == address(this), "not allowed"); // transfer can only be made with buyDeed
    }

    /**
    * @notice The only way to transfer ownership is via the buyNFT function
    * @dev Approvals are not supported by this contract
    * @param _to The new approved NFT controller
    * @param _tokenId The NFT to approve
    */
    function approve(address _to, uint256 _tokenId) external {
        require (msg.sender == address(this), "approvals disabled");
    }
    /**
    * @notice The only way to transfer ownership is via the buyNFT function
    * @dev Approvals are not supported by this contract
    * @param _operator Address to add to the set of authorized operators
    * @param _approved True if the operator is approved, false to revoke approval
    */
    function setApprovalForAll(address _operator, bool _approved) external {
        require (msg.sender == address(this), "approvals disabled");
    }

    /**
    * @notice The approvals feature is not supported by this contract
    * @dev Throws if `_tokenId` is not a valid NFT.
    * @param _tokenId The NFT to find the approved address for
    * @return Will always return address(this)
    */
    function getApproved(uint256 _tokenId) public view returns (address) {
        require (_tokenId > 0 &&  _tokenId < deedHeight+1, "index out of range");
        return address(this);
    }

    /**
    * @notice The approvals feature is not supported by this contract
    * @param _owner The address that owns the NFTs
    * @param _operator The address that acts on behalf of the owner
    * @return Will always return false
    */
    function isApprovedForAll(address _owner, address _operator) public pure returns (bool) {
        return false;
    }

    /**
    * @notice Query if a contract implements an interface
    * @param interfaceId The interface identifier, as specified in ERC-165
    * @dev Interface identification is specified in ERC-165. This function
    *  uses less than 30,000 gas.
    * @return `true` if the contract implements `interfaceID` and
    *  `interfaceID` is not 0xffffffff, `false` otherwise
    */
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return
        interfaceId == type(IERC721).interfaceId ||
        interfaceId == type(IERC721Metadata).interfaceId ||
        interfaceId == type(IERC165).interfaceId ||
        interfaceId == type(IERC721Enumerable).interfaceId ||
        interfaceId == type(IERC721TokenReceiver).interfaceId;
    }

    /**
    * @dev transfer a token from _from to _to, always assuming that _to != _from
    * @param _from from
    * @param _to to
    * @param _tokenId the token index
    */
    function _transfer(address _from, address _to, uint256 _tokenId) internal {
        balances[_to]++;
        balances[_from]--;
        deeds[_tokenId].holder = _to;
        removeEnumeration(_from, _tokenId);
        addEnumeration(_to, _tokenId);
        emit Transfer(_from, _to, _tokenId);
    }

    /**
    * @dev _mint mints a new deed
    * @param _to address to mint to
    * @param _tokenId to mint
    */
    function _mint(address _to, uint256 _tokenId) internal {
        balances[_to]++;
        deeds[_tokenId].holder = _to;
        addEnumeration(_to, _tokenId);
        emit Transfer(address(0), _to, _tokenId);
    }

    /**
    * @dev called after an erc721 token transfer, after the counts have been updated
    */
    function addEnumeration(address _to, uint256 _tokenId) internal {
        uint256 last = balances[_to]-1;           // the index of the last position
        ownedDeeds[_to][last] = _tokenId;         // add a new entry
        deeds[_tokenId].index = uint32(last);

    }
    function removeEnumeration(address _from, uint256 _tokenId) internal {
        uint256 height = balances[_from];         // last index
        uint256 i = deeds[_tokenId].index;        // index
        if (i != height) {
            // If not last, move the last token to the slot of the token to be deleted
            uint256 lastTokenId = ownedDeeds[_from][height];
            ownedDeeds[_from][i] = lastTokenId;   // move the last token to the slot of the to-delete token
            deeds[lastTokenId].index = uint32(i); // update the moved token's index
        }
        deeds[_tokenId].index = 0;                // delete from index
        delete ownedDeeds[_from][height];         // delete last slot
    }

    // we do not allow NFTs to be send to this contract, except internally
    function onERC721Received(address /*_operator*/, address /*_from*/, uint256 /*_tokenId*/, bytes memory /*_data*/) external view returns (bytes4) {
        if (msg.sender == address(this)) {
            return RECEIVED;
        }
        revert("nope");
    }

}

/**
 * Interfaces 🍔
 */

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
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 */
interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/**
 * @title ERC-721 Non-Fungible Token Standard, optional metadata extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721Metadata  {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

interface IERC721TokenReceiver {
    function onERC721Received(address _operator, address _from, uint256 _tokenId, bytes memory _data) external returns (bytes4);
}

/// @title ERC-721 Non-Fungible Token Standard, optional enumeration extension
/// @dev See https://eips.ethereum.org/EIPS/eip-721
///  Note: the ERC-165 identifier for this interface is 0x780e9d63.
interface IERC721Enumerable {
    function totalSupply() external view returns (uint256);
    function tokenByIndex(uint256 _index) external view returns (uint256);
    function tokenOfOwnerByIndex(address _owner, uint256 _index) external view returns (uint256);
}
/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721 is IERC165, IERC721Metadata, IERC721Enumerable, IERC721TokenReceiver {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
    function approve(address to, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function setApprovalForAll(address operator, bool _approved) external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;
}

/**
 * @title ERC721 token receiver interface
 * @dev Interface for any contract that wants to support safeTransfers
 * from ERC721 asset contracts.
 */
interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

// ENS 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e
interface IENS {
    function setApprovalForAll(address operator, bool approved) external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    /* node is the namehash of tld */
    function owner(bytes32 node) external view returns (address); // eg. namehash for .eth is: 0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae will return 0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85 which is the .eth registrar
    function resolver(bytes32 node) external view returns (address); // for the .eth namehash it returns 0x30200E0cb040F38E474E53EF437c95A1bE723b2B
    function setRecord(bytes32 node, address owner, address resolver, uint64 ttl) external;
    function setSubnodeRecord(bytes32 node, bytes32 label, address owner, address resolver, uint64 ttl) external;
    function setSubnodeOwner(bytes32 node, bytes32 label, address owner) external returns(bytes32);
    function setResolver(bytes32 node, address resolver) external;
    function setOwner(bytes32 node, address owner) external;
    function setTTL(bytes32 node, uint64 ttl) external;
    function ttl(bytes32 node) external view returns (uint64);
    function recordExists(bytes32 node) external view returns (bool);
}

// Registrar (where domains are NFTs) 0x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85
// https://docs.ens.domains/contract-api-reference/.eth-permanent-registrar
interface IENSRegistrar is IERC721 {
    function controllers(address) external returns(bool);
    function reclaim(uint256 id, address owner) external;
    function nameExpires(uint256 id) external view returns(uint);
    function addController(address controller) external;
    function removeController(address controller) external;
    function setResolver(address resolver) external;
    function available(uint256 id) external view returns(bool);
    function renew(uint256 id, uint duration) external returns(uint);
}


// Public resolver 0x4976fb03C32e5B8cfe2b6cCB31c09Ba78EBaBa41
interface IENSResolver {
    /*
    * AddrResolver
    */
    function addr(bytes32 node) external view returns (address);
    function setAddr(bytes32 node, address a) external;
    function setAddr(bytes32 node, uint coinType, bytes memory a) external;
    function addr(bytes32 node, uint coinType) external view returns(bytes memory);

    /**
    * ContentHashResolver
    */
    function setContenthash(bytes32 node, bytes calldata hash) external;
    function contenthash(bytes32 node) external view returns (bytes memory);
    /*
    * DNSResolver
    */
    function setDNSRecords(bytes32 node, bytes calldata data) external;
    function dnsRecord(bytes32 node, bytes32 name, uint16 resource) external view returns (bytes memory);
    function hasDNSRecords(bytes32 node, bytes32 name) external view returns (bool);
    function clearDNSZone(bytes32 node) external;
    /*
    * NameResolver
    */
    function setName(bytes32 node, string calldata name) external;
    function name(bytes32 node) external view returns (string memory);
    /*
    * PubkeyResolver
    */
    function setPubkey(bytes32 node, bytes32 x, bytes32 y) external;
    function pubkey(bytes32 node) external view returns (bytes32 x, bytes32 y);
    /*
    * TextResolver
    */
    function setText(bytes32 node, string calldata key, string calldata value) external;
    function text(bytes32 node, string calldata key) external view returns (string memory);
}

interface IENSReverseRegistrar { // 0x084b1c3C81545d370f3634392De611CaaBFf8148
    function setName(string memory name) external;
    function node(address addr) external pure returns (bytes32);
    function claim(address owner) external returns (bytes32); // set name does this
    function claimWithResolver(address owner, address resolver) external returns (bytes32);
    function defaultResolver() external pure returns(IENSReverseResolver);
}

interface IENSReverseResolver { // 0xA2C122BE93b0074270ebeE7f6b7292C7deB45047
    function setName(bytes32 node, string memory name) external;
    function node(address addr) external pure returns (bytes32);
}

/**
* @dev ICryptoPunk used to query the cryptopunks contract to verify the owner
*/
interface ICryptoPunks {
    //function balanceOf(address account) external view returns (uint256);
    //function punkIndexToAddress(uint256 punkIndex) external returns (address);
    //function punksOfferedForSale(uint256 punkIndex) external returns (bool, uint256, address, uint256, address);
    function buyPunk(uint punkIndex) external payable;
    //function transferPunk(address to, uint punkIndex) external;
    function offerPunkForSaleToAddress(uint punkIndex, uint minSalePriceInWei, address toAddress) external;
}

interface ICryptoPunksTokenURI {
    function tokenURI(uint256 _tokenId) external view returns (string memory);
}

interface ICigtoken is IERC20 {
    function taxBurnBlock() external view returns (uint256);
    function CEO_price() external view returns (uint256);
}


