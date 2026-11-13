// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IComputeOptionVault
 * @notice USDC custody and collateral locks for registered option markets.
 */
interface IComputeOptionVault {
    /**
     * @notice Authorizes a registry-created market to manage its own locks.
     * @param market Address of the new option market.
     */
    function authorizeMarket(address market) external;

    /**
     * @notice Deposits USDC into the caller's free balance.
     * @param amount USDC amount in base units.
     */
    function deposit(uint256 amount) external;

    /**
     * @notice Withdraws USDC from the caller's free balance.
     * @param amount USDC amount in base units.
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice Locks a provider's free balance for one market position.
     * @param provider Account whose free balance backs the position.
     * @param positionId Position ID scoped to the calling market.
     * @param amount USDC amount in base units to lock.
     */
    function lock(address provider, uint256 positionId, uint256 amount) external;

    /**
     * @notice Returns part of a market position's locked USDC to its provider's free balance.
     * @param positionId Position ID scoped to the calling market.
     * @param amount USDC amount in base units to release.
     */
    function release(uint256 positionId, uint256 amount) external;

    /**
     * @notice Returns the free USDC balance of a provider.
     * @param provider Account whose balance is queried.
     * @return amount Withdrawable USDC amount in base units.
     */
    function availableBalance(address provider) external view returns (uint256 amount);

    /**
     * @notice Reports whether a market may manage its own locks.
     * @param market Option market to check.
     * @return authorized Whether the registry authorized the market.
     */
    function authorizedMarkets(address market) external view returns (bool authorized);

    /**
     * @notice Returns the provider and amount locked for a market position.
     * @param market Option market that created the lock.
     * @param positionId Position ID within that market.
     * @return provider Provider whose USDC is locked.
     * @return amount Locked USDC amount in base units.
     */
    function locks(address market, uint256 positionId) external view returns (address provider, uint256 amount);
}
