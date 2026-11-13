// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC1155MetadataURI} from "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";

/**
 * @title IComputeOption
 * @notice Interface for a weekly RTX 5090 option grid indexed by strike and delivery hour.
 */
interface IComputeOption is IERC1155MetadataURI {
    enum Grade {
        A,
        B,
        C
    }

    error InvalidStrikePrices();
    error InvalidTokenId(uint256 tokenId);
    error InvalidStrikeIndex(uint256 strikeIndex);
    error InvalidHourIndex(uint256 hourIndex);
    error InvalidMintTerms();
    error OptionExpired();
    error OptionNotExpired();
    error PositionNotFound(uint256 positionId);
    error PositionAlreadyReleased(uint256 positionId);
    error NoProviderPosition(uint256 tokenId);

    event OptionsMinted(
        uint256 indexed positionId,
        address indexed provider,
        uint256 indexed tokenId,
        uint256 units,
        uint256 bondPerUnit
    );
    event ExpiredPositionReleased(uint256 indexed positionId, address indexed provider);
    event OptionExercised(
        uint256 indexed claimId, uint256 indexed tokenId, address indexed exerciser, address provider
    );

    /**
     * @notice Returns the GPU model represented by this contract.
     */
    function gpuModel() external pure returns (string memory);

    /**
     * @notice Returns the GPU VRAM size in gigabytes.
     */
    function gpuVramGb() external pure returns (uint16);

    /**
     * @notice Returns the duration of one option slot in seconds.
     */
    function slotDuration() external pure returns (uint256);

    /**
     * @notice Returns the number of hourly slots in the delivery week.
     */
    function slotCount() external pure returns (uint256);

    /**
     * @notice Returns the number of strike rows in the option grid.
     */
    function strikeCount() external view returns (uint256);

    /**
     * @notice Returns the number of option series across all strikes and hours.
     */
    function seriesCount() external view returns (uint256);

    /**
     * @notice Returns the supporting compute grade.
     */
    function grade() external view returns (Grade);

    /**
     * @notice Returns the exercise expiry, which is the start of the delivery week.
     */
    function expiry() external view returns (uint64);

    /**
     * @notice Returns the account that created the weekly option grid.
     */
    function creator() external view returns (address);

    /**
     * @notice Returns the USDC token used for strike prices and order book quotes.
     */
    function paymentToken() external view returns (address);

    /**
     * @notice Returns the vault that holds provider collateral for this market.
     */
    function collateralVault() external view returns (address);

    /**
     * @notice Returns the most recently allocated provider position ID.
     */
    function nextPositionId() external view returns (uint256);

    /**
     * @notice Returns the provider obligation backing a mint position.
     */
    function mintPositions(uint256 positionId)
        external
        view
        returns (
            address provider,
            uint256 tokenId,
            uint256 units,
            uint256 bondPerUnit,
            uint256 assignedUnits,
            bool released
        );

    /**
     * @notice Returns the most recently allocated exercise claim ID.
     */
    function nextClaimId() external view returns (uint256);

    /**
     * @notice Returns the provider assignment and held strike for an exercised option.
     */
    function claims(uint256 claimId)
        external
        view
        returns (address exerciser, address provider, uint256 tokenId, uint256 positionId, uint256 strike);

    /**
     * @notice Returns the strike price in USDC base units for a strike row.
     */
    function strikePriceAt(uint256 strikeIndex) external view returns (uint256);

    /**
     * @notice Returns the strike price in USDC base units for a token ID.
     */
    function strikePrice(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Returns the token ID at a strike row and hourly slot column.
     */
    function tokenIdFor(uint256 strikeIndex, uint256 hourIndex) external view returns (uint256);

    /**
     * @notice Returns the UTC start of the given hourly slot.
     */
    function slotStart(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Returns the UTC end of the given hourly slot.
     */
    function slotEnd(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Returns the UTC end of the delivery week.
     */
    function deliveryEnd() external view returns (uint256);

    /**
     * @notice Mints options after locking the provider's USDC bond in the vault.
     * @param tokenId Strike-row and hour-column option ID.
     * @param units Number of option units to mint.
     * @param bondPerUnit USDC base units locked for each minted option.
     * @return positionId Provider position that backs these units.
     */
    function mintOptions(uint256 tokenId, uint256 units, uint256 bondPerUnit) external returns (uint256 positionId);

    /**
     * @notice Burns one option, holds its USDC strike, and assigns an unclaimed provider position.
     * @param tokenId Option series to exercise before expiry.
     * @return claimId Exercise claim ID.
     */
    function exercise(uint256 tokenId) external returns (uint256 claimId);

    /**
     * @notice Releases the unassigned part of a mint position's bond after option expiry.
     * @param positionId Provider position to release.
     */
    function releaseExpiredPosition(uint256 positionId) external;
}
