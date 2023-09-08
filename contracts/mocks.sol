// SPDX-License-Identifier: MIT
// Author: 0xTycoon
// Repo: github.com/0xTycoon/punksceo

pragma solidity ^0.8.10;

import "./oldcig.sol";

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

contract CryptoPunksTokenURIMock {
    // simulate 0x4e776fCbb241a0e0Ea2904d642baa4c7E171a1E9

    function tokenURI(uint256 _tokenId) external view returns (string memory) {
        require(_tokenId < 10000, "invalid _tokenId");

        return string(abi.encodePacked("data:application/json;base64,",
            encode(
                abi.encodePacked(
                    '{\n"description": "CryptoPunks launched as a fixed set of 10,000 items in mid-2017 and became one of the inspirations for the ERC-721 standard. They have been featured in places like The New York Times, Christies of London, Art|Basel Miami, and The PBS NewsHour.",',
                    '"external_url": "https://cryptopunks.app/cryptopunks/details/',intToString(_tokenId),'",',
                    '"image": "data:image/svg+xml;base64,', encode(bytes('<svg width="300" height="300" viewBox="0 0 300 300" fill="none" xmlns="http://www.w3.org/2000/svg"><circle cx="150" cy="150" r="150" fill="url(#paint0_linear_609_349)"/> <circle cx="150" cy="150" r="140" fill="url(#paint1_linear_609_349)"/><rect x="76" y="182" width="131" height="22" fill="black"/> <rect x="76" y="204" width="108" height="22" fill="white"/> <rect x="184" y="204" width="23" height="22" fill="#E25B26"/> <rect x="76" y="226" width="131" height="22" fill="black"/> <rect x="207" y="204" width="24" height="22" fill="black"/> <rect x="184" y="26" width="21" height="132" fill="#FCF7D6"/> <defs> <linearGradient id="paint0_linear_609_349" x1="150" y1="0" x2="150" y2="300" gradientUnits="userSpaceOnUse"> <stop stop-color="#F08710"/> <stop offset="1" stop-color="#F96D36"/> </linearGradient> <linearGradient id="paint1_linear_609_349" x1="150" y1="10" x2="150" y2="290" gradientUnits="userSpaceOnUse"> <stop stop-color="#F0870D"/> <stop offset="1" stop-color="#F09A39"/> </linearGradient> </defs> </svg>')), '",',
                    '"name": "CryptoPunk #',intToString(_tokenId),'",',
                    '"attributes": [{"trait_type":"Type","value":"Male 2"},{"trait_type":"Accessory","value":"Buck Teeth"},{"trait_type":"Accessory","value":"Mole"},{"trait_type":"Accessory","value":"Big Beard"},{"trait_type":"Accessory","value":"Earring"},{"trait_type":"Accessory","value":"Top Hat"},{"trait_type":"Accessory","value":"Cigarette"},{"trait_type":"Accessory","value":"Classic Shades"}]', "\n}"
                )
            )
            ));
    }

    function intToString(uint256 value) public pure returns (string memory) {
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

    // OZ base64 library
    string internal constant _TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    function encode(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";

        // Loads the table into memory
        string memory table = _TABLE;
        string memory result = new string(4 * ((data.length + 2) / 3));

        /// @solidity memory-safe-assembly
        assembly {
            let tablePtr := add(table, 1)
            let resultPtr := add(result, 32)
            for {
                let dataPtr := data
                let endPtr := add(data, mload(data))
            } lt(dataPtr, endPtr) {
            } {
            // Advance 3 bytes
                dataPtr := add(dataPtr, 3)
                let input := mload(dataPtr)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(18, input), 0x3F))))
                resultPtr := add(resultPtr, 1) // Advance
                mstore8(resultPtr, mload(add(tablePtr, and(shr(12, input), 0x3F))))
                resultPtr := add(resultPtr, 1) // Advance
                mstore8(resultPtr, mload(add(tablePtr, and(shr(6, input), 0x3F))))
                resultPtr := add(resultPtr, 1) // Advance
                mstore8(resultPtr, mload(add(tablePtr, and(input, 0x3F))))
                resultPtr := add(resultPtr, 1) // Advance
            }
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



