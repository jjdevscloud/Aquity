# Aquity contracts

Foundry project for AQUITY-SPEC.md's contract set.

- **Phase 1** — the Splitter alone: one `pay()` call splits a job payment
  between the builder and the agent's Vault, swapping the vault share into
  the paired stock token.
- **Phase 2** — registry and launch: AgentRegistry, Launcher, Vesting. One
  `Launcher.launch()` call creates the agent's token through a third-party
  launchpad, registers its on-chain identity, makes the first buy, and locks
  the builder's allocation.
- **Phase 3** (current) — distribution: FeeRouter, Distributor. FeeRouter
  claims and splits trading fees; Distributor pays the Vault's holdings out
  to holders via posted Merkle roots.

## Contracts

- `src/Splitter.sol` — receives job payments, splits by `vaultShareBps`, swaps
  the vault share via `ISwapRouter` and deposits it into `Vault`.
- `src/Vault.sol` — holds one agent's paired stock token. The only way money
  leaves is `release`, callable only by `distributor`; there is no path for
  the agent or builder to withdraw (spec §2.3, "Never touch the vault").
- `src/AgentRegistry.sol` — ERC-721 identity per agent. `register()` (callable
  only by `Launcher`) checks an EIP-712 signature binding the agent key to the
  owner wallet, and a second EIP-712 signature from a trusted `verifier`
  attesting the X-handle verification post was found — see spec §2.4. Ticker
  and X handle are each unique and permanent.
- `src/Launcher.sol` — one transaction: calls the launchpad factory to create
  the agent token, calls `AgentRegistry.register()`, deploys a `Vesting`
  contract, makes the first buy with the ETH sent in, routes it to `Vesting`.
- `src/Vesting.sol` — locks the builder's launch-day token allocation.
  Releases against cumulative *graded* revenue (spec §3.4), reported by an
  authorized `reporter` — the real revenue oracle/indexer is Phase 3+ work,
  so `reporter` is just an admin-set address for now.
- `src/interfaces/ISwapRouter.sol` — minimal Uniswap-V2-shaped router
  interface. Point `router` at Robinhood Chain's real DEX once confirmed.
- `src/interfaces/ILaunchpadFactory.sol` — minimal stand-in for the
  third-party launchpad factory/pool. Reshape to match the real ABI (Robinhood
  Chain's own launchpad, or pump.fun Custom Pairs) before deploying for real.
- `src/FeeRouter.sol` — claims accrued trading fees from `IFeeEscrow` and
  splits them by `feeSplitBps` between the Vault (holder share) and the
  agent's own wallet. No swap leg — fees already arrive in the paired stock.
- `src/Distributor.sol` — pays the Vault's holdings out to holders. Computing
  a *time-weighted* balance from historical Transfer logs is an off-chain
  indexing job, not something Solidity can do; the indexer posts a Merkle
  root per epoch via `postRoot` (pulling exactly that epoch's total out of
  the Vault), and holders either `claim` individually or get batch-pushed by
  `sweep` once their allocation clears `dustThreshold` (spec §11.5).
- `src/interfaces/IFeeEscrow.sol` — minimal stand-in for the launchpad's
  trading-fee escrow. Reshape to match the real ABI once confirmed.
- `src/mocks/` — `MockERC20` / `MockRouter` / `MockLaunchpadFactory` /
  `MockFeeEscrow`, test-only, not deployed.

## What's not built yet

- The X-verification backend itself (reading the timeline, generating the
  code, signing the `verifier` attestation) — `AgentRegistry` only verifies
  the resulting signature on-chain.
- The revenue oracle/indexer that would call `Vesting.reportRevenue()` with
  real graded numbers, or compute Distributor's time-weighted Merkle trees
  and call `postRoot`.
- Revenue grading / anti-circularity weighting (spec §3.4) — not enforced
  anywhere on-chain; it's an indexer-side computation before revenue ever
  reaches `Splitter.pay()` or a `Vesting.reportRevenue()` call.

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

Set `ROBINHOOD_RPC_URL` and the env vars documented at the top of each script,
then run against `--rpc-url robinhood` — omit `--broadcast` for a dry run:

```shell
forge script script/DeploySplitter.s.sol --rpc-url robinhood --broadcast --verify
forge script script/DeployRegistryAndLauncher.s.sol --rpc-url robinhood --broadcast --verify
forge script script/DeployFeeRouterAndDistributor.s.sol --rpc-url robinhood --broadcast --verify
```

### Local end-to-end demo (anvil)

`script/DeployLocalDemo.s.sol` deploys everything above plus mocks (a
payment token, a stock token, a swap router, a launchpad factory, a fee
escrow) to a local anvil chain, launches one agent through `Launcher`
exactly like a real builder would — real EIP-712 signatures, checked
on-chain, not stubbed — wires its Vault/Splitter/FeeRouter/Distributor, and
fires one job payment and one fee claim so there's something to see
immediately. It writes `local-demo-output.json` / `local-demo-env.json`
(gitignored) with every deployed address.

From the repo root, `run-local-demo.ps1` drives this end to end and copies
the output straight into `indexer/agents.config.json`:

```powershell
.\run-local-demo.ps1
```

Or run the script directly (from `/contracts`, with `anvil` already running
separately):

```shell
forge script script/DeployLocalDemo.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

You can also simulate it with no anvil at all — no `--rpc-url`, no
`--broadcast` — which runs against Foundry's own in-process EVM and
exercises everything except actually persisting a chain the indexer could
point at. Useful for checking the script itself still compiles and runs
clean after an edit:

```shell
forge script script/DeployLocalDemo.s.sol
```
