pragma solidity ^0.8.17;

import "./harberger.sol";

//import "./safemath.sol";
import "hardhat/console.sol";



/// todo: test id 79233663829379634837589865448569342784712482819484549289560981379859480642508 (vitalik.eth)
// 0xaf2caa1c2ca1d027f1ac823b529d0a67cd144264b2789fa2ea4d63a67c7103cc

// tycoon.eth 91619853155866335512671285861854665742416064493353485516078172342642102520950
// reverse node: 0x5b411af53442b08a2eac0b3cd480bbbdc7ca33e90b48f5397324c76fc4106114

// content hash js library https://github.com/ensdomains/content-hash
// other ways, including sub-graph https://docs.ens.domains/dapp-developer-guide/resolving-names

//  // namehash('addr.reverse')
//    bytes32 public constant ADDR_REVERSE_NODE = 0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2;

// namehash('.eth)
// 0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae

// namehash calc https://swolfeyes.github.io/ethereum-namehash-calculator/
// tycoon eth: 0x3678407b1945d4c1f020cf2b02f05e8650ee554c21814f1e20055c3f42bda46f
contract ENSReg {
    IENSResolver public r;
    constructor (address _r) {
        r = IENSResolver(_r);
    }
    function resolver(bytes32 node) public virtual view returns (IENSResolver) {
        return r;
    }
}

contract ENSResolver {
    function addr(bytes32 node) public virtual view returns (address) {
        return (address(0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045));
    }
    /**
     * @dev Reclaim ownership of a name in ENS, if you own it in the registrar.
     */
    function reclaim(uint256 id, address owner) external {
        console.log("reclaim ens", id, owner);
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

// this will be used to check to see if:
// given .eth name resolved address == reverse address(msg.sender)
contract ENSReverseResolverMock {

    // real one at https://etherscan.io/address/0xa2c122be93b0074270ebee7f6b7292c7deb45047#code
    bytes32 public constant ADDR_REVERSE_NODE = 0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2;


    function node(address addr) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(ADDR_REVERSE_NODE, sha3HexAddress(addr)));
    }

    /**
     * @dev An optimised function to compute the sha3 of the lower-case
     *      hexadecimal representation of an Ethereum address.
     * @param addr The address to hash
     * @return ret The SHA3 hash of the lower-case hexadecimal encoding of the
     *         input address.
     */
    function sha3HexAddress(address addr) private pure returns (bytes32 ret) {
        addr;
        ret; // Stop warning us about unused variables
        assembly {
            let lookup := 0x3031323334353637383961626364656600000000000000000000000000000000

            for { let i := 40 } gt(i, 0) { } {
                i := sub(i, 1)
                mstore8(i, byte(and(addr, 0xf), lookup))
                addr := div(addr, 0x10)
                i := sub(i, 1)
                mstore8(i, byte(and(addr, 0xf), lookup))
                addr := div(addr, 0x10)
            }

            ret := keccak256(0, 40)
        }
    }

    function setName(bytes32 node, string memory name) external {
        // all it does is just
        //name[node] = _name;
    }


}