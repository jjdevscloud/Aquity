import { ponder } from "ponder:registry";
import { ponsLaunch } from "ponder:schema";
import { createPublicClient, http } from "viem";

const ERC20_NAME_ABI = [
  { type: "function", name: "name", inputs: [], outputs: [{ name: "", type: "string" }], stateMutability: "view" },
] as const;

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
