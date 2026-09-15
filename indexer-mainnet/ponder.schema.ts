import { onchainTable } from "ponder";

/**
 * On-chain identity, populated from AgentRegistry.AgentRegistered — same
 * contract, same event shape as the testnet indexer (AgentRegistry.sol is
 * unchanged for this mainnet flow). `owner` is the human; `agentKey` is
 * the agent's own wallet — the one that actually launched the token, see
 * ponsLaunch below.
 */
export const agentIdentity = onchainTable("agent_identity", (t) => ({
  ticker: t.text().primaryKey(),
  tokenId: t.bigint().notNull(),
  owner: t.hex().notNull(),
  agentKey: t.hex().notNull(),
  agentId: t.text().notNull(),
  xHandle: t.text().notNull(),
  /** The real Robinhood Stock Token this agent is paired with. */
  pairAddress: t.hex().notNull(),
  /** The real token Pons deployed for this agent — same as ponsLaunch.token. */
  agentTokenAddress: t.hex().notNull(),
  registeredAt: t.bigint().notNull(),
}));

/**
 * One row per agent, from PonsLauncher.AgentFullyLaunchedOnPons — the real
 * Pons v2 launch facts. No Vault/Splitter/FeeRouter/Distributor exist yet
 * for this flow (Phase B) — trading, price, and holder data all live on
 * Pons's own contracts (and are already served live by GMGN/Axiom/etc.),
 * not duplicated here.
 */
export const ponsLaunch = onchainTable("pons_launch", (t) => ({
  ticker: t.text().primaryKey(),
  name: t.text().notNull(),
  agentToken: t.hex().notNull(),
  curve: t.hex().notNull(),
  startBlock: t.bigint().notNull(),
}));

/**
 * Full Transfer history per agent token — Phase B's distribution job
 * (src/jobs/postEpochRoot.ts) needs actual transfer-by-transfer history,
 * not just a running balance, to compute time-weighted holdings within an
 * epoch window. Nothing else reads this table.
 *
 * Keyed by `agentToken` address, NOT ticker, deliberately: a real fork test
 * of this exact indexer found that a token's very first Transfer (Pons's
 * own initial mint, inside the same launch transaction) fires BEFORE
 * PonsLauncher's own AgentLaunchedOnPons event — ours is emitted last, once
 * control returns from factory.launchToken(). A ticker reverse-index
 * populated by that later event would still be empty at the moment the
 * mint's Transfer handler runs, silently dropping every token's first-ever
 * transfer. Storing the address directly needs no such lookup at write
 * time; ticker resolution happens later, at read time, against ponsLaunch
 * (see src/api/distribution.ts), by which point it's always populated.
 */
export const agentTokenTransfer = onchainTable("agent_token_transfer", (t) => ({
  id: t.text().primaryKey(), // `${blockNumber}-${logIndex}`
  agentToken: t.hex().notNull(),
  from: t.hex().notNull(),
  to: t.hex().notNull(),
  value: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  timestamp: t.bigint().notNull(),
}));

// Posted-epoch records and per-holder Merkle proofs are NOT declared here.
// ponder:api's db is read-only (event handlers are the only place Ponder
// allows writes, and there's no on-chain event carrying individual
// holder/proof data to index in the first place — only the Merkle root
// goes on-chain). src/jobs/postEpochRoot.ts and src/api/distribution.ts
// instead share a small, separately-defined Postgres schema of their own
// — see src/lib/distributionDb.ts — reached via a plain `pg` client, not
// through onchainTable/Drizzle at all.
