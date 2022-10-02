// SPDX-License-Identifier: MIT
// Author: 0xTycoon
// Repo: github.com/0xTycoon/punksceo

pragma solidity ^0.8.10;

import "./oldcig.sol";

//import "./safemath.sol";
import "hardhat/console.sol";
// a mock contract used for testing
contract PunkMock {

    struct Offer {
        uint256 minSalePriceInWei;
        address toAddress;
    }
    mapping(uint256 => address) private registry; // ownership registry
    mapping(uint256 => Offer) private offers;

    event PunkBought(uint indexed punkIndex, uint value, address indexed fromAddress, address indexed toAddress);
    event PunkOffered(uint indexed punkIndex, uint minValue, address indexed toAddress);
    function punkIndexToAddress(uint256 punkIndex) external returns (address) {
        return registry[punkIndex];
    }
    constructor(address _addr1, address _addr2, address _addr3) {
        registry[4513] = _addr1;
        registry[4514] = _addr1;
        registry[4515] = _addr2;
        registry[4519] = _addr2;
        registry[4520] = _addr2;
        registry[4001] = _addr3;
    }

    function offerPunkForSaleToAddress(uint punkIndex, uint minSalePriceInWei, address toAddress) external {
        offers[punkIndex].toAddress = toAddress;
        offers[punkIndex].minSalePriceInWei = minSalePriceInWei;
        emit PunkOffered(punkIndex, minSalePriceInWei, toAddress);
    }

    function buyPunk(uint punkIndex) external payable {
        require(offers[punkIndex].toAddress == msg.sender, "you are not the toAddress");
        address seller = registry[punkIndex];
        registry[punkIndex] = msg.sender;
        offers[punkIndex].toAddress = address(0);
        emit PunkBought(punkIndex, msg.value, seller, msg.sender);

    }

}

import "hardhat/console.sol";
// PoolTokenMock is a mock contract for testing
contract PoolTokenMock {
    //using SafeMath for uint256;
    string public name = "CIG-ETH-V2";
    string public symbol = "CIGETH";
    uint8 public decimals = 18;
    uint256 public totalSupply = 0;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(address _addr) {
        //tester = _addr;
        balanceOf[_addr] = balanceOf[_addr] + 5 ether;
        totalSupply = totalSupply + 5 ether;
    }

    function mint(address _to, uint256 _amount) public {
        totalSupply = totalSupply + _amount;
        balanceOf[_to] = balanceOf[_to] + _amount;
        emit Transfer(address(0), _to, _amount);
    }

    /**
    * @dev transfer token for a specified address
    * @param _to The address to transfer to.
    * @param _value The amount to be transferred.
    */
    function transfer(address _to, uint256 _value) public returns (bool) {
        // require(_value <= balanceOf[msg.sender], "value exceeds balance"); // SafeMath already checks this
        balanceOf[msg.sender] = balanceOf[msg.sender] - _value;
        balanceOf[_to] = balanceOf[_to] + _value;
        emit Transfer(msg.sender, _to, _value);
        return true;
    }


    /**
    * @dev Transfer tokens from one address to another
    * @param _from address The address which you want to send tokens from
    * @param _to address The address which you want to transfer to
    * @param _value uint256 the amount of tokens to be transferred
    */
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    )
    public
    returns (bool)
    {
        //require(_value <= balanceOf[_from], "value exceeds balance"); // SafeMath already checks this
        require(_value <= allowance[_from][msg.sender], "not approved");
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
    function approve(address _spender, uint256 _value) public returns (bool) {
        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
         _reserve0 = 69;
         _reserve1 = 420;
        _blockTimestampLast = 69420;
    }

}

contract V2RouterMock {
    constructor() {
    }
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) external pure returns(uint256 amountOut) {
        amountOut = 4206969;
    }
}

/**
* Mock the masterchef v2 callback
*/
contract MasterChefV2 {
    IRewarder rewarder;
    mapping(address => uint256) public balances;

    constructor() {}

    /**
    * @dev pass the address of the cig token to call back to
    * @param _rewarder address of the cig contract that implements the callback
    */
    function setRewarder(address _rewarder) external {
        rewarder = IRewarder(_rewarder);
    }

    function deposit(address _user, uint256 _amount) external {
        balances[_user] = balances[_user] + _amount;
        _simulateCallback(_user);
    }

    function withdraw(address _user, uint256 _amount) external {
        balances[_user] = balances[_user] - _amount;
        _simulateCallback(_user);
    }

    function harvest() external {
        _simulateCallback(msg.sender);
    }

    function _simulateCallback(address _user) internal {
        rewarder.onSushiReward(0, _user, _user, 10 ether, balances[_user]);
    }
}

contract ERC721Mock {
    // Just a simulation, do not use in any live code
    mapping(address => uint256) private balances;              // counts of ownership
    mapping(uint256  => address) private ownership;
    mapping(uint256  => address) private approval;
    //mapping(address => mapping(address => bool)) private approvalAll; // operator approvals

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Approval is fired when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @dev ApprovalForAll is fired when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function tokenURI(uint256 _tokenId) public view returns (string memory) {
        return ""; // todo: return uri
    }

    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes memory _data) external {
        address o = ownership[_tokenId];
        require (o == _from, "_from must be owner");
        address a = approval[_tokenId];
        require (o == msg.sender || (a == msg.sender) /* || (approvalAll[o][msg.sender])*/, "not permitted");
        balances[_to]++;
        balances[_from]--;
        ownership[_tokenId] = _to;
        emit Transfer(_from, _to, _tokenId);
    }

    function approve(address _to, uint256 _tokenId) external {
        address o = ownership[_tokenId];
        require (o == msg.sender, "action not token permitted");
        approval[_tokenId] = _to;
        emit Approval(msg.sender, _to, _tokenId);
    }
}

contract CigTokenMock {

    string public name = "Cigarettes";
    string public symbol = "CIG";
    uint8 public decimals = 18;
    uint256 public totalSupply = 0;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    address ceo;

    constructor (address _ceo) {
        ceo = _ceo;
        balanceOf[_ceo] = balanceOf[_ceo] + 5 ether;
        totalSupply = totalSupply + 5 ether;
    }
    function mint(address _to, uint256 _amount) public {
        totalSupply = totalSupply + _amount;
        balanceOf[_to] = balanceOf[_to] + _amount;
        emit Transfer(address(0), _to, _amount);
    }
    function transfer(address _to, uint256 _value) public returns (bool) {
        // require(_value <= balanceOf[msg.sender], "value exceeds balance"); // SafeMath already checks this
        balanceOf[msg.sender] = balanceOf[msg.sender] - _value;
        balanceOf[_to] = balanceOf[_to] + _value;
        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    )
    public
    returns (bool)
    {
        //require(_value <= balanceOf[_from], "value exceeds balance"); // SafeMath already checks this
        require(_value <= allowance[_from][msg.sender], "not approved");
        balanceOf[_from] = balanceOf[_from] - _value;
        balanceOf[_to] = balanceOf[_to] + _value;
        emit Transfer(_from, _to, _value);
        return true;
    }

    function approve(address _spender, uint256 _value) public returns (bool) {
        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function The_CEO() external view returns (address) {
        return ceo;
    }
    function CEO_punk_index() external view returns (uint256) {
        return 4513;
    }
    function taxBurnBlock() external view returns (uint256) {
        return block.number - 5;
    }
    function CEO_price() external view returns (uint256) {
        return 1000000 ether;
    }
}
