import { onchainTable, primaryKey } from "ponder";

/**
 * On-chain identity, populated from AgentRegistry.AgentRegistered (plus one
 * `agents(tokenId)` read for xHandle, which isn't in the event). Curatorial
 * fields that aren't on-chain at all — company, sector, operator — still
 * come from agents.config.json and are merged in by src/api/index.ts.
 */
export const agentIdentity = onchainTable("agent_identity", (t) => ({
  ticker: t.text().primaryKey(),
  tokenId: t.bigint().notNull(),
  owner: t.hex().notNull(),
  agentId: t.text().notNull(),
  xHandle: t.text().notNull(),
  pairAddress: t.hex().notNull(),
  agentTokenAddress: t.hex().notNull(),
  registeredAt: t.bigint().notNull(),
}));

/**
 * One row per agent, keyed by ticker. Everything here is *derived from
 * events* — curatorial metadata (name, company, sector, pair symbol) lives
 * in agents.config.json and is merged in at query time by src/api/index.ts,
 * not stored on-chain-indexed rows. See AQUITY-SPEC.md §4's Agent type.
 *
 * revenueTotal / jobsTotal / distributedToHolders are cumulative, not
 * rolling 30-day windows — the frontend's e30/e24/dist fields want a
 * rolling window, which needs timestamp-bucketed queries. That's a
 * follow-up (aggregate agent_stats_daily by day and sum the trailing N),
 * not attempted here — see README "Known limitations".
 */
export const agentStats = onchainTable("agent_stats", (t) => ({
  ticker: t.text().primaryKey(),

  // Vault (Vault.Deposited / Vault.Released)
  vaultBalance: t.bigint().notNull().default(0n),

  // What has flowed INTO the vault, by source (Splitter.pay / FeeRouter.claimFees).
  // Fungible once in the vault, so this is "backed by", not a claim-side split.
  depositedFromRevenue: t.bigint().notNull().default(0n),
  depositedFromFees: t.bigint().notNull().default(0n),

  // What has actually reached holder wallets (Distributor.Claimed, summed).
  distributedToHolders: t.bigint().notNull().default(0n),

  // The agent's own operating wallet, funded by its (100 - feeSplitBps) share.
  agentWalletFunded: t.bigint().notNull().default(0n),

  // Job activity (Splitter.WorkReceipt).
  revenueTotal: t.bigint().notNull().default(0n),
  jobsTotal: t.integer().notNull().default(0),
  lastPaidAt: t.bigint(),

  // The two dials (AQUITY-SPEC.md §2.2), refreshed opportunistically on
  // every WorkReceipt / FeesClaimedAndSplit via a live contract read —
  // simpler than also handling *ShareUpdated/*SplitUpdated separately, and
  // self-healing if the owner changes them.
  vaultShareBps: t.integer().notNull().default(0),
  feeSplitBps: t.integer().notNull().default(0),

  // Builder vesting (Vesting.Locked / RevenueReported / Released).
  vestingTotalAllocation: t.bigint().notNull().default(0n),
  vestingReleased: t.bigint().notNull().default(0n),
}));

/**
 * Running per-holder balance of each agent's own token, from Transfer logs.
 * This is exactly the raw material a Distributor root-posting job needs to
 * compute time-weighted balances and build an epoch's Merkle tree — see
 * AQUITY-SPEC.md §3.3. Building that job itself is out of scope here; this
 * table is the input it would read.
 */
export const agentTokenBalance = onchainTable(
  "agent_token_balance",
  (t) => ({
    ticker: t.text().notNull(),
    holder: t.hex().notNull(),
    balance: t.bigint().notNull().default(0n),
  }),
  (table) => ({
    pk: primaryKey({ columns: [table.ticker, table.holder] }),
  }),
);

/**
 * Address -> ticker resolution for agents launched through Launcher's
 * auto-deploying `launch()` (see src/Launcher.ts and AQUITY-SPEC.md §10
 * Phase 5) rather than curated by hand in agents.config.json. Populated
 * once per agent from Launcher's own `AgentFullyLaunched` event, then read
 * by every *Auto contract's handler (src/Splitter.ts etc.) to find which
 * ticker's agent_stats row an event belongs to — the dynamic counterpart to
 * agents.ts's static, config-file-built address map.
 */
export const autoAgentAddress = onchainTable("auto_agent_address", (t) => ({
  address: t.hex().primaryKey(),
  ticker: t.text().notNull(),
}));

/**
 * Curatorial metadata for auto-launched agents — the counterpart to
 * agents.config.json's hand-entered company/sector/pairSymbol for the
 * original curated cohort. Populated once from Launcher's
 * `AgentFullyLaunched` event plus one read of the resolved stock token's
 * own name()/symbol(), so nothing here needs hand-entry. See
 * src/api/index.ts, which merges this with agents.config.json.
 */
export const autoAgent = onchainTable("auto_agent", (t) => ({
  ticker: t.text().primaryKey(),
  name: t.text().notNull(),
  sector: t.text().notNull(),
  company: t.text().notNull(),
  pairSymbol: t.text().notNull(),
  pairAddress: t.hex().notNull(),
  agentTokenAddress: t.hex().notNull(),
  vaultAddress: t.hex().notNull(),
  splitterAddress: t.hex().notNull(),
  feeRouterAddress: t.hex().notNull(),
  distributorAddress: t.hex().notNull(),
  vestingAddress: t.hex().notNull(),
  startBlock: t.bigint().notNull(),
}));
