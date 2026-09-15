# aquity-indexer-mainnet

Ponder indexer for the **real** Robinhood Chain mainnet (chain 4663) flow — real Stock
Tokens, real Pons v2 launchpad, real money. Deliberately a separate project from
`/indexer` (the testnet one) so real and demo data are never in the same database or API
response.

## What this tracks

- `AgentRegistry.AgentRegistered` — our own identity layer (unchanged contract from
  testnet; same ABI, different deployment). Records `owner` (the human) and `agentKey`
  (the agent's own wallet — the one that actually launches the token).
- `PonsLauncher.AgentLaunchedOnPons` — the real Pons v2 launch facts (token, curve).

There's deliberately no Vault/Splitter/FeeRouter/Distributor tracking here — that
revenue-sharing runtime (Phase B) doesn't exist for this flow yet. Trading, price, and
holder data already live on Pons's own contracts and are already served live by
third-party terminals (GMGN, Axiom, etc. — confirmed manually: a real launch showed up on
both within minutes). `/api/agents` is identity + "where to find it," not a stats mirror.

## Setup

```shell
cp .env.example .env.local   # fill in a real mainnet RPC — the free public endpoint
                              # rate-limits hard enough that local backfill effectively
                              # stalls; use Alchemy or similar, same as /indexer's testnet
                              # setup needed.
npm install
npm run dev
```

Contract addresses, their deploy blocks, and the Pons factory address are pre-filled in
`.env.example` — see `/contracts/script/DeployPonsMainnet.s.sol` and
`RedeployPonsLauncherMainnet.s.sol` for how they were deployed.

`VERIFIER_PRIVATE_KEY` must be a **mainnet-only** key — never reuse the testnet verifier
key here. See `AgentRegistry.verifier()` on the real deployed registry to confirm which
address it currently trusts.

## X verification

Same mechanism as `/indexer`'s `src/api/verify.ts` (oEmbed-based, no X Developer API
needed), with one difference: the thing posted to X is the **agent's own wallet address**,
not a random code — that's what ties a verified human X account to a specific agent
wallet the human doesn't hold the key for.
