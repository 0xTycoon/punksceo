// SPDX-License-Identifier: MIT
// 🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔
// Author: tycoon.eth
// Project: Cig Token
// About: ERC721 for Employee ID cards
// 🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔
pragma solidity ^0.8.17;

/*



*/

contract EmployeeIDCards {

    enum State {
        Active,
        PendingExpiry,
        Expired
    }

    struct Card {
        bytes32 graffiti;        // graffiti settable by owner
        address identiconAddress;// address of identicon
        address owner;           // address of current owner
        address approval;        // address approved for
        uint64 lastEventAt;      // block id of when last state changed
        uint64 issuedAt;         // block id when issued
        uint64 index;            // sequential index, i.e. the id
        State state;             // NFT's state
    }

    IStogie public stogie;
    ICigToken private immutable cig;           // 0xCB56b52316041A62B6b5D0583DcE4A8AE7a3C629
    mapping (address => uint256) public cardsIndex; // address to card id
    mapping(address => uint256) private balances;   // counts of ownership
    mapping(address => mapping(uint256 => uint256)) private ownedCards; // track enumeration
    mapping (uint256 => Card) public cards; // all of the cards
    uint256 employeeHeight; // the next available employee id
    mapping(address => mapping(address => bool)) private approvalAll; // operator approvals
    bytes4 private constant RECEIVED = 0x150b7a02; // bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))
    mapping(address => bool) public minters;
    address private deployer;
    uint public minSTOG = 10 ether; // minimum STOG required to mint
    uint64 public minSTOGUpdatedAt; // block number of last change
    uint16 private immutable EPOCH;
    uint16 private immutable DURATION;
    event StateChanged(uint256 indexed id, address caller, State s0, State s1);
    event MinSTOGChanged(uint256 minSTOG, uint256 amt);

    constructor(address _cig, uint16 _epoch, uint16 _duration) {
        deployer = msg.sender;
        cig = ICigToken(_cig);
        EPOCH = _epoch;
        DURATION = _duration;
    }

    /**
    * @dev setStogie can only be called once
    */
    function setStogie(address _s) public {
        require (msg.sender == deployer);
        require (address(stogie) == address(0));
        stogie = IStogie(_s);
    }

    /**
    * @dev issueID mints a new ID card. The account must be an active stogie staker
    */
    function issueID(address _to) external {
        require(msg.sender == address(stogie), "you're not stogie");
        _issueID(_to);
    }

    function issueID() external {
        IStogie.UserInfo memory i = stogie.farmers(msg.sender);
        require(i.deposit > minSTOG, "insert more STOG");
        _issueID(msg.sender);
    }

    function _issueID(address _to) internal {
        require(minters[_to] == false, "_to has minted a card already");
        uint256 id = employeeHeight;
        cards[id].owner = _to;
        balances[_to]++;
        cardsIndex[_to] = id;
        Card storage c = cards[id];
        c.state = State.Active;
        c.issuedAt = uint64(block.timestamp);
        emit Transfer(address(0), _to, id);
        unchecked {id++;}
        employeeHeight = id;
        minters[_to] = true;
    }

    function setGraffiti(uint256 _tokenId, bytes32 _g) external {
        require (msg.sender == cards[_tokenId].owner, "must be owner");
        cards[_tokenId].graffiti = _g;
    }

    /**
    * @dev Initiate s.PendingExpiry if account does not possess minimal stake.
    *   or, place NFT to s.Expired after spending 30 days in s.PendingExpiry.
    */
    function expire(uint256 _tokenId) external returns (State) {
        Card storage c = cards[_tokenId];
        State s = c.state;
        IStogie.UserInfo memory i = stogie.farmers(msg.sender);
        if ((s == State.Active) &&
            (i.deposit < minSTOG)) {
            c.state = State.PendingExpiry;
            c.lastEventAt = uint64(block.number);
            emit StateChanged(
                _tokenId,
                msg.sender,
                s,
                State.PendingExpiry
            );
            return State.PendingExpiry;
        } else if (s == State.PendingExpiry) {
            if (c.lastEventAt < block.number - 7200 * 30) {
                c.state = State.Expired;
                c.lastEventAt = uint64(block.number);
                emit StateChanged(
                    _tokenId,
                    msg.sender,
                    s,
                    State.Expired
                );
                _transfer(c.owner, address(this), _tokenId); // take token
                return State.Expired;
            }
        }
        return s;
    }

    /**
    * @dev respawn an expired token
    */
    function respawn(uint256 _tokenId) external {
        Card storage c = cards[_tokenId];
        State s = c.state;
        require (s == State.Expired, "must be expired");
        IStogie.UserInfo memory i = stogie.farmers(msg.sender);
        require(i.deposit > minSTOG, "insert more STOG");
        emit StateChanged(_tokenId, msg.sender, s, State.Active);
        c.state = State.Active;
        _transfer(address(this), msg.sender, _tokenId);
        c.lastEventAt = uint64(block.number);
    }

    /**
    * @dev take a snapshot of the holder's address. This will change the
    *   punk-identicon
    */
    function snapshot(uint256 _tokenId) external {
        require (msg.sender == cards[_tokenId].owner, "must be owner");
        cards[_tokenId].identiconAddress = msg.sender;
    }

    /**
    * minSTOGChange allows the CEO of CryptoPunks to change the minSTOG
    *    either increasing or decreasing by 10%. Cannot be below 1 STOG, or
    *    above 0.1% of staked STOG supply.
    * @param _up increase by 20% if true, decrease otherwise.
    */
    function minSTOGChange(bool _up) external {unchecked {
        require(msg.sender == cig.The_CEO(), "need to be CEO");
        require(block.number > cig.taxBurnBlock() - 20, "need to be CEO longer");
        require(block.number > minSTOGUpdatedAt + 7200, "wait more blocks");
        minSTOGUpdatedAt = uint64(block.number);
        uint256 amt = minSTOG / 10;                               // %10
        uint256 newMin;
        if (_up) {
            newMin = minSTOG + amt;
        } else {
            newMin = minSTOG - amt;
        }
        require (newMin > 1 ether, "min too small");
        require (newMin < cig.stakedlpSupply() / 1000, "too big"); // must be less than 0.1% of staked supply
        minSTOG = newMin;                                          // write
        emit MinSTOGChanged(minSTOG, amt);
    }}

    /**
    * @dev called after an erc721 token transfer, after the counts have been updated
    */
    function addEnumeration(address _to, uint256 _tokenId) internal {
        uint256 last = balances[_to]-1;           // the index of the last position
        ownedCards[_to][last] = _tokenId;         // add a new entry
        cards[_tokenId].index = uint64(last);
    }

    function removeEnumeration(address _from, uint256 _tokenId) internal {
        uint256 height = balances[_from];         // last index
        uint256 i = cards[_tokenId].index;        // index
        if (i != height) {
            // If not last, move the last token to the slot of the token to be deleted
            uint256 lastTokenId = ownedCards[_from][height];
            ownedCards[_from][i] = lastTokenId;   // move the last token to the slot of the to-delete token
            cards[lastTokenId].index = uint64(i); // update the moved token's index
        }
        cards[_tokenId].index = 0;                // delete from index
        delete ownedCards[_from][height];         // delete last slot
    }

    /***
    * Custom ERC721 functionality.
    * Only 1 nft per wallet allowed, so no need to implement balances or index enumeration
    */

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /// @notice Count NFTs tracked by this contract
    /// @return A count of valid NFTs tracked by this contract, where each one of
    ///  them has an assigned and queryable owner not equal to the zero address
    function totalSupply() external view returns (uint256) {
        return employeeHeight;
    }

    /// @notice Enumerate valid NFTs
    /// @dev Throws if `_index` >= `employeeHeight`.
    /// @param _index A counter less than `employeeHeight`
    /// @return The token identifier for the `_index`th NFT,
    ///  (sort order not specified)
    function tokenByIndex(uint256 _index) external view returns (uint256) {
        require (_index >= employeeHeight, "index out of range");
        return _index; // index starts from 0
    }

    /// @notice Enumerate NFTs assigned to an owner
    /// @dev Throws if `_index` >= `balanceOf(_owner)` or if
    ///  `_owner` is the zero address, representing invalid NFTs.
    /// @param _owner An address where we are interested in NFTs owned by them
    /// @param _index A counter less than `balanceOf(_owner)`
    /// @return The token identifier for the `_index`th NFT assigned to `_owner`,
    ///   (sort order not specified)
    function tokenOfOwnerByIndex(address _owner, uint256 _index) external view returns (uint256) {
        require (_index <= balances[_owner], "index out of range");
        require (_owner != address(0), "invalid _owner");
        return ownedCards[_owner][_index];
    }

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address _holder) public view returns (uint256) {
        // each address can only own 1
        require (_holder != address(0), "invalid _owner");
        return balances[_holder];
    }

    function name() public pure returns (string memory) {
        return "Cigarette Factory ID Cards";
    }

    function symbol() public pure returns (string memory) {
        return "EMPLOYEE";
    }

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 _tokenId) public view returns (string memory) {
        require ( _tokenId < employeeHeight, "index out of range");
        return string(abi.encodePacked('moo')); // todo
    }

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 _tokenId) public view returns (address) {
        require (_tokenId >= employeeHeight, "index out of range");
        Card storage c = cards[_tokenId];
        address owner = c.owner;
        require (owner != address(0), "not minted.");
        return owner;
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
        _transfer(_from,  _to, _tokenId);
        require(_checkOnERC721Received(_from, _to, _tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
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
        bytes memory data = new bytes(0);
        _transfer(_from,  _to, _tokenId);
        require(_checkOnERC721Received(_from, _to, _tokenId, data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    function transferFrom(address _from, address _to, uint256 _tokenId) external  {
        _transfer( _from,  _to,  _tokenId);
    }

    function _transfer(address _from, address _to, uint256 _tokenId) internal {
        require(_from != _to, "not allowed");
        require (_tokenId < employeeHeight, "index out of range");
        require (_to != address(0), "_to is zero");
        address o =  cards[_tokenId].owner;
        require (o == _from, "_from must be owner");        // also ensures that the card exists
        address a = cards[_tokenId].approval;
        require (
            msg.sender == address(stogie) ||
            o == address(this) ||
            o == msg.sender ||
            a == msg.sender ||
            (approvalAll[o][msg.sender]), "not permitted"); // check permissions
        balances[_to]++;
        balances[_from]--;
        cards[_tokenId].owner = _to;                        // set new owner
        removeEnumeration(_from, _tokenId);
        addEnumeration(_to, _tokenId);
        emit Transfer(_from, _to, _tokenId);
        if (a != address(0)) {
            cards[_tokenId].approval = address(0);          // clear previous approval
            emit Approval(msg.sender, address(0), _tokenId);
        }
    }

    /**
    * @notice The only way to transfer ownership is via the buyNFT function
    * @dev Approvals are not supported by this contract
    * @param _to The new approved NFT controller
    * @param _tokenId The NFT to approve
    */
    function approve(address _to, uint256 _tokenId) external {
        require (_tokenId < employeeHeight, "index out of range");
        address o = cards[_tokenId].owner;
        require (o == msg.sender || isApprovedForAll(o, msg.sender), "action not token permitted");
        cards[_tokenId].approval = _to;
        emit Approval(msg.sender, _to, _tokenId);
    }
    /**
    * @notice The only way to transfer ownership is via the buyNFT function
    * @dev Approvals are not supported by this contract
    * @param _operator Address to add to the set of authorized operators
    * @param _approved True if the operator is approved, false to revoke approval
    */
    function setApprovalForAll(address _operator, bool _approved) external {
        approvalAll[msg.sender][_operator] = _approved;
        emit ApprovalForAll(msg.sender, _operator, _approved);
    }

    /**
    * @notice The approvals feature is not supported by this contract
    * @dev Throws if `_tokenId` is not a valid NFT.
    * @param _tokenId The NFT to find the approved address for
    * @return Will always return address(this)
    */
    function getApproved(uint256 _tokenId) public view returns (address) {
        return cards[_tokenId].approval;
    }

    /**
    * @notice The approvals feature is not supported by this contract
    * @param _owner The address that owns the NFTs
    * @param _operator The address that acts on behalf of the owner
    * @return Will always return false
    */
    function isApprovedForAll(address _owner, address _operator) public view returns (bool) {
        return approvalAll[_owner][_operator];
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
    
    // we do not allow NFTs to be send to this contract, except internally
    function onERC721Received(address /*_operator*/, address /*_from*/, uint256 /*_tokenId*/, bytes memory /*_data*/) external view returns (bytes4) {
        if (msg.sender == address(this)) {
            return RECEIVED;
        }
        revert("nope");
    }

    /**
    * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
    * The call is not executed if the target address is not a contract.
    *
    * @param from address representing the previous owner of the given token ID
    * @param to target address that will receive the tokens
    * @param tokenId uint256 ID of the token to be transferred
    * @param _data bytes optional data to send along with the call
    * @return bool whether the call correctly returned the expected magic value
    *
    * credits https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/ERC721.sol
    */
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) private returns (bool) {
        if (isContract(to)) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, _data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
            return false; // not needed, but the ide complains that there's "no return statement"
        } else {
            return true;
        }
    }

    /**
     * @dev Returns true if `account` is a contract.
     *
     * credits https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Address.sol
     */
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

}

interface IStogie {
    struct UserInfo {
        uint256 deposit;    // How many LP tokens the user has deposited.
        uint256 rewardDebt; // keeps track of how much reward was paid out
    }
    function farmers(address _user) external view returns (UserInfo memory);
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


interface ICigToken  {
    function stakedlpSupply() external view returns(uint256);
    function taxBurnBlock() external view returns (uint256);
    function The_CEO() external view returns (address);
}