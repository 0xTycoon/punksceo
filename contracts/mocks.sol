// SPDX-License-Identifier: MIT
// Author: 0xTycoon
// Repo: github.com/0xTycoon/punksceo

pragma solidity ^0.8.10;

import "./oldcig.sol";

//import "./safemath.sol";
import "hardhat/console.sol";
// a mock contract used for testing
contract PunkMock {

    address tester;

    function punkIndexToAddress(uint256 punkIndex) external returns (address) {
        if ((punkIndex != 4513) && (punkIndex != 4514) && (punkIndex != 4515) && (punkIndex != 4519)) {
            return address(0);
        }
        return tester;
    }
    constructor(address _addr) {
        tester = _addr;
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
