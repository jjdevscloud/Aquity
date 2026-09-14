import { ponder } from "ponder:registry";
import { agentStats } from "ponder:schema";
import { agentForAddress } from "./lib/agents";

ponder.on("Vesting:Locked", async ({ event, context }) => {
  const hit = agentForAddress(event.log.address);
  if (!hit) return;

  await context.db
    .insert(agentStats)
    .values({ ticker: hit.agent.ticker, vestingTotalAllocation: event.args.totalAllocation })
    .onConflictDoUpdate({ vestingTotalAllocation: event.args.totalAllocation });
});

ponder.on("Vesting:Released", async ({ event, context }) => {
  const hit = agentForAddress(event.log.address);
  if (!hit) return;

  await context.db
    .insert(agentStats)
    .values({ ticker: hit.agent.ticker, vestingReleased: event.args.amount })
    .onConflictDoUpdate((row) => ({ vestingReleased: row.vestingReleased + event.args.amount }));
});
