// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IComputeOption} from "./interfaces/IComputeOption.sol";
import {IComputeOptionVault} from "./interfaces/IComputeOptionVault.sol";

/**
 * @title ComputeOption
 * @notice Weekly ERC-1155 grid for hourly RTX 5090 compute call options.
 * @dev Each token ID identifies one strike row and one hour in the week after expiry.
 */
contract ComputeOption is ERC1155, IComputeOption, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    string private constant GPU_MODEL = "NVIDIA GeForce RTX 5090 Desktop";
    uint16 private constant GPU_VRAM_GB = 32;
    uint256 private constant SLOT_DURATION = 1 hours;
    uint256 private constant SLOT_COUNT = 168;

    struct MintPosition {
        address provider;
        uint256 tokenId;
        uint256 units;
        uint256 bondPerUnit;
        uint256 assignedUnits;
        bool released;
    }

    struct Claim {
        address exerciser;
        address provider;
        uint256 tokenId;
        uint256 positionId;
        uint256 strike;
    }

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    Grade private immutable GRADE;
    uint64 private immutable EXPIRY;
    address private immutable CREATOR;
    address private immutable USDC;
    IComputeOptionVault private immutable VAULT;

    uint256[] private _strikePrices;
    uint256 public override nextPositionId;
    uint256 public override nextClaimId;
    mapping(uint256 positionId => MintPosition) public override mintPositions;
    mapping(uint256 claimId => Claim) public override claims;
    mapping(uint256 tokenId => uint256[] positionIds) private _positionIdsByToken;
    mapping(uint256 tokenId => uint256 nextIndex) private _nextAssignmentIndex;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the market's fixed terms and ERC-1155 metadata URI.
     * @param grade_ Supporting compute grade.
     * @param expiry_ Monday 00:00 UTC expiry and start of the delivery week.
     * @param creator_ Account that created the weekly grid.
     * @param usdc_ USDC token used for strike prices and order book quotes.
     * @param vault_ Vault authorized to lock provider USDC for this market.
     * @param strikePrices_ Strictly increasing strike prices in USDC base units.
     * @param metadataUri_ ERC-1155 metadata URI, optionally containing `{id}`.
     */
    constructor(
        Grade grade_,
        uint64 expiry_,
        address creator_,
        address usdc_,
        address vault_,
        uint256[] memory strikePrices_,
        string memory metadataUri_
    ) ERC1155(metadataUri_) {
        if (strikePrices_.length == 0) revert InvalidStrikePrices();
        uint256 previous;
        for (uint256 i; i < strikePrices_.length; ++i) {
            if (strikePrices_[i] <= previous) revert InvalidStrikePrices();
            previous = strikePrices_[i];
        }

        GRADE = grade_;
        EXPIRY = expiry_;
        CREATOR = creator_;
        USDC = usdc_;
        VAULT = IComputeOptionVault(vault_);
        _strikePrices = strikePrices_;
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Reports support for the compute option interface and inherited ERC-1155 interfaces.
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, IERC165) returns (bool) {
        return interfaceId == type(IComputeOption).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @inheritdoc IComputeOption
     */
    function gpuModel() external pure override returns (string memory) {
        return GPU_MODEL;
    }

    /**
     * @inheritdoc IComputeOption
     */
    function gpuVramGb() external pure override returns (uint16) {
        return GPU_VRAM_GB;
    }

    /**
     * @inheritdoc IComputeOption
     */
    function slotDuration() external pure override returns (uint256) {
        return SLOT_DURATION;
    }

    /**
     * @inheritdoc IComputeOption
     */
    function slotCount() external pure override returns (uint256) {
        return SLOT_COUNT;
    }

    /**
     * @inheritdoc IComputeOption
     */
    function strikeCount() external view override returns (uint256) {
        return _strikePrices.length;
    }

    /**
     * @inheritdoc IComputeOption
     */
    function seriesCount() external view override returns (uint256) {
        return _strikePrices.length * SLOT_COUNT;
    }

    /**
     * @inheritdoc IComputeOption
     */
    function grade() external view override returns (Grade) {
        return GRADE;
    }

    /**
     * @inheritdoc IComputeOption
     */
    function expiry() external view override returns (uint64) {
        return EXPIRY;
    }

    /**
     * @inheritdoc IComputeOption
     */
    function creator() external view override returns (address) {
        return CREATOR;
    }

    /**
     * @inheritdoc IComputeOption
     */
    function paymentToken() external view override returns (address) {
        return USDC;
    }

    /**
     * @inheritdoc IComputeOption
     */
    function collateralVault() external view override returns (address) {
        return address(VAULT);
    }

    /**
     * @inheritdoc IComputeOption
     */
    function strikePriceAt(uint256 strikeIndex) external view override returns (uint256) {
        if (strikeIndex >= _strikePrices.length) revert InvalidStrikeIndex(strikeIndex);
        return _strikePrices[strikeIndex];
    }

    /**
     * @inheritdoc IComputeOption
     */
    function strikePrice(uint256 tokenId) external view override returns (uint256) {
        if (tokenId >= _strikePrices.length * SLOT_COUNT) revert InvalidTokenId(tokenId);
        return _strikePrices[tokenId / SLOT_COUNT];
    }

    /**
     * @inheritdoc IComputeOption
     */
    function tokenIdFor(uint256 strikeIndex, uint256 hourIndex) external view override returns (uint256) {
        if (strikeIndex >= _strikePrices.length) revert InvalidStrikeIndex(strikeIndex);
        if (hourIndex >= SLOT_COUNT) revert InvalidHourIndex(hourIndex);
        return strikeIndex * SLOT_COUNT + hourIndex;
    }

    /**
     * @inheritdoc IComputeOption
     */
    function slotStart(uint256 tokenId) public view override returns (uint256) {
        if (tokenId >= _strikePrices.length * SLOT_COUNT) revert InvalidTokenId(tokenId);
        return uint256(EXPIRY) + (tokenId % SLOT_COUNT) * SLOT_DURATION;
    }

    /**
     * @inheritdoc IComputeOption
     */
    function slotEnd(uint256 tokenId) external view override returns (uint256) {
        return slotStart(tokenId) + SLOT_DURATION;
    }

    /**
     * @inheritdoc IComputeOption
     */
    function deliveryEnd() external view override returns (uint256) {
        return uint256(EXPIRY) + 1 weeks;
    }

    /*//////////////////////////////////////////////////////////////
                             MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IComputeOption
     */
    function mintOptions(uint256 tokenId, uint256 units, uint256 bondPerUnit)
        external
        override
        nonReentrant
        returns (uint256 positionId)
    {
        if (block.timestamp >= EXPIRY) revert OptionExpired();
        if (tokenId >= _strikePrices.length * SLOT_COUNT) revert InvalidTokenId(tokenId);
        if (units == 0 || bondPerUnit == 0) revert InvalidMintTerms();

        positionId = ++nextPositionId;
        VAULT.lock(msg.sender, positionId, units * bondPerUnit);
        mintPositions[positionId] = MintPosition({
            provider: msg.sender,
            tokenId: tokenId,
            units: units,
            bondPerUnit: bondPerUnit,
            assignedUnits: 0,
            released: false
        });
        _positionIdsByToken[tokenId].push(positionId);
        _mint(msg.sender, tokenId, units, "");
        emit OptionsMinted(positionId, msg.sender, tokenId, units, bondPerUnit);
    }

    /**
     * @inheritdoc IComputeOption
     */
    function exercise(uint256 tokenId) external override nonReentrant returns (uint256 claimId) {
        if (block.timestamp >= EXPIRY) revert OptionExpired();
        if (tokenId >= _strikePrices.length * SLOT_COUNT) revert InvalidTokenId(tokenId);

        uint256[] storage positionIds = _positionIdsByToken[tokenId];
        uint256 index = _nextAssignmentIndex[tokenId];
        while (
            index < positionIds.length
                && mintPositions[positionIds[index]].assignedUnits == mintPositions[positionIds[index]].units
        ) {
            ++index;
        }
        if (index == positionIds.length) revert NoProviderPosition(tokenId);
        uint256 positionId = positionIds[index];
        MintPosition storage position = mintPositions[positionId];
        position.assignedUnits += 1;
        if (position.assignedUnits == position.units) _nextAssignmentIndex[tokenId] = index + 1;

        uint256 strike = _strikePrices[tokenId / SLOT_COUNT];
        _burn(msg.sender, tokenId, 1);
        IERC20(USDC).safeTransferFrom(msg.sender, address(this), strike);

        claimId = ++nextClaimId;
        claims[claimId] = Claim({
            exerciser: msg.sender, provider: position.provider, tokenId: tokenId, positionId: positionId, strike: strike
        });
        emit OptionExercised(claimId, tokenId, msg.sender, position.provider);
    }

    /**
     * @inheritdoc IComputeOption
     */
    function releaseExpiredPosition(uint256 positionId) external override nonReentrant {
        if (block.timestamp < EXPIRY) revert OptionNotExpired();
        MintPosition storage position = mintPositions[positionId];
        if (position.provider == address(0)) revert PositionNotFound(positionId);
        if (position.released) revert PositionAlreadyReleased(positionId);
        position.released = true;
        uint256 unassigned = position.units - position.assignedUnits;
        if (unassigned != 0) VAULT.release(positionId, unassigned * position.bondPerUnit);
        emit ExpiredPositionReleased(positionId, position.provider);
    }
}
