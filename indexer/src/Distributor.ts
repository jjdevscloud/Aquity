import { ponder } from "ponder:registry";
import { agentStats } from "ponder:schema";
import { agentForAddress } from "./lib/agents";

ponder.on("Distributor:Claimed", async ({ event, context }) => {
  const hit = agentForAddress(event.log.address);
  if (!hit) return;

  await context.db
    .insert(agentStats)
    .values({ ticker: hit.agent.ticker, distributedToHolders: event.args.amount })
    .onConflictDoUpdate((row) => ({
      distributedToHolders: row.distributedToHolders + event.args.amount,
    }));
});
