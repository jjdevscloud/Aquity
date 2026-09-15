import agentsJson from "../../agents.config.json";
import { autoAgentAddress } from "../../ponder.schema";

/**
 * The hand-picked cohort's static config — see agents.config.json and the
 * README. AQUITY-SPEC.md §10 Phase 5: registration isn't permissionless yet
 * ("twenty hand-picked agents"), so Splitter/Vault/FeeRouter/Distributor
 * addresses — deployed one-off per agent via the Foundry scripts, not
 * through an on-chain factory — are curated here rather than discovered.
 */
export type AgentConfig = {
  ticker: string;
  name: string;
  company: string;
  sector: string;
  operator?: string;
  pairSymbol: string;
  pairAddress: `0x${string}`;
  agentTokenAddress: `0x${string}`;
  splitterAddress: `0x${string}`;
  vaultAddress: `0x${string}`;
  feeRouterAddress: `0x${string}`;
  distributorAddress: `0x${string}`;
  vestingAddress: `0x${string}`;
  /** Block each of this agent's contracts was deployed at. */
  startBlock: number;
};

export const agents = agentsJson as AgentConfig[];

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as const;

/** Ponder's `address` config wants at least one entry; falls back to a
 * harmless placeholder when no agents are configured yet so the indexer
 * still boots with an empty board rather than failing to start. */
function addressesOrPlaceholder(pick: (a: AgentConfig) => `0x${string}`) {
  const list = agents.map(pick);
  return list.length > 0 ? list : [ZERO_ADDRESS];
}

export const splitterAddresses = addressesOrPlaceholder((a) => a.splitterAddress);
export const vaultAddresses = addressesOrPlaceholder((a) => a.vaultAddress);
export const feeRouterAddresses = addressesOrPlaceholder((a) => a.feeRouterAddress);
export const distributorAddresses = addressesOrPlaceholder((a) => a.distributorAddress);
export const vestingAddresses = addressesOrPlaceholder((a) => a.vestingAddress);
export const agentTokenAddresses = addressesOrPlaceholder((a) => a.agentTokenAddress);

export const minStartBlock =
  agents.length > 0 ? Math.min(...agents.map((a) => a.startBlock)) : 0;

type Role = "splitter" | "vault" | "feeRouter" | "distributor" | "vesting" | "agentToken";

const addressToAgent = new Map<string, { agent: AgentConfig; role: Role }>();
for (const agent of agents) {
  addressToAgent.set(agent.splitterAddress.toLowerCase(), { agent, role: "splitter" });
  addressToAgent.set(agent.vaultAddress.toLowerCase(), { agent, role: "vault" });
  addressToAgent.set(agent.feeRouterAddress.toLowerCase(), { agent, role: "feeRouter" });
  addressToAgent.set(agent.distributorAddress.toLowerCase(), { agent, role: "distributor" });
  addressToAgent.set(agent.vestingAddress.toLowerCase(), { agent, role: "vesting" });
  addressToAgent.set(agent.agentTokenAddress.toLowerCase(), { agent, role: "agentToken" });
}

/** Looks up which agent (and which of its contracts) emitted an event, by
 * the log's own contract address — `event.log.address` in a handler. Only
 * ever finds the curated, agents.config.json cohort; see resolveTicker for
 * the auto-launched counterpart. */
export function agentForAddress(address: string) {
  return addressToAgent.get(address.toLowerCase());
}

/**
 * Ticker for any contract address emitting an event a handler cares about —
 * curated (agents.config.json, checked first, no DB round trip) or
 * auto-launched via Launcher.sol's `AgentFullyLaunched` (src/Launcher.ts
 * writes the auto_agent_address table this falls back to). Every handler
 * that used to call `agentForAddress(...).agent.ticker` should call this
 * instead — see src/Splitter.ts and friends.
 */
/** `db` is a handler's `context.db` — Ponder doesn't export that type standalone. */
export async function resolveTicker(address: `0x${string}`, db: any): Promise<string | undefined> {
  const staticHit = agentForAddress(address);
  if (staticHit) return staticHit.agent.ticker;

  const row = await db.find(autoAgentAddress, { address: address.toLowerCase() });
  return row?.ticker;
}
