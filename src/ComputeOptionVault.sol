// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IComputeOptionVault} from "./interfaces/IComputeOptionVault.sol";

/**
 * @title ComputeOptionVault
 * @notice Holds provider USDC and locks it against option positions.
 * @dev Each lock is scoped to the registered market that created it.
 */
contract ComputeOptionVault is IComputeOptionVault, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                  TYPES
    //////////////////////////////////////////////////////////////*/

    struct Lock {
        address provider;
        uint256 amount;
    }

    /*//////////////////////////////////////////////////////////////
                              ERRORS & EVENTS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized();
    error InvalidAmount();
    error InvalidMarket();
    error UnsupportedTokenBehavior();
    error InsufficientAvailable(uint256 available, uint256 required);
    error LockAlreadyExists();
    error LockNotFound();
    error InsufficientLocked(uint256 locked, uint256 required);

    event Deposited(address indexed provider, uint256 amount);
    event Withdrawn(address indexed provider, uint256 amount);
    event MarketAuthorized(address indexed market);
    event CollateralLocked(
        address indexed market, uint256 indexed positionId, address indexed provider, uint256 amount
    );
    event CollateralReleased(
        address indexed market, uint256 indexed positionId, address indexed provider, uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    IERC20 public immutable USDC;
    address public immutable REGISTRY;

    mapping(address provider => uint256 amount) public override availableBalance;
    mapping(address market => bool authorized) public override authorizedMarkets;
    mapping(address market => mapping(uint256 positionId => Lock)) public override locks;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the USDC token and the registry allowed to authorize markets.
     * @param usdc_ USDC contract address on the deployment chain.
     * @param registry_ Registry that creates and authorizes option markets.
     */
    constructor(address usdc_, address registry_) {
        if (usdc_ == address(0) || registry_ == address(0)) revert Unauthorized();
        USDC = IERC20(usdc_);
        REGISTRY = registry_;
    }

    /*//////////////////////////////////////////////////////////////
                             ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IComputeOptionVault
     */
    function authorizeMarket(address market) external override {
        if (msg.sender != REGISTRY) revert Unauthorized();
        if (market == address(0) || market.code.length == 0) revert InvalidMarket();
        authorizedMarkets[market] = true;
        emit MarketAuthorized(market);
    }

    /*//////////////////////////////////////////////////////////////
                            PROVIDER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IComputeOptionVault
     */
    function deposit(uint256 amount) external override nonReentrant {
        if (amount == 0) revert InvalidAmount();
        uint256 balanceBefore = USDC.balanceOf(address(this));
        USDC.safeTransferFrom(msg.sender, address(this), amount);
        if (USDC.balanceOf(address(this)) - balanceBefore != amount) revert UnsupportedTokenBehavior();
        availableBalance[msg.sender] += amount;
        emit Deposited(msg.sender, amount);
    }

    /**
     * @inheritdoc IComputeOptionVault
     */
    function withdraw(uint256 amount) external override nonReentrant {
        if (amount == 0) revert InvalidAmount();
        uint256 available = availableBalance[msg.sender];
        if (available < amount) revert InsufficientAvailable(available, amount);
        availableBalance[msg.sender] = available - amount;
        USDC.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                             MARKET FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IComputeOptionVault
     */
    function lock(address provider, uint256 positionId, uint256 amount) external override {
        if (!authorizedMarkets[msg.sender]) revert Unauthorized();
        if (provider == address(0) || amount == 0) revert InvalidAmount();
        if (locks[msg.sender][positionId].provider != address(0)) revert LockAlreadyExists();
        uint256 available = availableBalance[provider];
        if (available < amount) revert InsufficientAvailable(available, amount);
        availableBalance[provider] = available - amount;
        locks[msg.sender][positionId] = Lock({provider: provider, amount: amount});
        emit CollateralLocked(msg.sender, positionId, provider, amount);
    }

    /**
     * @inheritdoc IComputeOptionVault
     */
    function release(uint256 positionId, uint256 amount) external override {
        if (!authorizedMarkets[msg.sender]) revert Unauthorized();
        Lock storage position = locks[msg.sender][positionId];
        if (position.provider == address(0)) revert LockNotFound();
        if (amount == 0) revert InvalidAmount();
        uint256 locked = position.amount;
        if (locked < amount) revert InsufficientLocked(locked, amount);
        address provider = position.provider;
        if (locked == amount) {
            delete locks[msg.sender][positionId];
        } else {
            position.amount = locked - amount;
        }
        availableBalance[provider] += amount;
        emit CollateralReleased(msg.sender, positionId, provider, amount);
    }
}
