// Author: 0xTycoon
// Project: Cigarettes (CEO of CryptoPunks)
// Place your NFTs under harberger tax & earn
pragma solidity ^0.8.15;


import "hardhat/console.sol";

contract Harberger {

    // Structs
    struct Deed {
        uint256 nftTokenID;
        uint256 price;
        uint256 bond; // amount of CIG taken for a new deed (returned later)
        uint256 taxBalance; // amount of tax pre-paid
        bytes32 graffiti;
        address originator; // address of the creator of the deed
        address holder; // address of current holder and tax payer
        address nftContract;
        IERC20 priceToken;
        uint64 taxBurnBlock; // block number when tax was last burned
        uint64 blockStamp; // block number when NFT transferred owners
        uint16 taxRate; // a number between 1 and 1000, eg 1 represents 0.1%, 11 = %1.1 333 = 33.3
        uint16 share; // % that goes to originator
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
    IERC20 private immutable cig;
    uint private constant SCALE = 1e3;
    bytes4 private constant RECEIVED = 0x150b7a02; // bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))
    uint256 constant MIN_PRICE = 1e12;            // 0.000001

    // Events
    // NewCEO -> Takeover
    event NewDeed(uint256 indexed deedID);
    event Takeover(uint256 indexed deedID, address indexed user, uint256 new_price, bytes32 graffiti); // when a NFT is bought
    // TaxDeposit
    event TaxDeposit(uint256 indexed deedID, address indexed user, uint256 amount);     // when tax is deposited
    // RevenueBurned
    event RevenueBurned(uint256 indexed deedID, address indexed user, uint256 amount);  // when tax is burned
    // TaxBurned
    event TaxBurned(uint256 indexed deedID, address indexed user, uint256 amount);      // when tax is burned
    // CEODefaulted -> CEODefaulted
    event Defaulted(uint256 indexed deedID, address indexed called_by, uint256 reward); // when owner defaulted on tax
    // CEOPriceChange -> PriceChange
    event PriceChange(uint256 indexed deedID, uint256 price);                           // when owner changed price

    constructor(uint256 _epochBlocks, uint256 _auctionBlocks, address _cig) {
        epochBlocks = _epochBlocks;
        auctionBlocks = _auctionBlocks;
        cig = IERC20(_cig);
    }

    function newDeed(
            address _nftContract,
            uint256 _tokenID,
            uint256 _price, // initial price
            address _priceToken,
            uint16 _taxRate
    ) external returns (uint256 deedID) {
        unchecked{deedID = ++deedHeight;} // starts from 1
        Deed storage d = deeds[deedID];
        d.originator = msg.sender;
        d.nftContract = _nftContract;
        d.nftTokenID = _tokenID;
        d.priceToken = IERC20(_priceToken);
        d.price = _price;
        d.taxRate = _taxRate;
        cig.transferFrom(msg.sender, address(this), deedBond);
        d.bond = deedBond;
        IERC721(d.nftContract).safeTransferFrom(msg.sender, address(this), _tokenID);
        emit NewDeed(deedID);
        return (deedID);
    }

    function buyNFT(
        uint256 _deedID,
        uint256 _max_spend,
        uint256 _new_price,
        uint256 _tax_amount,
        bytes32 _graffiti
    ) external {
        Deed memory d = deeds[_deedID];
        require (d.bond > 0, "no such deed");
        if (d.state == 1 && (d.taxBurnBlock != uint64(block.number))) {
            d.state = _consumeTax(
                _deedID,
                d.price,
                d.taxRate,
                d.taxBurnBlock,
                d.taxBalance,
                d.holder,
                d.priceToken
            ); // _burnTax can change d.state to 2
            deeds[_deedID].taxBurnBlock = uint64(block.number);                   // store the block number of last burn
        }
        if (d.state == 2) {
             // Auction state. The price goes down 10% every `CEO_auction_blocks` blocks
             d.price = _calcDiscount(d.price, d.taxBurnBlock);
        }
        require (d.price + _tax_amount <= _max_spend, "overpaid");         // prevent from over-payment
        require (_new_price >= MIN_PRICE, "price 2 smol");                 // price cannot be under 0.000001
        require (_tax_amount >= _new_price / 1000, "insufficient tax" );   // at least %0.1 fee paid for 1 epoch
        safeERC20TransferFrom(
            d.priceToken, msg.sender, address(this), d.price + _tax_amount
        );                                                                 // pay for the deed + deposit tax
        safeERC20Transfer(d.priceToken, address(0), d.price);              // burn the revenue
        emit RevenueBurned(_deedID, msg.sender, d.price);
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
    function depositTax(uint256 _deedID, uint256 _amount) external {
        Deed memory d = deeds[_deedID];
        require (d.state == 1, "not active");
        require (d.holder == msg.sender, "only holdoor");
        if (_amount > 0) {
            safeERC20TransferFrom(d.priceToken, msg.sender, address(this), _amount); // place the tax on deposit
            d.taxBalance += _amount;
            deeds[_deedID].taxBalance = d.taxBalance;        // record the balance
            emit TaxDeposit(_deedID, msg.sender, _amount);
        }
        if (d.taxBurnBlock != uint64(block.number)) {
            _consumeTax(
                _deedID,
                d.price,
                d.taxRate,
                d.taxBurnBlock,
                d.taxBalance,
                d.holder,
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

    function consumeTax(uint256 _deedID) external  {
        Deed memory d = deeds[_deedID];
        require (d.state == 1, "deed not active");
        if (d.taxBurnBlock == uint64(block.number)) return;
        _consumeTax(
            _deedID,
            d.price,
            d.taxRate,
            d.taxBurnBlock,
            d.taxBalance,
            d.holder,
            d.priceToken);
        deeds[_deedID].taxBurnBlock = uint64(block.number);
    }

    /**
     * @dev setPrice changes the price for the holder title.
     * @param _price the price to be paid. The new price most be larger tan MIN_PRICE and not default on debt
     */
    function setPrice(uint256 _deedID, uint256 _price) external  {
        Deed memory d = deeds[_deedID];
        require (d.state == 1, "deed not active");
        require (_price >= MIN_PRICE, "price 2 smol");
        require (d.taxBalance >= _price / SCALE * d.taxRate, "price would default"); // need at least tax for 1 epoch
        if (block.number != d.taxBurnBlock) {
            d.state = _consumeTax(
                _deedID,
                d.price,
                d.taxRate,
                d.taxBurnBlock,
                d.taxBalance,
                d.holder,
                d.priceToken);
            deeds[_deedID].taxBurnBlock = uint64(block.number);
        }
        // The state is 1 if the holder hasn't defaulted on tax
        if (d.state == 1) {
            deeds[_deedID].price = _price;                                   // set the new price
            emit PriceChange(_deedID, _price);
        }
    }

    function getInfo(address _user, uint256 _deedID) view public returns (
        uint256[] memory   // ret
    ) {
        uint[] memory ret = new uint[](10);
        return ret;
    }

    /**
    * @dev _burnTax burns any tax debt. Boots the owner if defaulted, assuming can state is 1
    * @return uint256 state 2 if if defaulted, 1 if not
    */
    function _consumeTax(
        uint256 _deedID,
        uint256 _price,
        uint16 _taxRate,
        uint64 _taxBurnBlock,
        uint256 _taxBalance,
        address _holder,
        IERC20 _token
    ) internal returns(uint8 /*state*/) {
        uint256 tpb = _price / SCALE * _taxRate / epochBlocks;  // calculate tax-per-block
        uint256 debt = (block.number - _taxBurnBlock) * tpb;
        if (_taxBalance !=0 && _taxBalance >= debt) {    // Does holder have enough deposit to pay debt?
            _taxBalance = _taxBalance - debt;            // deduct tax
            _burn(_token, debt);                     // burn the tax
            emit TaxBurned(_deedID, msg.sender, debt);
        } else {
            // Holder defaulted
            uint256 default_amount = debt - _taxBalance;     // calculate how much defaulted
            _burn(_token, _taxBalance);                // burn the tax
            emit TaxBurned(_deedID, msg.sender, _taxBalance);
            deeds[_deedID].state = 2;                                      // initiate a Dutch auction.
            deeds[_deedID].taxBalance = 0;
            _transfer(_holder, address(this), _deedID); // Strip the deed from the holder
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
    * @dev burn some tokens
    * @param _token The token to burn
    * @param _amount The amount to burn
    */
    function _burn(IERC20 _token,  uint256 _amount) internal {
        safeERC20Transfer(_token, address(0), _amount);
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
        require (_index > 0 && _index < deedHeight, "index out of range");
        return _index++;
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
        require (_tokenId < deedHeight, "index out of range");
        Deed storage d = deeds[_tokenId];
        // todo: ens names do not have tokenURI, see https://metadata.ens.domains/docs
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
        require (_tokenId < deedHeight, "index out of range");
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
        require(msg.sender == address(this), "not allowed"); // call must come from this contract
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
        require(msg.sender == address(this), "not allowed"); // call must come from this contract
    }

    function transferFrom(address _from, address _to, uint256 _tokenId) external  {
        require(msg.sender == address(this), "not allowed"); // call must come from this contract
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
        require (_tokenId < deedHeight, "index out of range");
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

    function addEnumeration(address to, uint256 tokenId) internal {
        uint256 length = balances[to];
        ownedDeeds[to][length] = tokenId;
        ownedDeedsIndex[tokenId] = length;
    }
    function removeEnumeration(address from, uint256 _tokenId) internal {
        uint256 height = balances[from]-1; // last index
        uint256 i = ownedDeedsIndex[_tokenId]; // index
        if (i != height) {
            // If not last, move the last token to the slot of the token to be deleted
            uint256 lastTokenId = ownedDeeds[from][height];
            ownedDeeds[from][i] = lastTokenId; // Move the last token to the slot of the to-delete token
            ownedDeedsIndex[lastTokenId] = i; // Update the moved token's index
        }
        delete ownedDeedsIndex[_tokenId];// delete from index
        delete ownedDeeds[from][height]; // delete last slot
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