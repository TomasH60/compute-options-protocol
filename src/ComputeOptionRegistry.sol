// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IComputeOption} from "./interfaces/IComputeOption.sol";
import {ComputeOption} from "./ComputeOption.sol";
import {ComputeOptionVault} from "./ComputeOptionVault.sol";

/**
 * @title ComputeOptionRegistry
 * @notice Creates one weekly RTX 5090 option market per compute grade and expiry.
 */
contract ComputeOptionRegistry {
    /*//////////////////////////////////////////////////////////////
                              ERRORS & EVENTS
    //////////////////////////////////////////////////////////////*/

    error InvalidUsdc();
    error InvalidExpiry();
    error OptionAlreadyExists(IComputeOption.Grade grade, uint64 expiry);
    error ActiveOptionExists(IComputeOption.Grade grade, address option);

    event ComputeOptionCreated(
        IComputeOption.Grade indexed grade, uint64 indexed expiry, address indexed option, address creator
    );

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    address public immutable USDC;
    ComputeOptionVault public immutable VAULT;

    mapping(IComputeOption.Grade grade => mapping(uint64 expiry => address option)) public optionForWeek;
    mapping(IComputeOption.Grade grade => address option) public currentOption;
    address[] public options;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the USDC token used by every market created by this registry.
     * @param usdc_ USDC contract address on the deployment chain.
     */
    constructor(address usdc_) {
        if (usdc_ == address(0) || usdc_.code.length == 0) revert InvalidUsdc();
        USDC = usdc_;
        VAULT = new ComputeOptionVault(usdc_, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                             MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates the option market for the next Monday's expiry.
     * @param grade Supporting compute grade for this market.
     * @param expiry Next Monday at 00:00 UTC.
     * @param strikePrices Strictly increasing strike prices in USDC base units.
     * @param metadataURI ERC-1155 metadata URI, optionally containing `{id}`.
     * @return option Address of the deployed option market.
     */
    function createOption(
        IComputeOption.Grade grade,
        uint64 expiry,
        uint256[] calldata strikePrices,
        string calldata metadataURI
    ) external returns (address option) {
        // Unix timestamps for Monday 00:00 UTC have a four-day offset from the epoch's Thursday.
        if (expiry <= block.timestamp || uint256(expiry) > block.timestamp + 1 weeks || expiry % 1 weeks != 4 days) {
            revert InvalidExpiry();
        }
        if (optionForWeek[grade][expiry] != address(0)) revert OptionAlreadyExists(grade, expiry);

        address active = currentOption[grade];
        if (active != address(0) && block.timestamp < IComputeOption(active).expiry()) {
            revert ActiveOptionExists(grade, active);
        }

        option = address(new ComputeOption(grade, expiry, msg.sender, USDC, address(VAULT), strikePrices, metadataURI));
        VAULT.authorizeMarket(option);
        optionForWeek[grade][expiry] = option;
        currentOption[grade] = option;
        options.push(option);

        emit ComputeOptionCreated(grade, expiry, option, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the number of markets deployed by this registry.
     */
    function optionCount() external view returns (uint256) {
        return options.length;
    }
}
