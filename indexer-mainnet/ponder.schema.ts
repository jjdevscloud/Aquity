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
