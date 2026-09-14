# Aquity indexer

Ponder project for AQUITY-SPEC.md §9 ("Indexer: Ponder, or a viem event
listener with Postgres"). Watches the Phase 1–3 contracts in `/contracts`
and serves `GET /api/agents`, which `aquity.html` fetches when
`window.AQUITY_API_BASE` is set (see its `loadAgentsFromIndexer()`).

**Not runnable in the environment this was written in** — no Node.js was
available, so nothing here has actually been executed. It's built closely
against Ponder's current documented API (verified against
ponder.sh/docs and the ponder-sh/ponder `with-foundry` example as of
2026-09), but treat the first `npm install && npm run dev` as the real test,
not this description.

## Setup

```shell
npm install
cp .env.example .env.local   # fill in RPC url, chain id, deployed addresses
npm run codegen               # generates ponder-env.d.ts — commit it after
npm run dev
```

Ponder only reads `.env.local` (not plain `.env` — this tripped up the first
real run of this indexer, see git history), so the file must be named
`.env.local`.

Requires Node.js ≥22 and a Postgres 14–17 database (`DATABASE_URL` in
`.env.local`) — see [ponder.sh/docs/requirements](https://ponder.sh/docs/requirements).

## Testing against a real local chain

The fastest way to get real values for everything below, rather than typing
addresses in by hand: from the repo root, run `.\run-local-demo.ps1`. It
starts anvil, deploys every contract plus mocks, launches one real demo
agent, and writes `agents.config.json` for you — see
`/contracts/README.md`'s "Local end-to-end demo" section.

## Populating agents.config.json

Registration isn't permissionless yet (AQUITY-SPEC.md §10 Phase 5: "twenty
hand-picked agents"). `AgentRegistry` and `Launcher` are singletons this
indexer discovers on-chain identity from automatically, but `Splitter`,
`Vault`, `FeeRouter`, `Distributor`, and `Vesting` are deployed one-off per
agent via the Foundry scripts, not through a factory `Launcher` calls — so
there's no on-chain event to discover them from. List each onboarded agent's
contract addresses in `agents.config.json`:

```json
[
  {
    "ticker": "SENTRY",
    "name": "Contract risk flagging",
    "company": "Palantir",
    "sector": "Legal & risk",
    "operator": "kessler",
    "pairSymbol": "PLTRx",
    "pairAddress": "0x...",
    "agentTokenAddress": "0x...",
    "splitterAddress": "0x...",
    "vaultAddress": "0x...",
    "feeRouterAddress": "0x...",
    "distributorAddress": "0x...",
    "vestingAddress": "0x...",
    "startBlock": 1234567
  }
]
```

`ticker` here must match the ticker used at on-chain registration exactly —
that's how `src/lib/agents.ts` joins agents.config.json's curatorial fields
(company, sector, pair symbol) against `agentIdentity`/`agentStats` rows
keyed by ticker.

## What's real vs. a placeholder in `/api/agents`

Real, computed from indexed events:

- `vault`, `distributed`, `fromRevenue`, `fromFees`, `agentBalance` — running
  totals from `Vault.Deposited/Released`, `Distributor.Claimed`,
  `Splitter.WorkReceipt`, `FeeRouter.FeesClaimedAndSplit`.
- `feeSplit`, `vaultShare` — read live off `FeeRouter`/`Splitter` each time
  they emit an event; self-healing if the owner changes them.
- `holders` — count of non-zero balances in `agent_token_balance`, built
  from the agent token's own `Transfer` logs.
- `status`, `daysSincePaid` — AQUITY-SPEC.md §2.5's lifecycle rule, from
  `lastPaidAt`.
- `owner`, `xHandle`, `agentId` — from `AgentRegistry.AgentRegistered` (plus
  one `agents(tokenId)` read for `xHandle`, which isn't in the event).

Honest placeholders, not computed:

- `stockPrice`, `tokenPrice` — need a price feed (Chainlink
  `latestRoundData()` or a DEX quote, AQUITY-SPEC.md §9 "Prices"). Always 0.
- `completionRate`, `margin`, `quality` — revenue grading (AQUITY-SPEC.md
  §3.4, the 1.0×/0.4×/0.1×/0× weighting by payer) isn't implemented
  anywhere, contracts included. `quality` returns `[100,0,0]` once an agent
  has any jobs (optimistic default so the UI doesn't read as "no income")
  and `[0,0,0]` before that.
- `skills` — always `[false,false,false,false,false]`. The five skills
  (§2.3) are operator-side behavior, not something these contracts expose
  as on-chain flags.
- `revenue24h` — always 0; only a cumulative `revenue30d` total exists (see
  below).

## Known limitations

- **`revenue30d`/`revenue24h` are cumulative-to-date, not rolling windows.**
  A real 30d/24h figure needs a day-bucketed table (e.g. `agent_stats_daily`,
  summed over the trailing N rows) — not built here.
- **`fromRevenue`/`fromFees` are deposit-side, not claim-side.** They track
  what flowed into the Vault by source. Once in the Vault the money is
  fungible, so a payout's *actual* revenue/fee split can't be recovered at
  claim time without FIFO or pro-rata accounting — not attempted.
- **Amounts assume 18 decimals** (`toDisplayAmount` in `src/api/index.ts`).
  If USDG or a given tokenized stock uses a different `decimals()`, this
  needs a per-token divisor.
- **`agent_token_balance` is exactly the input a Distributor root-posting
  job needs** (time-weighted balances from Transfer logs → Merkle tree,
  AQUITY-SPEC.md §3.3) but building that job — the actual "who gets paid
  how much this epoch" logic that calls `Distributor.postRoot` — is not
  part of this indexer.
