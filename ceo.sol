pragma solidity ^0.7.6;

import "./safemath.sol";

/**
* "Non fungible CEO"
* This is a NFT that gets transferred to the address that hold the CEO title.
* Think of it as a "title belt" in boxing.
* The purpose is so that the NFT will show up in CEOs gallery, so that everyone will be able to see it!
*
* Properties:
* - There is only 1 NFT, NFT ID is 0
* - Only the CIG token contract has permission to transfer it
* - Admin key only used for deployment
*
*/
contract NonFungibleCEO {
    address private cigToken;
    address public admin;
    string private assetURL;
    constructor() {
        admin = msg.sender;
    }
    modifier onlyAdmin {
        require(
            msg.sender == admin,
            "only admin can call this"
        );
        _;
    }
    function _onlyCig() internal view {
        require(cigToken == msg.sender, 'must be called from cigtoken');
    }
    /**
    * @dev burnAdmin burns the admin key
    */
    function burnAdmin() external onlyAdmin {
        admin = 0x0000000000000000000000000000000000000000;
    }
    /**
    * @dev setCigToken sets the address to the cig token
    * @param _addr address to the cig token
    */
    function setCigToken(address _addr) external onlyAdmin {
        cigToken = _addr;
    }

    function setAssetURL(string memory _url) external onlyAdmin {
        assetURL = _url;
    }

    /***
    * ERC721 stuff
    */
    address private holder; // the NFT owner
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function totalSupply() external view returns (uint256) {
        return 1;
    }

    function tokenByIndex(uint256 _index) external view returns (uint256) {
        if (_index == 0) {return 0; }
        revert("404");
    }

    function tokenOfOwnerByIndex(address _owner, uint256 _index) external view returns (uint256) {
        if (_owner == holder) {
            return 0;
        }
        revert("404");
    }

    function balanceOf(address _holder) public view returns (uint256) {
        if (_holder == holder) {
            return 1;
        }
        return 0;
    }

    function name() public view returns (string memory) {
        return "CEO of Cryptopunks";
    }

    function symbol() public view returns (string memory) {
        return "PNKCEO";
    }

    function tokenURI(uint256 _tokenId) public view returns (string memory) {
        if (_tokenId != 0) revert("404");
        return assetURL;
    }

    function _baseURI() internal view virtual returns (string memory) {
        return "";
    }

    function ownerOf(uint256 _tokenId) public view returns (address) {
        if (_tokenId != 0) revert("404");
        return holder;
    }

    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes memory data) external {
        _onlyCig();
        _transfer(_from, _to, _tokenId);
    }

    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external {
        _onlyCig();
        _transfer(_from, _to, _tokenId);
    }

    function transferFrom(address _from, address _to, uint256 _tokenId) external {
        _onlyCig();
        _transfer(_from, _to, _tokenId);
    }

    function approve(address _approved, uint256 _tokenId) external {
        _onlyCig();
    }

    function setApprovalForAll(address _operator, bool _approved) external {
        _onlyCig();
    }

    function getApproved(uint256 _tokenId) public view returns (address) {
        _onlyCig();
        return address(0);
    }

    function isApprovedForAll(address _owner, address _operator) public view returns (bool) {
        _onlyCig();
        return false;
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return
        interfaceId == type(IERC721).interfaceId ||
        interfaceId == type(IERC721Metadata).interfaceId ||
        interfaceId == type(IERC165).interfaceId ||
        interfaceId == type(ERC721Enumerable).interfaceId ||
        interfaceId == type(ERC721TokenReceiver).interfaceId;
    }

    function _transfer(address _from, address _to, uint256 _tokenId) internal {
        require(_tokenId == 0, "404");
        //balances[_from] -= 1; // there are no other holders, see balanceOf implementation
        //_balances[_to] += 1;
        holder = _to;
        emit Transfer(_from, _to, _tokenId);
    }

    function onERC721Received(address _operator, address _from, uint256 _tokenId, bytes memory _data) external returns (bytes4) {
        revert("nope");
        return bytes4(keccak256("nope"));
    }


}


/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}


/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721 is IERC165 {
    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be have been allowed to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {safeTransferFrom} whenever possible.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /**
     * @dev Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) external;

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the caller.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool _approved) external;

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;
}

/**
 * @title ERC-721 Non-Fungible Token Standard, optional metadata extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721Metadata is IERC721 {
    /**
     * @dev Returns the token collection name.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the token collection symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

interface ERC721TokenReceiver {
    /// @notice Handle the receipt of an NFT
    /// @dev The ERC721 smart contract calls this function on the
    /// recipient after a `transfer`. This function MAY throw to revert and reject the transfer. Return
    /// of other than the magic value MUST result in the transaction being reverted.
    /// @notice The contract address is always the message sender.
    /// @param _operator The address which called `safeTransferFrom` function
    /// @param _from The address which previously owned the token
    /// @param _tokenId The NFT identifier which is being transferred
    /// @param _data Additional data with no specified format
    /// @return `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
    /// unless throwing
    function onERC721Received(address _operator, address _from, uint256 _tokenId, bytes memory _data) external returns (bytes4);
}

/// @title ERC-721 Non-Fungible Token Standard, optional enumeration extension
/// @dev See https://eips.ethereum.org/EIPS/eip-721
///  Note: the ERC-165 identifier for this interface is 0x780e9d63.
interface ERC721Enumerable /* is ERC721 */ {
    /// @notice Count NFTs tracked by this contract
    /// @return A count of valid NFTs tracked by this contract, where each one of
    ///  them has an assigned and queryable owner not equal to the zero address
    function totalSupply() external view returns (uint256);

    /// @notice Enumerate valid NFTs
    /// @dev Throws if `_index` >= `totalSupply()`.
    /// @param _index A counter less than `totalSupply()`
    /// @return The token identifier for the `_index`th NFT,
    ///  (sort order not specified)
    function tokenByIndex(uint256 _index) external view returns (uint256);

    /// @notice Enumerate NFTs assigned to an owner
    /// @dev Throws if `_index` >= `balanceOf(_owner)` or if
    ///  `_owner` is the zero address, representing invalid NFTs.
    /// @param _owner An address where we are interested in NFTs owned by them
    /// @param _index A counter less than `balanceOf(_owner)`
    /// @return The token identifier for the `_index`th NFT assigned to `_owner`,
    ///   (sort order not specified)
    function tokenOfOwnerByIndex(address _owner, uint256 _index) external view returns (uint256);
}
