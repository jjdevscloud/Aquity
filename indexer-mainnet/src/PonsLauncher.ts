import { ponder } from "ponder:registry";
import { ponsLaunch } from "ponder:schema";

const ERC20_NAME_ABI = [
  { type: "function", name: "name", inputs: [], outputs: [{ name: "", type: "string" }], stateMutability: "view" },
] as const;

ponder.on("PonsLauncher:AgentLaunchedOnPons", async ({ event, context }) => {
  // `name` isn't in the event (kept out to save gas, same reasoning as
  // AgentRegistry.sol's xHandle) — the deployed token itself has a real
  // ERC-20 name(), so read it back rather than duplicating the string.
  const name = await context.client.readContract({
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
});
