# Aquity contracts

Foundry project for AQUITY-SPEC.md's contract set. Phase 1 (current): the
Splitter alone — one `pay()` call splits a job payment between the builder
and the agent's Vault, swapping the vault share into the paired stock token.

## Contracts

- `src/Splitter.sol` — receives job payments, splits by `vaultShareBps`, swaps
  the vault share via `ISwapRouter` and deposits it into `Vault`.
- `src/Vault.sol` — holds one agent's paired stock token. Deposit-only; no
  withdrawal path for the agent or builder (spec §2.3, "Never touch the vault").
  Release-to-holders lands in Phase 3 with the Distributor.
- `src/interfaces/ISwapRouter.sol` — minimal Uniswap-V2-shaped router
  interface. Point `router` at Robinhood Chain's real DEX once confirmed.
- `src/mocks/` — `MockERC20` / `MockRouter`, test-only, not deployed.

## Before deploying anything real

Per spec §3.2, verify on a Robinhood Chain fork first:

1. A contract (the Vault) can actually custody the tokenized stock token —
   some third-party analyses claim transfer restrictions on these.
2. Which router/DEX on Robinhood Chain has real pool depth for the pair.
3. Vault value should come from the Chainlink feed or the ERC-8056
   `uiMultiplier()`, never from `balanceOf()` alone once corporate actions
   are in play — not yet needed for Phase 1's raw deposit-only Vault.

## Usage

```shell
forge build
forge test -vv
```

### Deploy (Robinhood Chain)

Set `ROBINHOOD_RPC_URL` and the env vars documented at the top of
`script/DeploySplitter.s.sol`, then:

```shell
# dry run against the RPC without broadcasting
forge script script/DeploySplitter.s.sol --rpc-url robinhood

# broadcast for real
forge script script/DeploySplitter.s.sol --rpc-url robinhood --broadcast --verify
```
