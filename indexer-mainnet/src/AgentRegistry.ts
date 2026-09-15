import { ponder } from "ponder:registry";
import { agentIdentity } from "ponder:schema";

ponder.on("AgentRegistry:AgentRegistered", async ({ event, context }) => {
  // agentKey and xHandle aren't in the event (kept out to save gas) — one
  // extra read here, once per agent ever registered, not per block.
  // agents(tokenId) returns an unnamed tuple in this order (viem doesn't
  // expose multi-output reads as named fields even though the ABI names
  // them): [ticker, name, agentId, agentKey, xHandle, pair, agentToken,
  // registeredAt].
  const [, , , agentKey, xHandle] = await context.client.readContract({
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
      agentKey,
      agentId: event.args.agentId,
      xHandle,
      pairAddress: event.args.pair,
      agentTokenAddress: event.args.agentToken,
      registeredAt: event.block.timestamp,
    })
    .onConflictDoUpdate({
      owner: event.args.owner,
      agentKey,
      xHandle,
    });
});
