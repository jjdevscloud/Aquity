import { ponder } from "ponder:registry";
import { ponsLaunch } from "ponder:schema";
import { createPublicClient, http } from "viem";
import { AgentRegistryAbi } from "../abis/AgentRegistry";

const ERC20_NAME_ABI = [
  { type: "function", name: "name", inputs: [], outputs: [{ name: "", type: "string" }], stateMutability: "view" },
] as const;

const registryAddress = process.env.AGENT_REGISTRY_ADDRESS as `0x${string}`;

// A plain, unpinned client — deliberately NOT context.client, which pins
// every read to the event's own historical block. ERC-20 name() is
// immutable, so there's no correctness reason to read it historically, and
// doing so broke for real: a from-scratch backfill months after a token's
// actual launch block found the RPC provider's archive depth no longer
// reached that old block ("metadata is not found"), silently dropping the
// ponsLaunch row for any agent launched further back than the provider's
// archive window. Reading at latest instead sidesteps that permanently.
const client = createPublicClient({ transport: http(process.env.ROBINHOOD_MAINNET_RPC_URL) });

async function handleAgentLaunched({ event, context }: { event: any; context: any }) {
  // `name` isn't in the event (kept out to save gas, same reasoning as
  // AgentRegistry.sol's xHandle) — the deployed token itself has a real
  // ERC-20 name(), so read it back rather than duplicating the string.
  const name = await client.readContract({
    abi: ERC20_NAME_ABI,
    address: event.args.agentToken,
    functionName: "name",
  });

  await context.db
    .insert(ponsLaunch)
    .values({
      ticker: event.args.ticker,
      name,
      agentToken: event.args.agentToken,
      curve: event.args.curve,
      startBlock: event.block.number,
    })
    .onConflictDoNothing();
}

// Same handler bound to both contracts — PonsLauncherV2 (Phase B) is a
// separate tracked contract (see ponder.config.ts) with a byte-identical
// AgentLaunchedOnPons event, since AgentRegistry.setLauncher() was
// repointed there mid-session and every launch since goes through it.
ponder.on("PonsLauncher:AgentLaunchedOnPons", handleAgentLaunched);
ponder.on("PonsLauncherV2:AgentLaunchedOnPons", handleAgentLaunched);
ponder.on("PonsLauncherV0:AgentLaunchedOnPons", handleAgentLaunched);

// V2-only: fires in the same transaction as AgentLaunchedOnPons, right
// after it, only when a launch opted into enforced routing. The event
// itself only carries tokenId (not ticker) — same reasoning as
// AgentRegistry.ts's own agentKey/xHandle reads, resolve it via the
// registry's own agents(tokenId) rather than guessing a lookup table.
// ponsLaunch's row for this ticker is guaranteed to already exist: Ponder
// processes both events in the same transaction in log order, and
// AgentLaunchedOnPons (always emitted first by PonsLauncherV2.sol) already
// inserted it above.
ponder.on("PonsLauncherV2:EnforcedRevenueRoutingDeployed", async ({ event, context }: { event: any; context: any }) => {
  const [ticker] = await client.readContract({
    abi: AgentRegistryAbi,
    address: registryAddress,
    functionName: "agents",
    args: [event.args.tokenId],
  });

  await context.db.update(ponsLaunch, { ticker }).set({
    vault: event.args.vault,
    distributor: event.args.distributor,
    revenueRouter: event.args.revenueRouter,
  });
});
