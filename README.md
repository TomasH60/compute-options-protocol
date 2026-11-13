## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

The [protocol design](PROTOCOL_DESIGN.md) describes the intended option book, provider pool, collateral, and exercise flows alongside the current implementation boundary.

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

Run the issue, transfer, exercise, and expiry scenarios on Foundry's local EVM:

```shell
$ forge test --match-contract ComputeOptionScenarioTest -vv
```

### Format

```shell
$ forge fmt
```

### Lint and formatting checks

CI runs these checks on pushes and pull requests:

```shell
$ forge lint --deny notes
$ forge fmt --check
```

Lint warnings and notes fail CI. Run `forge fmt` to fix formatting locally.

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

Deploy `ComputeOptionRegistry` to an already running local Anvil node:

```shell
$ make deploy USDC_ADDRESS=0xYourChainsUsdcAddress
```

This uses `http://127.0.0.1:8545` and Anvil's first default unlocked account.
It broadcasts the deployment transaction without starting Anvil.
Override the endpoint or unlocked sender when needed:

```shell
$ make deploy RPC_URL=http://127.0.0.1:9545 DEPLOYER=0xYourUnlockedAccount USDC_ADDRESS=0xYourChainsUsdcAddress
```

The registry is deployed with a chain-specific USDC contract address. Its
`createOption(grade, expiry, strikePrices, metadataURI)` deploys
one option contract per grade and weekly expiry for the RTX 5090 desktop with
32 GB VRAM. Expiry must be the next Monday at 00:00 UTC. Contracts for different
grades can coexist, but the same grade cannot be created again until its current
contract expires. Look up a contract with `optionForWeek(grade, expiry)`.

Each contract has 168 hourly columns for the week after expiry and one row per
strike price supplied at creation. Strike prices must be positive, unique, and
in ascending order, expressed in USDC base units. Token IDs use
`strikeIndex * 168 + hourIndex`; five strikes create 840 IDs.
`slotStart(id)` and `slotEnd(id)` calculate the UTC service window, and
`strikePrice(id)` returns the strike. `paymentToken()` returns the registry's
fixed USDC address.

Option premiums are bids and asks in a future order book. They can differ
between orders for the same token ID and are not stored as fixed token terms.
The registry deploys a shared USDC collateral vault. Providers approve USDC to
the vault, deposit it, and call `mintOptions(id, units, bondPerUnit)` on a market.
Minting locks `units * bondPerUnit` from their free vault balance; a mint with
insufficient free collateral reverts. A holder can call `exercise(id)` before
expiry to burn one option, pay its strike in USDC, and receive a claim assigned
to a provider position. The market holds the strike. After expiry,
`releaseExpiredPosition(positionId)` releases only collateral for units that
were never assigned. Matching an ask price to the committed bond and
delivery settlement remain to be designed. **Do not use real funds yet:**
there is no way to settle a claim, pay out or refund its strike, or release
its assigned provider collateral.

`metadataURI` is the ERC-1155 URI for display data, such as a hosted or IPFS
JSON file containing a name, description, and image. The `{id}` placeholder is
replaced by ERC-1155 clients. The GPU configuration, grade, expiry, service
hours and strike prices remain on-chain. Grade requirements, physical GPU
capacity checks, the order book, and settlement are not implemented yet.

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
