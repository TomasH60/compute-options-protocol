# Compute options protocol design

Working design for a market in which providers sell call options on future GPU compute hours. This document separates the intended protocol from what the current contracts implement.

## Market and option series

A `ComputeOption` ERC-1155 contract represents one weekly option book for a standardized GPU configuration and supporting compute grade. The initial configuration is an NVIDIA GeForce RTX 5090 desktop with 32 GB VRAM. Grades `A`, `B`, and `C` are separate markets; their measurable CPU, RAM, network, and service requirements still need definitions. A market represents a configuration, not one provider's physical GPU.

The registry holds a chain-specific USDC address and creates at most one contract per grade and weekly expiry. The current creation rule permits the next Monday at 00:00 UTC as expiry, and the next contract for a grade may be created after the current one expires. USDC is the intended unit for strike prices, premiums, collateral, and settlement.

Each market has a set of ascending strike-price rows and 168 hourly columns for the seven days immediately after expiry. Each row/column pair is one ERC-1155 token ID:

```text
tokenId = strikeIndex * 168 + hourIndex
hourIndex = 0..167
```

For example, with $1, $2, $3, $4, and $5 strike rows, IDs `0..167` have a $1 strike, IDs `168..335` have a $2 strike, and ID `168` represents the first delivery hour at a $2 strike. There are 840 IDs in that example. A token gives its holder the right to claim one qualifying GPU hour in its slot by exercising before the shared expiry and paying its strike. Multiple providers may back units of the same token ID, so those units are fungible before exercise.

The contract's GPU configuration, grade, expiry, strike rows, and derived slot times are on-chain terms. The ERC-1155 URI points to optional JSON for names, descriptions, and images; JSON does not define or enforce the option terms.

## Providers and the order book

Providers register physical GPUs that meet the market's configuration and grade. A provider can commit capacity for a token ID only if a qualifying GPU can serve that hour. A physical GPU cannot back overlapping obligations beyond its actual capacity. Each minted option unit must correspond to one unassigned, collateralized provider obligation in that token ID's pool.

The option token does not retain its minting provider's identity as it moves between wallets. The protocol separately tracks each provider's outstanding units, reserved GPU capacity, and locked USDC collateral. Providers can place ask orders for the options they mint; buyers can place bids. Several orders for the same token ID may have different premiums. Bid and ask prices belong to the order book, not to the token ID's fixed terms.

The proposed collateral rule is for a provider to lock an amount equal to the premium they commit to for each minted unit. For example, minting one option with a $3 initial premium locks $3 of that provider's USDC. That bond remains associated with the provider obligation even if the token later trades for $2, $4, or passes through several wallets. The exact point at which the initial premium and bond become fixed, and whether an unsold ask may change, still need specification.

## Exercise and delivery

Before expiry, a holder exercises a token ID and pays its strike into escrow. Exercise consumes one option token and assigns one unclaimed provider obligation from that token ID's pool. The protocol records a claim containing at least the exerciser, token ID, assigned provider, assigned GPU or capacity position, strike held, and bond attached to that position. The claim is specific to that provider even though the option token was fungible before exercise.

If the provider delivers the compute hour, the strike is settled and their bond is released. If they fail, the exerciser receives the assigned provider's collateral and the strike is returned from escrow. The collateral payment is **not guaranteed to equal the exerciser's latest purchase price**. A buyer who pays more on resale accepts that price difference as trading risk. Because providers may lock different bonds for the same token ID, the failure payment depends on which provider is assigned at exercise; the assignment rule and this exposure must be visible to buyers.

Collateral and reservations can ensure that an unassigned provider obligation exists for every outstanding option unit. They cannot prove that a physical GPU is online or that service was delivered. The protocol needs a delivery-verification and dispute process, plus a defined response when an assigned provider is unavailable.

## Recommended collateral vault

Use one purpose-built USDC escrow for all option markets created by the registry. It should hold provider deposits without issuing vault shares or investing the funds. Each provider has a free balance that they may withdraw and locked balances attached to specific obligations. A lock is identified by both the option-market address and a provider-position ID, so one market cannot release or slash another market's collateral.

Only markets created by the registry may manage their own collateral locks. A provider deposits USDC, then minting an option atomically locks `units * bondPerUnit` for that provider position. Free balance cannot be withdrawn once locked. After expiry, the market releases only the bond for units that were never assigned; assigned units remain locked. The intended outcome is to release a successful unit's bond to the provider and send a failed unit's bond to the exerciser. The market, rather than the vault, tracks token IDs, provider capacity, assignment, and claim status.

The buyer's exercise strike is currently held by the option market, separate from provider bonds in the vault. Future settlement must account for each claim's strike separately. If delivery fails, the strike should return to the exerciser independently of the provider's bond. The order book handles premium payments; the collateral vault only holds bonds. The proposed `bondPerUnit` is the provider's committed initial premium, while later bid and ask prices do not change that bond. The rule for changing an unsold ask or commitment remains open.

This vault is a custody and obligation ledger, not an ERC-4626 share vault. Its implementation should use safe USDC transfers and reentrancy protection, while restricting withdrawals to free balances and settlement operations to the market that owns each lock.

## Current implementation

`ComputeOptionRegistry` deploys a shared USDC vault and weekly grade-specific markets, authorizes each market in the vault, and stores market addresses. `ComputeOption` stores the fixed GPU configuration, grade, expiry, USDC address, and strike rows; it derives the strike and delivery hour from a token ID. `IComputeOption` exposes these terms through the ERC-1155 interface. Providers can deposit and withdraw free USDC and mint options with a committed bond per unit. Before expiry, exercise burns one option, assigns the oldest position with an available unit for that token ID, collects the strike in USDC, and records a claim. After expiry, a position can release only its unassigned bond. The implementation does **not** yet register physical GPUs, enforce grade requirements or capacity, run an order book, verify delivery, slash collateral, or settle claims. The strike and bond attached to a claim cannot currently be withdrawn or paid out, so this implementation must not be used with real funds.

## Decisions still needed

- Define objective requirements and verification for grades `A`, `B`, and `C`, including how physical GPUs are identified and prevented from backing overlapping slots.
- Define when the initial premium and bond are fixed, whether an unsold ask can change, and the exact release conditions for unexercised obligations.
- Define order matching, payment flow, and whether ERC-1155 transfers outside the order book are allowed.
- Choose a fair, gas-bounded provider-assignment rule and what happens if the selected provider is offline but another is available.
- Define service delivery evidence, deadlines, disputes, slashing, strike release, and any transferable form of an exercised claim.
