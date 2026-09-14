import { ponder } from "ponder:registry";
import { agentIdentity } from "ponder:schema";

ponder.on("AgentRegistry:AgentRegistered", async ({ event, context }) => {
  // xHandle isn't in the event (kept out to save gas) — one extra read here,
  // once per agent ever registered, not per block.
  const onchainAgent = await context.client.readContract({
    abi: context.contracts.AgentRegistry.abi,
    address: event.log.address,
    functionName: "agents",
    args: [event.args.tokenId],
  });

  await context.db
    .insert(agentIdentity)
    .values({
      ticker: event.args.ticker,
      tokenId: event.args.tokenId,
      owner: event.args.owner,
      agentId: event.args.agentId,
      xHandle: onchainAgent.xHandle,
      pairAddress: event.args.pair,
      agentTokenAddress: event.args.agentToken,
      registeredAt: event.block.timestamp,
    })
    .onConflictDoUpdate({
      owner: event.args.owner,
      xHandle: onchainAgent.xHandle,
    });
});
