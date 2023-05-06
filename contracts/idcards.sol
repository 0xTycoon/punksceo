// SPDX-License-Identifier: MIT
// 🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔
// Author: tycoon.eth
// Project: Cig Token
// About: ERC721 for Employee ID cards
// 🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔
pragma solidity ^0.8.19;
import "hardhat/console.sol";
/*



*/

contract EmployeeIDCards {
    using DynamicBufferLib for DynamicBufferLib.DynamicBuffer;
    enum State {
        Uninitialized,
        Active,
        PendingExpiry,
        Expired
    }
    struct Card {
        address identiconSeed;   // address of identicon (the minter)
        address owner;           // address of current owner
        address approval;        // address approved for
        uint64 lastEventAt;      // block id of when last state changed
        uint64 index;            // sequential index in the wallet
        State state;             // NFT's state
    }
    IStogie public stogie;
    ICigToken private immutable cig;                // 0xCB56b52316041A62B6b5D0583DcE4A8AE7a3C629
    IPunkIdenticons private immutable identicons; // 0xc55C7913BE9E9748FF10a4A7af86A5Af25C46047;
    IPunkBlocks private immutable pblocks; // 0xe91eb909203c8c8cad61f86fc44edee9023bda4d;
    IBarcode private immutable barcode; // 0x4872BC4a6B29E8141868C3Fe0d4aeE70E9eA6735
    mapping (address => uint256) public cardsIndex; // address to card id
    mapping(address => uint256) private balances;   // counts of ownership
    mapping(address => mapping(uint256 => uint256)) private ownedCards; // track enumeration
    mapping (uint256 => Card) public cards;                             // all of the cards
    uint256 employeeHeight;                                             // the next available employee id
    mapping(address => mapping(address => bool)) private approvalAll;   // operator approvals
    bytes4 private constant RECEIVED = 0x150b7a02; // bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))
    mapping(address => uint64) public minters;       // keep track of addresses & when minted, address => timestamp
    address private deployer;
    uint public minSTOG = 10 ether;                // minimum STOG required to mint
    uint64 public minSTOGUpdatedAt;                // block number of last change
    uint16 private immutable EPOCH;                // 1 day (7200 blocks)
    uint16 private immutable DURATION;             // EPOCHS to elapse for expiration (30)
    event StateChanged(uint256 indexed id, address caller, State s0, State s1);
    event MinSTOGChanged(uint256 minSTOG, uint256 amt);

    constructor(
        address _cig,
        uint16 _epoch,
        uint16 _duration,
        address _identicons,
        address _pblocks,
        address _barcode
) {
        deployer = msg.sender;
        cig = ICigToken(_cig);
        EPOCH = _epoch;
        DURATION = _duration;
        identicons = IPunkIdenticons(_identicons);
        pblocks = IPunkBlocks(_pblocks);
        barcode = IBarcode(_barcode);
    }

    /**
    * @dev setStogie can only be called once
    */
    function setStogie(address _s) public {
        require (msg.sender == deployer, "not deployer");
        require (address(stogie) == address(0), "stogie already set");
        stogie = IStogie(_s);
    }

    /**
    * @dev issueID mints a new ID card. The account must be an active stogie
    *   staker would be called from the Stogies contract. Stogies would ensure
    *   not called form a contract
    */
    function issueID(address _to) external {
        require(msg.sender == address(stogie), "you're not stogie");
        _issueID(_to);
    }

    function issueID() external {
        IStogie.UserInfo memory i = stogie.farmers(msg.sender);
        require(i.deposit > minSTOG, "insert more STOG");
        require(msg.sender == tx.origin);      // must be an EOA (not a contract)
        _issueID(msg.sender);
    }

    function _issueID(address _to) internal {
        require(minters[_to] == 0, "_to has minted a card already");
        uint256 id = employeeHeight;
        cards[id].owner = _to;
        balances[_to]++;
        cardsIndex[_to] = id;
        Card storage c = cards[id];
        c.state = State.Active;
        c.lastEventAt = uint64(block.number);
        emit StateChanged(
            id,
            msg.sender,
            State.Uninitialized,
            State.Active
        );
        emit Transfer(address(0), _to, id); // mint
        unchecked {id++;}
        employeeHeight = id;
        minters[_to] = uint64(block.timestamp);
        c.identiconSeed = _to; // save seed, used for the identicon
    }

    /**
    * @dev expire a token.
    *   Initiate s.PendingExpiry if account does not possess minimal stake.
    *   or, place NFT to s.Expired after spending DURATION (30) days in
    *   s.PendingExpiry.
    * @param _tokenId the token to expire
    */
    function expire(uint256 _tokenId) external returns (State) {
        Card storage c = cards[_tokenId];
        State s = c.state;
        require(s == State.Active || s == State.PendingExpiry, "invalid state");

        IStogie.UserInfo memory i = stogie.farmers(c.owner);
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
            if (c.lastEventAt < block.number - EPOCH * DURATION) {
                c.state = State.Expired;
                c.lastEventAt = uint64(block.number);
                emit StateChanged(
                    _tokenId,
                    msg.sender,
                    s,
                    State.Expired
                );
                minters[c.identiconSeed] = 0;           // minter can mint again
                _transfer(
                    c.owner,
                    address(this),
                    _tokenId);                          // take token
                return State.Expired;
            }
        }
        return s;
    }

    /**
    * @dev reactivate a token. Must be in State.PendingExpiry state.
    *    At least `minSTOG` of Stogies are needed to reactivate.
    */
    function reactivate(uint256 _tokenId) external returns(State) {
        Card storage c = cards[_tokenId];
        State s = c.state;
        require(s == State.PendingExpiry, "invalid state");
        IStogie.UserInfo memory i = stogie.farmers(c.owner);
        if (i.deposit >= minSTOG) {
            c.state = State.Active;
            c.lastEventAt = uint64(block.number);
            emit StateChanged(
                _tokenId,
                msg.sender,
                State.PendingExpiry,
                State.Active
            );
            return State.Active;
        }
        return s;
    }

    /**
    * @dev respawn an expired token. Can only be respawned by an address that
    * hasn't minted.
    * @param _tokenId the token id to respawn
    */
    function respawn(uint256 _tokenId) external {
        require(minters[msg.sender] == 0, "_to has minted a card already");
        Card storage c = cards[_tokenId];
        require (c.state == State.Expired, "must be expired");
        IStogie.UserInfo memory i = stogie.farmers(msg.sender);
        require(i.deposit > minSTOG, "insert more STOG");
        emit StateChanged(
            _tokenId,
            msg.sender,
            State.Expired,
            State.Active
        );
        c.state = State.Active;
        minters[msg.sender] = uint64(block.timestamp);
        c.identiconSeed = msg.sender;                  // used for the identicon
        _transfer(address(this), msg.sender, _tokenId);
        c.lastEventAt = uint64(block.number);
    }


    /**
    * minSTOGChange allows the CEO of CryptoPunks to change the minSTOG
    *    either increasing or decreasing by 1%. Cannot be below 1 STOG, or
    *    above 0.1% of staked STOG supply.
    * @param _up increase by 1% if true, decrease otherwise.
    */
    function minSTOGChange(bool _up) external {unchecked {
        require(msg.sender == cig.The_CEO(), "need to be CEO");
        require(block.number > cig.taxBurnBlock() - 20, "need to be CEO longer");
        require(block.number > minSTOGUpdatedAt + EPOCH, "wait more blocks");
        minSTOGUpdatedAt = uint64(block.number);
        uint256 amt = minSTOG / 1e3 * 10;                               // %1
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
    * ERC721 functionality.
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


    bytes constant badgeStart = '<svg xmlns="http://www.w3.org/2000/svg" width="2343.307" height="1927.559" viewBox="0 0 620 510" shape-rendering="crispEdges"><path d="M330 118h270v350H330z" fill="#ebebeb"/><path d="M589.999 118.668h10v10h-10z" fill="#fff"/><g transform="matrix(0 .999959 -.999889 0 -899.44629 -4620.8766)"><path d="M6755.152-2343.785v-1149.049h-9740.396v1149.049z" fill="#ff0"/><path d="M4739.738-909.547v-10h360v10zm0-590v-10h360v10z"/><path d="M5099.738-919.547v-10h10v10z"/><path d="M5089.738-919.547v-10h10v10zm0-570v-10h10v10z" fill="#a0a0a0"/><path d="M4729.738-1489.547v-10h10v10zm370 0v-10h10v10z"/><path d="M5069.738-1489.547v-10h10v10zm-320-.065v-10h10v10z" fill="#dedede"/><path d="M5109.738-929.547v-560h10v560zm-389.669-.002v-560h10v560z"/><path d="M5099.738-929.547v-560h10v560z" fill="#a0a0a0"/><path d="M5079.738-929.547v-560.062h10v560.062zm-340-.002v-560.062h10v560.062z" fill="#dedede"/><g fill="#fff"><path d="M5080-920v-10h10v10zm-.262-569.547v-10h10v10z"/><path d="M5089.738-929.547v-560h10v560zm-360 0v-560h10v560z"/></g><path d="M4730.069-919.548v-10.001h10v10.001z"/><path d="M4740-920v-310h350v310z" fill="#dedede"/></g><path d="M20 458h10v10H20zm0-339h10v10H20z" fill="#fff"/><path d="M320 148h250v40H320zm0 110h40v20h-40zm0 40h60v20h-60zm0 40h250v20H320zm0 50h250v20H320zm70-90h60v20h-60zm70 0h40v20h-40zm50 0h20v20h-20zm30 0h30v20h-30zm-170-40h30v20h-30zm40 0h70v20h-70zm90 0h70v20h-70z" fill="#7c7b7e"/><path d="M40 148h260v260H40z" fill="#3e545f"/><path d="M50 158h240v240H50z" fill="#638596"/><path d="M270 0h80v130h-80z"/><path d="M280 90h60v30h-60z" fill="#7e7e7e"/><path d="M280 10h60v70h-60z" fill="#c1c1c1"/><path d="M290 80h40v10h-40z" fill="#ddd"/><path d="M290 90h40v10h-40zm10-20h20v10h-20zm0-20h20v10h-20z"/><path d="M320 60h10v10h-10z"/><path d="M300 60h20v10h-20zm-20 10h10v10h-10zm50 0h10v10h-10z" fill="#ddd"/><path d="M290 100h40v10h-40zm-9.583-11.07h10v10h-10zm50 0h10v10h-10z" fill="#6a6a6a"/><path d="M270 130h80v10h-80z" fill="#bfbfbf"/><g fill="#a9a9a9"><path d="M290 70h10v10h-10zm30 0h10v10h-10z"/><path d="M330 60h10v10h-10zm-50-50h20v60h-20z"/></g><path d="M290 60h10v10h-10z"/>';

    bytes constant badgeText = '<svg><defs><style>@font-face {font-family: "C64";src: url(data:font/woff2;base64,d09GMgABAAAAAAVgAA0AAAAAFlgAAAUJAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP0ZGVE0cGhgGYACCWhEICpsEkngLgRwAATYCJAOBbgQgBYQZB4NcG8oQIxGmjE4A4K+TJ0Osoz0yHHiUIkeu8JnCS5uIH1YhT02PLEKlTJ7cqgZVF/5IPHyugb2f7G5SAkXAGljj+Hr2gK6WSeiyg3PnT0iMUWvb91CYfvgbZppEPEaGUigFhE0YA/WRi3POTSggSRRs2fnJ2yeodbZZS3aT5NqzSb5BVxKj6QrdHMN9vERqLCweg+Eon8X6+uo2ar9f/XKLyXSxG1KhEc0iIT+B+6KChSLq0RKhkhiaSi2eIqURK5lMKJlF3GQEMrhGtO1N/74I+LMvU4FPHryBP75yAIXRGA8SOiTkMiVu6qk6hE6HTsjqyBRDN6RUIxAAcGSFcSOOGBYNRZgFcRm9ArNQyMiYhgJHMQLTsDaBqkqYK2DYGmaxS7RG+9l+oAIy6IiBAERCAgAEmQ4A+qH8VNQgwLhXk+wdpp+fVqc3GE1mEeRfRojWAPsAd7Ee0kfyaYhVENsAkGjkSLKQBEUiwcczH8tj/BlZjPR4gciOhukMmG/KPkMmmc0uuWmX7vPFjZQCTKpgN+4z58WghjLNctLuw6qV7mzQFaQCKPjwbOxyRrRqww5jG54lgTpsLi3QH/iqrBWMoFWcTDY6QmOfrVTozOCl7F1evHrv9iAMzShgDTA/KkFTbR4xVisj1YDKNcsYXonRTZiFGJc9rPsYza7KqMo4bBzqMTNDzNQ1l47OjQ3lXd26BA7vUdPRU4hvGaPT8ywb8swsskD+EsahHh1dPpzz9uUMix8UdUNi2YAfuxDlzC5gWqqmqWsjrK2laIRALSvnilvXRppxJ1ePi1aV47jqbJ9eQbiH7Sbfs48oewX3cKofdLojr+rLGjEyjpQIm+VOY/cJG3eK5DX7sJzeFFVHRuvep641aKXl+UL1ma56eRh9ldT9GDGyPCdL85UU+LA+qiN/zrHa2uGPJ/TIKHqeop5Ha3NLFHFspGdLghd6AgUoRpTdTSHLT9TqwVwc6y3IIatqwjAogOmjn+dVGgrzNfQLN34S35USopfAxoYuaOwykhOkB/bkWAKk6ZxgRWuw1nh5KkHiENHImzSY6+xKj3sC9taEpeknfdBVklDE0Id1GE8pKXVxSjU70sggixzyKKCIEsqgIUGGAhUWWGFLs/+lOf7hhAtueOCFD34EEEQIYUQQRQxxeeK4k+TuSfDjjeRcRgoqARYybCjfYTh8p25MpS0FFKifGgFi/c9/+De//W3YHHrPm8V/gagSCIqGEaASAIAlFVCFihEovLkrylL0tWavtplBK5dEecQJAvsQDJQEPCwkjPVSABZp6jQUV6QJ92g22Z92ir9pb2psuXgwxBmM6EbgIOg0jHVOmnCHZot8aWesv2hvQ6SHDEbHcR+zONk52Fnw5gEqouXmbWfOihCt3GjBSZDNcI041cvN6uhiSYIn3xCptvwCJPFfW9GJn3gTPyQ0b5DPWEQWF9ibnk3Ug0fY62T/XvjFcNjc0t3O2AV+pe2oOU8P6pq7uFo7OiAcrJwc1XRbPuF9MLQ6HS3H99AeknDy8qjeoYVnZdgqzUADbejzGxb0fHZFF+g3HMXT9PSmrAx+wX0gIskGk2hcqtQarU5vMJrMFqvN7nC63B4vgAgTyrAcL4iSHCCk0nTDtGzH9XyECWUcL4iSrKiabpiW7bhe/bf/7yORMBGixBBLXKovbQhnIAgMgcLAwhGfTgAEgSFQGFg44tMZgCAwBAoDq3Y=);}.t {fill: #7c7b7e; stroke: none; font-size: 22px; font-family: \'C64\',monospace; text-anchor: end}</style></defs><text x="570px" y="210px" class="t">CIG FACTORY</text><text x="570px" y="232px" class="t">EMPLOYEE</text><text x="570px" y="254px" class="t">#';
    bytes constant badgeEnd = '</text></svg></svg>';

    function _generateBadge(uint256 _tokenId, address _seed) internal view returns (bytes memory) {
        DynamicBufferLib.DynamicBuffer memory result;
console.log("before barcode");
        string memory bars = barcode.draw(_tokenId, "42069", "408", "c0c0c0", 61, 4);
        console.log("about to pick", _seed);
        bytes32[] memory traits = identicons.pick(_seed, 0);
        console.log("after pick");
        string memory punk = pblocks.svgFromKeys(traits, 60, 158, 240, 0);
        result.append(badgeStart, bytes(bars), bytes(punk));
        result.append(badgeText, bytes(_intToString(_tokenId)), badgeEnd);
        return result.data;
    }

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 _tokenId) public view returns (string memory) {
        DynamicBufferLib.DynamicBuffer memory result;
        //require ( _tokenId < employeeHeight, "index out of range"); // todo put back in
        Card storage c = cards[_tokenId];

        bytes memory badge = _generateBadge(_tokenId, c.identiconSeed);


        result.append('{\n"description": "Employee ID Cards for the Cigarette Factory",', "\n",
        '"external_url": "https://cigtoken.eth.limo/#idCard-');
        result.append( bytes(_intToString(_tokenId)),'",', "\n");
        result.append('"image": "data:image/svg+xml;base64,');
        result.append(bytes(Base64.encode(badge)), '",', "\n");
        result.append('"attributes": ',_getAttributes(), "\n}");



        return string(abi.encodePacked("data:application/json;base64,",
            Base64.encode(
                result.data
            /*
                abi.encodePacked(
                    '{\n"description": "Employee ID Cards for the Cigarette Factory', "\n",
                    '"external_url": "https://cigtoken.eth.limo/', _intToString(_tokenId),'",', "\n",
                    '"image": "data:image/svg+xml;base64,', Base64.encode(result.data), '",', "\n",
                    '"name": "Employee Id #', _intToString(_tokenId),'",', "\n",
                    '"attributes": ',_getAttributes(), "\n}"
                )
                */
            )
        ));
        //return string(abi.encodePacked('moo')); // todo
        //return string(result.data);
    }

    function _getAttributes() internal view returns (bytes memory) {
        DynamicBufferLib.DynamicBuffer memory result;
        result.append('["test1", "test2", "test3"]');
        return result.data;
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

    function _intToString(uint256 value) public pure returns (string memory) {
        // Inspired by openzeppelin's implementation - MIT licence
        // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Strings.sol#L15
        // this version removes the decimals counting
        uint8 count;
        if (value == 0) {
            return "0";
        }
        uint256 digits = 31;
        // bytes and strings are big endian, so working on the buffer from right to left
        // this means we won't need to reverse the string later
        bytes memory buffer = new bytes(32);
        while (value != 0) {
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
            digits -= 1;
            count++;
        }
        uint256 temp;
        assembly {
            temp := mload(add(buffer, 32))
            temp := shl(mul(sub(32,count),8), temp)
            mstore(add(buffer, 32), temp)
            mstore(buffer, count)
        }
        return string(buffer);
    }

}

/**
* DynamicBufferLib adapted from
* https://github.com/Vectorized/solady/blob/main/src/utils/DynamicBufferLib.sol
*/
library DynamicBufferLib {
    /// @dev Type to represent a dynamic buffer in memory.
    /// You can directly assign to `data`, and the `append` function will
    /// take care of the memory allocation.
    struct DynamicBuffer {
        bytes data;
    }

    /// @dev Appends `data` to `buffer`.
    /// Returns the same buffer, so that it can be used for function chaining.
    function append(DynamicBuffer memory buffer, bytes memory data)
    internal
    pure
    returns (DynamicBuffer memory)
    {
        /// @solidity memory-safe-assembly
        assembly {
            if mload(data) {
                let w := not(31)
                let bufferData := mload(buffer)
                let bufferDataLength := mload(bufferData)
                let newBufferDataLength := add(mload(data), bufferDataLength)
            // Some random prime number to multiply `capacity`, so that
            // we know that the `capacity` is for a dynamic buffer.
            // Selected to be larger than any memory pointer realistically.
                let prime := 1621250193422201
                let capacity := mload(add(bufferData, w))

            // Extract `capacity`, and set it to 0, if it is not a multiple of `prime`.
                capacity := mul(div(capacity, prime), iszero(mod(capacity, prime)))

            // Expand / Reallocate memory if required.
            // Note that we need to allocate an exta word for the length, and
            // and another extra word as a safety word (giving a total of 0x40 bytes).
            // Without the safety word, the data at the next free memory word can be overwritten,
            // because the backwards copying can exceed the buffer space used for storage.
                for {} iszero(lt(newBufferDataLength, capacity)) {} {
                // Approximately double the memory with a heuristic,
                // ensuring more than enough space for the combined data,
                // rounding up to the next multiple of 32.
                    let newCapacity :=
                    and(add(capacity, add(or(capacity, newBufferDataLength), 32)), w)

                // If next word after current buffer is not eligible for use.
                    if iszero(eq(mload(0x40), add(bufferData, add(0x40, capacity)))) {
                    // Set the `newBufferData` to point to the word after capacity.
                        let newBufferData := add(mload(0x40), 0x20)
                    // Reallocate the memory.
                        mstore(0x40, add(newBufferData, add(0x40, newCapacity)))
                    // Store the `newBufferData`.
                        mstore(buffer, newBufferData)
                    // Copy `bufferData` one word at a time, backwards.
                        for { let o := and(add(bufferDataLength, 32), w) } 1 {} {
                            mstore(add(newBufferData, o), mload(add(bufferData, o)))
                            o := add(o, w) // `sub(o, 0x20)`.
                            if iszero(o) { break }
                        }
                    // Store the `capacity` multiplied by `prime` in the word before the `length`.
                        mstore(add(newBufferData, w), mul(prime, newCapacity))
                    // Assign `newBufferData` to `bufferData`.
                        bufferData := newBufferData
                        break
                    }
                // Expand the memory.
                    mstore(0x40, add(bufferData, add(0x40, newCapacity)))
                // Store the `capacity` multiplied by `prime` in the word before the `length`.
                    mstore(add(bufferData, w), mul(prime, newCapacity))
                    break
                }
            // Initalize `output` to the next empty position in `bufferData`.
                let output := add(bufferData, bufferDataLength)
            // Copy `data` one word at a time, backwards.
                for { let o := and(add(mload(data), 32), w) } 1 {} {
                    mstore(add(output, o), mload(add(data, o)))
                    o := add(o, w) // `sub(o, 0x20)`.
                    if iszero(o) { break }
                }
            // Zeroize the word after the buffer.
                mstore(add(add(bufferData, 0x20), newBufferDataLength), 0)
            // Store the `newBufferDataLength`.
                mstore(bufferData, newBufferDataLength)
            }
        }
        return buffer;
    }
    /*
        /// @dev Appends `data0`, `data1` to `buffer`.
    /// Returns the same buffer, so that it can be used for function chaining.
    function append(DynamicBuffer memory buffer, bytes memory data0, bytes memory data1)
    internal
    pure
    returns (DynamicBuffer memory)
    {
        return append(append(buffer, data0), data1);
    }
*/
    /// @dev Appends `data0`, `data1`, `data2` to `buffer`.
    /// Returns the same buffer, so that it can be used for function chaining.
    function append(
        DynamicBuffer memory buffer,
        bytes memory data0,
        bytes memory data1,
        bytes memory data2
    ) internal pure returns (DynamicBuffer memory) {
        return append(append(append(buffer, data0), data1), data2);
    }
    /*

        /// @dev Appends `data0`, `data1`, `data2`, `data3` to `buffer`.
    /// Returns the same buffer, so that it can be used for function chaining.
    function append(
        DynamicBuffer memory buffer,
        bytes memory data0,
        bytes memory data1,
        bytes memory data2,
        bytes memory data3
    ) internal pure returns (DynamicBuffer memory) {
        return append(append(append(append(buffer, data0), data1), data2), data3);
    }

    /// @dev Appends `data0`, `data1`, `data2`, `data3`, `data4` to `buffer`.
    /// Returns the same buffer, so that it can be used for function chaining.
    function append(
        DynamicBuffer memory buffer,
        bytes memory data0,
        bytes memory data1,
        bytes memory data2,
        bytes memory data3,
        bytes memory data4
    ) internal pure returns (DynamicBuffer memory) {
        append(append(append(append(buffer, data0), data1), data2), data3);
        return append(buffer, data4);
    }

    /// @dev Appends `data0`, `data1`, `data2`, `data3`, `data4`, `data5` to `buffer`.
    /// Returns the same buffer, so that it can be used for function chaining.
    function append(
        DynamicBuffer memory buffer,
        bytes memory data0,
        bytes memory data1,
        bytes memory data2,
        bytes memory data3,
        bytes memory data4,
        bytes memory data5
    ) internal pure returns (DynamicBuffer memory) {
        append(append(append(append(buffer, data0), data1), data2), data3);
        return append(append(buffer, data4), data5);
    }

    /// @dev Appends `data0`, `data1`, `data2`, `data3`, `data4`, `data5`, `data6` to `buffer`.
    /// Returns the same buffer, so that it can be used for function chaining.
    function append(
        DynamicBuffer memory buffer,
        bytes memory data0,
        bytes memory data1,
        bytes memory data2,
        bytes memory data3,
        bytes memory data4,
        bytes memory data5,
        bytes memory data6
    ) internal pure returns (DynamicBuffer memory) {
        append(append(append(append(buffer, data0), data1), data2), data3);
        return append(append(append(buffer, data4), data5), data6);
    }
    */
}

/**
 * @dev Provides a set of functions to operate with Base64 strings.
 *
 * _Available since v4.5._
 */
library Base64 {
    /**
     * @dev Base64 Encoding/Decoding Table
     */
    string internal constant _TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    /**
     * @dev Converts a `bytes` to its Bytes64 `string` representation.
     */
    function encode(bytes memory data) internal pure returns (string memory) {
        /**
         * Inspired by Brecht Devos (Brechtpd) implementation - MIT licence
         * https://github.com/Brechtpd/base64/blob/e78d9fd951e7b0977ddca77d92dc85183770daf4/base64.sol
         */
        if (data.length == 0) return "";

        // Loads the table into memory
        string memory table = _TABLE;

        // Encoding takes 3 bytes chunks of binary data from `bytes` data parameter
        // and split into 4 numbers of 6 bits.
        // The final Base64 length should be `bytes` data length multiplied by 4/3 rounded up
        // - `data.length + 2`  -> Round up
        // - `/ 3`              -> Number of 3-bytes chunks
        // - `4 *`              -> 4 characters for each chunk
        string memory result = new string(4 * ((data.length + 2) / 3));

        /// @solidity memory-safe-assembly
        assembly {
        // Prepare the lookup table (skip the first "length" byte)
            let tablePtr := add(table, 1)

        // Prepare result pointer, jump over length
            let resultPtr := add(result, 32)

        // Run over the input, 3 bytes at a time
            for {
                let dataPtr := data
                let endPtr := add(data, mload(data))
            } lt(dataPtr, endPtr) {

            } {
            // Advance 3 bytes
                dataPtr := add(dataPtr, 3)
                let input := mload(dataPtr)

            // To write each character, shift the 3 bytes (18 bits) chunk
            // 4 times in blocks of 6 bits for each character (18, 12, 6, 0)
            // and apply logical AND with 0x3F which is the number of
            // the previous character in the ASCII table prior to the Base64 Table
            // The result is then added to the table to get the character to write,
            // and finally write it in the result pointer but with a left shift
            // of 256 (1 byte) - 8 (1 ASCII char) = 248 bits

                mstore8(resultPtr, mload(add(tablePtr, and(shr(18, input), 0x3F))))
                resultPtr := add(resultPtr, 1) // Advance

                mstore8(resultPtr, mload(add(tablePtr, and(shr(12, input), 0x3F))))
                resultPtr := add(resultPtr, 1) // Advance

                mstore8(resultPtr, mload(add(tablePtr, and(shr(6, input), 0x3F))))
                resultPtr := add(resultPtr, 1) // Advance

                mstore8(resultPtr, mload(add(tablePtr, and(input, 0x3F))))
                resultPtr := add(resultPtr, 1) // Advance
            }

        // When data `bytes` is not exactly 3 bytes long
        // it is padded with `=` characters at the end
            switch mod(mload(data), 3)
            case 1 {
                mstore8(sub(resultPtr, 1), 0x3d)
                mstore8(sub(resultPtr, 2), 0x3d)
            }
            case 2 {
                mstore8(sub(resultPtr, 1), 0x3d)
            }
        }

        return result;
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

interface IPunkIdenticons {
    function pick(
        address _a,
        uint64 _cid) view external returns (bytes32[] memory);

}

interface IPunkBlocks {
    function svgFromKeys(
        bytes32[] calldata _attributeKeys,
        uint16 _x,
        uint16 _y,
        uint16 _size,
        uint32 _orderID) external view returns (string memory);
}

interface IBarcode {
    function draw(
        uint256 _in,
        string memory _x,
        string memory _y,
        string memory _color,
        uint16 _height,
        uint8 _barWidth) view external returns (string memory);
}