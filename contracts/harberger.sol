// Author: 0xTycoon
// Project: Hamburger Hut
// About: Place your NFTs under harberger tax & earn
pragma solidity ^0.8.17;

import "hardhat/console.sol";

/**

Welcome to BurgerMarket, a unique NFT marketplace where the NFTs are always for sale!

A deed wraps an NFT. The deed causes the NFT to be always for sale.
The user who wraps the NFT is called an "Originator

Rules:

- Taking out: The NFT can be taken out by the Originator, if they also own the deed.
The bond will be returned upon taking it out. The Originator is required to wait 7 days in order to take out the NFT.
This means that the originator will need to be a holder of the deed for at least 7 days.

- if the NFT being wrapped as a Deed is an ENS, then reclaim() is called after wrapping. Reclaim will be called again
after un-wrapping

* states
* 0 = initial
* 1 = CEO reigning
* 2 = Dutch auction
* 3 = Taken out

todo: ens proxy, check if ens reg expired, getinfo could also return details about ENS
*/

contract Harberger {

    // Structs
    struct Deed {
        uint256 nftTokenID; // the token id of the NFT that is wrapped in this deed
        uint256 price;      // takeover price in 'priceToken'
        uint256 bond;       // amount of CIG taken for a new deed (returned later)
        uint256 taxBalance; // amount of tax pre-paid
        bytes32 graffiti;   // a 32 character graffiti set when buying a deed
        address originator; // address of the creator of the deed
        address holder;     // address of current holder and tax payer
        address nftContract;// address of the NFT that is wrapped in this deed
        IERC20 priceToken;  // address of the payment token
        uint64 taxBurnBlock;// block number when tax was last burned
        uint64 blockStamp;  // block number when NFT transferred owners
        uint32 index;       // stores the index for deed enumeration
        uint16 [2] rate;    // a number between 1 and 1000, eg 1 represents 0.1%, 11 = %1.1 333 = 33.3
                            // rate[0] is the tax %, rate[1] is the share
        uint8 state;
    }

    // Storage
    uint256 public deedBond = 100000 ether; // price in CIG (to prevent spam)
    mapping(uint256 => Deed) public deeds; // a deed is also an NFT
    uint256 public deedHeight; // highest deedID
    mapping(address => uint256) private balances;      // counts of ownership
    //mapping(uint256  => address) private ownership; // deeds track ownership
    mapping(uint256 => uint256) private ownedDeedsIndex;
    mapping(address => mapping(uint256 => uint256)) private ownedDeeds;
    // Constants
    uint256 private immutable epochBlocks;   // secs per day divided by 12 (86400 / 12), assuming 12 sec blocks
    uint256 private immutable auctionBlocks; // 3600 blocks
    ICigtoken private immutable cig; // 0xCB56b52316041A62B6b5D0583DcE4A8AE7a3C629
    IENS private immutable ens; // 0x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85
    ICryptoPunks private immutable punks;
    uint private constant SCALE = 1e3;
    bytes4 private constant RECEIVED = 0x150b7a02; // bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))
    uint256 constant MIN_PRICE = 1e12;            // 0.000001
    uint8 internal locked = 1; // 2 = entered, 1 not

    // Modifiers
    modifier notReentrant() {
        require(locked == 1, "already entered");
        locked = 2; // enter
        _;
        locked = 1; // exit
    }

    // Events
    event NewDeed(uint256 indexed deedID);
    event Takeover(uint256 indexed deedID, address indexed user, uint256 new_price, bytes32 graffiti); // when a NFT is bought
    event TaxDeposit(uint256 indexed deedID, address indexed user, uint256 amount);     // when tax is deposited
    event RevenueSplit(
        uint256 indexed deedID,
        address indexed user,
        uint256 amount,
        uint16 split,
        address indexed originator);                                                    // revenue paid out
    event Defaulted(uint256 indexed deedID, address indexed called_by, uint256 reward); // when owner defaulted on tax
    event PriceChange(uint256 indexed deedID, uint256 price);                           // when owner changed price
    event Takeout(uint256 indexed deedID, address indexed user);                        // when NFT taken out from deed

    constructor(
        uint256 _epochBlocks, // 7200
        uint256 _auctionBlocks, // 3600
        address _cig, // 0xCB56b52316041A62B6b5D0583DcE4A8AE7a3C629
        address _ens, // 0x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85
        address _punks
    ){
        epochBlocks = _epochBlocks;
        auctionBlocks = _auctionBlocks;
        cig = ICigtoken(_cig);
        ens = IENS(_ens);
        punks = ICryptoPunks(_punks);
    }

    /**
    * @dev create a new Deed by wrapping an NFT, putting it under a Harberger tax system
    *   A new Deed token will be issued with the next available id.
    * @param _nftContract address of the nft to wrap, can be an ERC721 or a punk
    * @param _tokenID the token id from the _nftContract address
    * @param _priceToken address of the ERC20 to use as the payment token
    * @param _taxRate a number between 1 and 1000, eg 1 represents 0.1%, 11 = %1.1 333 = 33.3
    * @param _share of revenue that goes to originator, remainder is burned. The type is same as _taxRate
    */
    function newDeed(
            address _nftContract,
            uint256 _tokenID,
            uint256 _price, // initial price
            address _priceToken,
            uint16 _taxRate,
            uint16 _share
    ) external notReentrant returns (uint256 deedID) {
        unchecked{deedID = ++deedHeight;} // starts from 1
        Deed storage d = deeds[deedID];
        d.originator = msg.sender;
        d.nftContract = _nftContract;
        d.nftTokenID = _tokenID;
        d.priceToken = IERC20(_priceToken);
        d.price = _price;
        d.rate[0] = _taxRate;
        d.rate[1] = _share;
        cig.transferFrom(msg.sender, address(this), deedBond);
        d.bond = deedBond;
        if (d.nftContract == address(punks)) {
            punks.buyPunk(_tokenID); // wrap the punk
        } else {
            IERC721(d.nftContract).safeTransferFrom(msg.sender, address(this), _tokenID); // wrap the nft
            if (d.nftContract == address(ens)) {
                ens.reclaim(_tokenID, address(this)); // become the controller
            }
        }
        _mint(msg.sender, deedID);
        emit NewDeed(deedID);
        return (deedID);
    }

    /**
    * @dev buyDeed buys the deed and transfers it to the new holder.
    * @param _deedID the deed id
    * @param _max_spend in wei. Since d.price can change after signing the tx, this can protect the buyer in
    *    case the the d.price gets set to a high value
    * @param _new_price the new takeover price
    */
    function buyDeed(
        uint256 _deedID,
        uint256 _max_spend,
        uint256 _new_price,
        uint256 _tax_amount,
        bytes32 _graffiti
    ) external notReentrant {
        Deed memory d = deeds[_deedID];
        require (d.bond > 0, "no such deed");
        if (d.state == 1 && (d.taxBurnBlock != uint64(block.number))) {
            d.state = _consumeTax(
                _deedID,
                d.price,
                d.rate[0],
                d.rate[1],
                d.taxBurnBlock,
                d.taxBalance,
                d.holder,
                d.originator,
                d.priceToken
            ); // _burnTax can change d.state to 2
            deeds[_deedID].taxBurnBlock = uint64(block.number);                   // store the block number of last burn
        }
        if (d.state == 2) {
             // Auction state. The price goes down 10% every `CEO_auction_blocks` blocks
             d.price = _calcDiscount(d.price, d.taxBurnBlock);
        }
        require (_max_spend >= d.price + _tax_amount , "overpaid");        // prevent from over-payment
        require (_new_price >= MIN_PRICE, "price 2 smol");                 // price cannot be under 0.000001
        require (_tax_amount >= _new_price / 1000, "insufficient tax" );   // at least %0.1 fee paid for 1 epoch
        require (msg.sender != d.holder, "you already own it");
        safeERC20TransferFrom(
            d.priceToken, msg.sender, address(this), d.price + _tax_amount
        );                                                                 // pay for the deed + deposit tax
        _splitRevenue(d.priceToken, d.price, d.rate[1], d.originator);     // split the revenue
        emit RevenueSplit(_deedID, msg.sender, d.price, d.rate[1], d.originator);
        if (d.taxBalance > 0) {
            safeERC20Transfer(d.priceToken, d.holder, d.taxBalance);        // return deposited tax back to old holder
            // deeds[_deedID].taxBalance                                    // not needed, will be overwritten
        }
        deeds[_deedID].taxBalance = _tax_amount;                            // store the tax deposit amount
        _transfer(d.holder, msg.sender, _deedID);                           // transfer deed to buyer
        deeds[_deedID].price = _new_price;                                  // set the new price
        deeds[_deedID].blockStamp = uint64(block.number);                   // record the block of state change
        deeds[_deedID].state = 1;                                           // make available for sale
        deeds[_deedID].graffiti = _graffiti;                                // save the graffiti
        emit TaxDeposit(_deedID, msg.sender, _tax_amount);
        emit Takeover(_deedID, msg.sender, _new_price, _graffiti);
    }

    /**
    * @dev depositTax pre-pays tax for the existing holder.
    * It may also burn any tax debt the holder may have.
    * @param _amount amount of tax to pre-pay
    */
    function depositTax(uint256 _deedID, uint256 _amount) notReentrant external {
        Deed memory d = deeds[_deedID];
        require (d.state == 1, "not active");
        require (d.holder == msg.sender, "only holdoor");
        if (_amount > 0) {
            d.taxBalance += _amount;
            deeds[_deedID].taxBalance = d.taxBalance;        // record the balance
            emit TaxDeposit(_deedID, msg.sender, _amount);
            safeERC20TransferFrom(d.priceToken, msg.sender, address(this), _amount); // place the tax on deposit
        }
        if (d.taxBurnBlock != uint64(block.number)) {
            _consumeTax(
                _deedID,
                d.price,
                d.rate[0],
                d.rate[1],
                d.taxBurnBlock,
                d.taxBalance,
                d.holder,
                d.originator,
                d.priceToken);                                         // settle any tax debt
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
        require (d.state == 1, "deed not active");
        if (d.taxBurnBlock == uint64(block.number)) return;
        _consumeTax(
            _deedID,
            d.price,
            d.rate[1],
            d.rate[0],
            d.taxBurnBlock,
            d.taxBalance,
            d.holder,
            d.originator,
            d.priceToken);
        deeds[_deedID].taxBurnBlock = uint64(block.number);
    }

    /**
     * @dev setPrice changes the price for the holder title.
     * @param _price the price to be paid. The new price most be larger tan MIN_PRICE and not default on debt
     * @return state
     */
    function setPrice(uint256 _deedID, uint256 _price) external notReentrant returns (uint8 state) {
        Deed memory d = deeds[_deedID];
        require (d.holder == msg.sender, "only holdoor");
        require (d.state == 1, "deed not active");
        require (_price >= MIN_PRICE, "price 2 smol");
        require (d.taxBalance >= _price / SCALE * d.rate[0], "price would default"); // need at least tax for 1 epoch
        if (block.number != d.taxBurnBlock) {
            state = _consumeTax(
                _deedID,
                d.price,
                d.rate[0],
                d.rate[1],
                d.taxBurnBlock,
                d.taxBalance,
                d.holder,
                d.originator,
                d.priceToken);
            deeds[_deedID].taxBurnBlock = uint64(block.number);
        }
        // The state is 1 if the holder hasn't defaulted on tax
        if (state == 1) {
            deeds[_deedID].price = _price;                                   // set the new price
            emit PriceChange(_deedID, _price);
        }
        return state;
    }

    /**
    * @dev takeout allows the deed's originator to unwrap and remove the nft
    */
    function takeout(uint256 _deedID) external notReentrant returns (uint8 state) {
        Deed memory d = deeds[_deedID];
        require (d.holder == msg.sender, "only holdoor");
        require (d.state == 1, "deed not active");
        require (d.blockStamp + (epochBlocks*7) >= block.number, "must wait 7 epochs");
        require (d.originator == msg.sender, "only originatoor");
        if (d.taxBurnBlock == uint64(block.number)) return d.state;
        state = _consumeTax(
            _deedID,
            d.price,
            d.rate[0],
            d.rate[1],
            d.taxBurnBlock,
            d.taxBalance,
            d.holder,
            d.originator,
            d.priceToken);
        if (state != 1 ) { // defaulted on tax?
            return state;
        }
        deeds[_deedID].state = 3;
        deeds[_deedID].taxBurnBlock = uint64(block.number);
        d.nftTokenID;
        if (d.nftContract == address(punks)) {
            punks.offerPunkForSaleToAddress(d.nftTokenID, 0, msg.sender);
        } else {
            if (d.nftContract == address(ens)) {
                ens.reclaim(d.nftTokenID, msg.sender); // relinquish the controller
            }
            IERC721(d.nftContract).safeTransferFrom(address(this), msg.sender, d.nftTokenID); // unwrap
        }
        if (d.taxBalance + d.bond > 0) {
            safeERC20Transfer(d.priceToken, d.holder, d.taxBalance + d.bond);        // return deposited tax back to old holder
            deeds[_deedID].taxBalance = 0;                                   // not needed, will be overwritten
            deeds[_deedID].bond = 0;
        }

        _transfer(d.holder, address(0), _deedID); // burn the deed
        emit Takeout(d.nftTokenID, msg.sender);
        return 3;
    }

    /**
    * @dev _burnTax burns any tax debt. Boots the owner if defaulted, assuming can state is 1
    * @return uint8 state 2 if if defaulted, 1 if not
    */
    function _consumeTax(
        uint256 _deedID,
        uint256 _price,
        uint16 _taxRate,
        uint16 _split,
        uint64 _taxBurnBlock,
        uint256 _taxBalance,
        address _holder,
        address _originator,
        IERC20 _token
    ) internal returns(uint8 /*state*/) {
        uint256 tpb = _price / SCALE * _taxRate / epochBlocks;      // calculate tax-per-block
        uint256 debt = (block.number - _taxBurnBlock) * tpb;
        if (_taxBalance !=0 && _taxBalance >= debt) {               // Does holder have enough deposit to pay debt?
            _taxBalance = _taxBalance - debt;                       // deduct tax
            _splitRevenue(_token, debt, _split, _originator);       // burn the tax
            emit RevenueSplit(_deedID, msg.sender, debt, _split, _originator);
        } else {
            // Holder defaulted
            uint256 default_amount = debt - _taxBalance;             // calculate how much defaulted
            _splitRevenue(_token, _taxBalance, _split, _originator); // burn the tax
            emit RevenueSplit(_deedID, msg.sender, _taxBalance, _split, _originator);
            deeds[_deedID].state = 2;                                 // initiate a Dutch auction.
            deeds[_deedID].taxBalance = 0;
            _transfer(_holder, address(this), _deedID);               // Strip the deed from the holder
            emit Defaulted(_deedID, msg.sender, default_amount);
            return 2;
        }
        return 1;
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
    * @dev deedBond updates the minimum bond amount required for a deed (spam prevention)
    */
    function updateMinAmount() external {
        unchecked {
            require (block.number - cig.taxBurnBlock() > 50, "must be CEO for at least 50 blocks");
            deedBond = cig.CEO_price() / 10;
        }
    }

    /**
    * @return _ret - array of uin256 with state info
    * @return deed - deed state selected by _deedID
    * @return symbol - ERC20 symbol of deed.
    */
    function getInfo(address _user, uint256 _deedID) view public returns (
        uint256[] memory,   // ret
        Deed memory deed,
        string memory symbol,
        string memory nftName,
        string memory nftSymbol,
        string memory nftTokenURI
    ) {
        uint[] memory ret = new uint[](11);
        deed = deeds[_deedID];
        ret[0] = deedBond;
        ret[1] = epochBlocks;
        ret[2] = auctionBlocks;
        ret[3] = cig.balanceOf(_user);
        ret[4] = cig.allowance(_user, address(this));
        if (deed.state != 0) {
            ret[5] = IERC20(deed.priceToken).balanceOf(_user);
            ret[6] = IERC20(deed.priceToken).allowance(_user, address(this));
        }
        ret[7] = deedHeight;
        ret[8] = balanceOf(_user); //deed balance
        ret[9] = cig.taxBurnBlock();
        ret[10] = cig.CEO_price();
        if (deed.state != 0) {
            ret[11] = uint256(IERC20(deed.priceToken).decimals());
            symbol = IERC20(deed.priceToken).symbol();
            nftName = IERC721(deed.nftContract).name();
            nftSymbol = IERC721(deed.nftContract).symbol();
            nftTokenURI = tokenURI(_deedID);
            if (deed.state == 2) {
                deed.price = _calcDiscount(deed.price, deed.taxBurnBlock);
            }
        }
        return (ret, deed, symbol, nftName, nftSymbol, nftTokenURI);
    }

    /** todo Proxy functions for ENS

    **/

    /**
    * @dev burn some tokens
    * @param _token The token to burn
    * @param _amount The amount to burn
    * @param _split The % to send to originator, burn remainder
    * @param _originator address to send the revenue split, burn any remainder
    */
    function _splitRevenue(IERC20 _token,  uint256 _amount, uint16 _split, address _originator) internal {

        if (_split == 1000) {
            safeERC20Transfer(_token, _originator, _amount);             // distribute all
        } else if (_split > 0) {
            uint256 distribute = _amount / SCALE * _split;
            safeERC20Transfer(_token, _originator, distribute);          // distribute portion
            safeERC20Transfer(_token, address(0), _amount - distribute); // burn remainder
        } else if (_split == 0) {
            safeERC20Transfer(_token, address(0), _amount);              // burn all
        }

    }

    function safeERC20Transfer(IERC20 _token, address _to, uint256 _amount) internal {
        bytes memory payload = abi.encodeWithSelector(_token.transfer.selector, address(0), _amount);
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

    function deedNFTMetadata(uint256 _deedID) public view returns (string memory, string memory) {
        IERC721Metadata t = IERC721Metadata(deeds[_deedID].nftContract);
        return (t.name(), t.symbol());
    }

    /***
    * ERC721 stuff
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
            ICryptoPunksTokenURI uri = ICryptoPunksTokenURI(0x93b919324ec9D144c1c49EF33D443dE0c045601e);
            return uri.tokenURI(_tokenId);
        }
        if (d.nftContract == address(ens)) {
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
    function isApprovedForAll(address _owner, address _operator) public view returns (bool) {
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
    * @dev transfer a token from _from to _to
    * @param _from from
    * @param _to to
    * @param _tokenId the token index
    */
    function _transfer(address _from, address _to, uint256 _tokenId) internal {
        balances[_to]++;
        balances[_from]--;
        deeds[_tokenId].holder = _to;
        if (_from != _to) {
            removeEnumeration(_from, _tokenId);
            addEnumeration(_to, _tokenId);
        }
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
        uint256 last = balances[_to]-1;   // the index of the last position
        ownedDeeds[_to][last] = _tokenId; // add a new entry
        deeds[_tokenId].index = uint32(last);

    }
    function removeEnumeration(address _from, uint256 _tokenId) internal {
        uint256 height = balances[_from];  // last index
        uint256 i = deeds[_tokenId].index; // index
console.log("remove", height, i);
        if (i != height) {
            // If not last, move the last token to the slot of the token to be deleted
            uint256 lastTokenId = ownedDeeds[_from][height];
            ownedDeeds[_from][i] = lastTokenId;   // move the last token to the slot of the to-delete token
            deeds[lastTokenId].index = uint32(i); // update the moved token's index
        }
        deeds[_tokenId].index = 0;        // delete from index
        delete ownedDeeds[_from][height]; // delete last slot
    }

    // we do not allow NFTs to be send to this contract, except internally
    function onERC721Received(address /*_operator*/, address /*_from*/, uint256 /*_tokenId*/, bytes memory /*_data*/) external view returns (bytes4) {
        if (msg.sender == address(this)) {
            return RECEIVED;
        }
        revert("nope");
    }

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

interface IENS {
    function reclaim(uint256 id, address owner) external;
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

