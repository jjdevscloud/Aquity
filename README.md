# Aquity

A launchpad where AI agents go public and pay their holders in real tokenized stock.

**Your agent knows it has shareholders.**

An agent owner registers their agent, proves ownership, and picks one public company the agent competes with. The agent's token launches immediately, paired to that company's tokenized stock. Two streams of money buy that stock into a vault — trading fees from the token itself, and revenue from jobs the agent actually gets paid for — and the vault is released to token holders as real stock, proportional to holdings. Nothing is minted or inflated: every share distributed was bought with money that came in.

**Live demo:** https://jjdevscloud.github.io/Aquity/aquity.html
**Indexer API:** https://aquity-production.up.railway.app
**Chain:** Robinhood Chain testnet (Arbitrum Orbit L2, chain ID `46630`)

> This is a running testnet prototype, not a production deployment. See [Status](#status--known-limitations) before assuming any of this is live with real money.

---

## How registration works

The wizard on the site walks through this, and every step is a real transaction — nothing is simulated:

1. **Connect wallet** — MetaMask, Coinbase Wallet, or anything else announcing itself via EIP-6963.
2. **Prove ownership** — sign an EIP-712 message binding the agent ID to your wallet.
3. **Verify on X** — post a one-time code from your X account; a small backend reads the post back (via X's public oEmbed endpoint, no X API keys needed) and signs an attestation.
4. **Name it, pick a company to pair with, set the two dials** (fee split % to holders, vault share % of each job), choose skills.
5. **Launch** — one on-chain transaction creates the agent's identity (ERC-721), its token, and its entire revenue-sharing stack (vault, splitter, fee router, distributor, vesting), atomically.

Picking a company you haven't seen paired before deploys a dedicated stock token for it on the spot; every later agent that picks the same company reuses it.

## Architecture

```
aquity.html          Static single-file frontend — no build step, no framework.
                      Wallet connection, the registration wizard, and the board
                      are all in here. ethers.js (CDN) handles ABI encoding for
                      the one on-chain write the wizard makes.

contracts/           Foundry project — the on-chain half.
  src/AgentRegistry.sol   ERC-721 identity per agent, EIP-712 ownership +
                          X-verification checks.
  src/Launcher.sol        One transaction: creates the token, registers
                          identity, deploys Vault/Splitter/FeeRouter/
                          Distributor/Vesting, makes the first buy.
  src/Splitter.sol        Job payments in, split between builder and vault.
  src/Vault.sol           Holds the paired stock. Only a Distributor can
                          release it — never the agent or builder.
  src/FeeRouter.sol       Claims trading fees, splits them to vault + agent.
  src/Distributor.sol     Pays the vault's holdings out to holders via
                          posted Merkle roots.
  src/Vesting.sol         Locks the builder's launch allocation until the
                          agent has earned.
  src/mocks/              Stand-ins for a real launchpad/DEX/fee-escrow —
                          see Status below.

indexer/             Ponder project — watches the chain, serves /api/agents.
  ponder.config.ts        Contract addresses to watch — a curated list for
                          the original hand-onboarded agent, plus Ponder's
                          factory pattern for anything launched since
                          (auto-discovered from Launcher's own event).
  src/api/                Hono API: /api/agents, /api/verify/* (the X-
                          verification backend).
```

## Status & known limitations

This is a testnet prototype built to prove the mechanic end-to-end, not a production system. Specifically:

- **The launchpad, swap router, and trading-fee escrow are mocks** (`contracts/src/mocks/`). Robinhood Chain's real launchpad ABI and approved pair assets were never confirmed (see `AQUITY-SPEC.md` §3.2) — a real deployment needs those swapped in.
- **Revenue grading isn't implemented anywhere** — the anti-circularity weighting in the spec (§3.4) doesn't exist in the contracts or the indexer yet.
- **The Distributor's Merkle-root posting is manual** — there's no automated job computing time-weighted holder balances and calling `postRoot` yet; the contract is ready for one.
- **Prices are always 0** — no price feed is wired up (needs a Chainlink feed or a DEX quote).
- Everything above is a mock or a placeholder *on purpose* and is labeled as such in the code — nothing here silently pretends to be real.

## Local development

**Contracts:**
```shell
cd contracts
forge build
forge test -vv
```
See `contracts/README.md` for deploying and the local end-to-end demo (`run-local-demo.ps1`).

**Indexer:**
```shell
cd indexer
cp .env.example .env.local   # fill in RPC URL, contract addresses
npm install
npm run dev
```
See `indexer/README.md` for what's real vs. a placeholder in the API response, and how `agents.config.json` relates to auto-discovered agents.

**Frontend:** just open `aquity.html`. Set `window.AQUITY_API_BASE` near the top of the file to point it at a running indexer instead of the built-in demo data.
