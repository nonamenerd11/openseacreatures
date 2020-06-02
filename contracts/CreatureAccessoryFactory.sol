pragma solidity ^0.5.11;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";
import "./IFactory.sol";
import "./ERC1155Tradable.sol";
import "./Strings.sol";

/**
 * @title CreatureAccessoryFactory
 * CreatureAccessory - a factory contract for Creature Accessory semi-fungible
 * tokens.
 */
contract CreatureAccessoryFactory is IFactory, Ownable, ReentrancyGuard {
  using Strings for string;
  using SafeMath for uint256;

  address public proxyRegistryAddress;
  address public nftAddress;
  address public lootBoxAddress;
  string constant internal baseMetadataURI = "https://creatures-api.opensea.io/api/";
  uint256 constant UINT256_MAX = ~uint256(0);

  /**
   * Optionally set this to a small integer to enforce limited existence per option/token ID
   * (Otherwise rely on sell orders on OpenSea, which can only be made by the factory owner.)
   */
  uint256 constant SUPPLY_PER_TOKEN_ID = UINT256_MAX;

  // The number of creature accessories (not creature accessory rarity classes!)
  uint256 constant NUM_ITEM_OPTIONS = 6;

  /**
   * Three different options for minting CreatureAccessories (basic, premium, and gold).
   */
  uint256 constant public BASIC_LOOTBOX = NUM_ITEM_OPTIONS + 0;
  uint256 constant public PREMIUM_LOOTBOX = NUM_ITEM_OPTIONS + 1;
  uint256 constant public GOLD_LOOTBOX = NUM_ITEM_OPTIONS + 2;
  uint256 constant public NUM_LOOTBOX_OPTIONS = 3;

  uint256 constant public NUM_OPTIONS = NUM_ITEM_OPTIONS + NUM_LOOTBOX_OPTIONS;

  constructor(
    address _proxyRegistryAddress,
    address _nftAddress,
    address _lootBoxAddress
  ) public {
    proxyRegistryAddress = _proxyRegistryAddress;
    nftAddress = _nftAddress;
    lootBoxAddress = _lootBoxAddress;
  }

  /////
  // FACTORY INTERFACE METHODS
  /////

  function name() external view returns (string memory) {
    return "OpenSea Creature Accessory Pre-Sale";
  }

  function symbol() external view returns (string memory) {
    return "OSCAP";
  }

  function supportsFactoryInterface() external view returns (bool) {
    return true;
  }

  function factorySchemaName() external view returns (string memory) {
    return "ERC1155";
  }

  function numOptions() external view returns (uint256) {
    return NUM_LOOTBOX_OPTIONS + NUM_ITEM_OPTIONS;
  }

  function uri(uint256 _optionId) external view returns (string memory) {
    return Strings.strConcat(
      baseMetadataURI,
      "factory/",
      Strings.uint2str(_optionId)
    );
  }

  function canMint(uint256 _optionId, uint256 _amount) external view returns (bool) {
    return _canMint(msg.sender, _optionId, _amount);
  }

  function mint(uint256 _optionId, address _toAddress, uint256 _amount, bytes calldata _data) external nonReentrant() {
    return _mint(_optionId, _toAddress, _amount, _data);
  }

  /**
   * @dev Main minting logic implemented here!
   */
  function _mint(
    uint256 _option,
    address _toAddress,
    uint256 _amount,
    bytes memory _data
  ) internal {
    require(_canMint(msg.sender, _option, _amount), "CreatureAccessoryFactory#_mint: CANNOT_MINT_MORE");
    if (_option < NUM_ITEM_OPTIONS) {
      require(
        _isOwnerOrProxy(msg.sender) || msg.sender == lootBoxAddress,
        "Caller cannot mint accessories"
      );
      // Option IDs start at 0, Token IDs start at 1
      uint256 tokenId = _option + 1;
      // Items are pre-mined (by the owner), so transfer them (We are an
      // operator for the owner).
      ERC1155Tradable items = ERC1155Tradable(nftAddress);
      items.safeTransferFrom(owner(), _toAddress, tokenId, _amount, _data);
    } else if (_option < NUM_OPTIONS) {
      require(_isOwnerOrProxy(msg.sender), "Caller cannot mint boxes");
      uint256 lootBoxOption = _option - NUM_ITEM_OPTIONS;
      uint256 lootBoxTokenId = lootBoxOption + 1;
      // LootBoxes are not premined, so we need to create or mint them.
      _createOrMint(lootBoxAddress, _toAddress, lootBoxTokenId, _amount, _data);
    } else {
      revert("Unknown _option");
    }
  }

  /*
   * Note: make sure code that calls this is non-reentrant.
   * Note: this is the token _id *within* the ERC1155 contract, not the option
   *       id from this contract.
   */
  function _createOrMint (address _erc1155Address, address _to, uint256 _id, uint256 _amount, bytes memory _data)
  internal {
    ERC1155Tradable tradable = ERC1155Tradable(_erc1155Address);
    // Lazily create the token
    if (! tradable.exists(_id)) {
      tradable.create(_to, _id, _amount, "", _data);
    } else {
      tradable.mint(_to, _id, _amount, _data);
    }
  }

  /**
   * Get the factory's ownership of Option.
   * Should be the amount it can still mint.
   * NOTE: Called by `canMint`
   */
  function balanceOf(
    address _owner,
    uint256 _optionId
  ) public view returns (uint256) {
    if ( _optionId < NUM_ITEM_OPTIONS) {
      if ((!_isOwnerOrProxy(_owner)) && _owner != lootBoxAddress) {
        // Only the factory's owner or owner's proxy,
        // or the lootbox can have supply
        return 0;
      }
      // The pre-minted balance belongs to the address that minted this contract
      uint256 tokenId = _optionId + 1;
      ERC1155Tradable lootBox = ERC1155Tradable(nftAddress);
      uint256 currentSupply = lootBox.balanceOf(owner(), tokenId);
      return currentSupply;
    } else {
      if (!_isOwnerOrProxy(_owner)) {
        // Only the factory owner or owner's proxy can have supply
        return 0;
      }
      // We can mint up to a balance of SUPPLY_PER_TOKEN_ID
      uint256 tokenId = (_optionId + 1 - NUM_ITEM_OPTIONS);
      ERC1155Tradable lootBox = ERC1155Tradable(lootBoxAddress);
      uint256 currentSupply = lootBox.totalSupply(tokenId);
      return SUPPLY_PER_TOKEN_ID.sub(currentSupply);
    }
  }

  function _canMint(
    address _fromAddress,
    uint256 _optionId,
    uint256 _amount
  ) internal view returns (bool) {
    return _amount > 0 && balanceOf(_fromAddress, _optionId) >= _amount;
  }

  function _isOwnerOrProxy(
    address _address
  ) internal view returns (bool) {
    ProxyRegistry proxyRegistry = ProxyRegistry(proxyRegistryAddress);
    return owner() == _address || address(proxyRegistry.proxies(owner())) == _address;
  }
}
