import { ponder } from "ponder:registry";
import { agentStats } from "ponder:schema";
import { resolveTicker } from "./lib/agents";

async function handleLocked({ event, context }: { event: any; context: any }) {
  const ticker = await resolveTicker(event.log.address, context.db);
  if (!ticker) return;

  await context.db
    .insert(agentStats)
    .values({ ticker, vestingTotalAllocation: event.args.totalAllocation })
    .onConflictDoUpdate({ vestingTotalAllocation: event.args.totalAllocation });
}

async function handleReleased({ event, context }: { event: any; context: any }) {
  const ticker = await resolveTicker(event.log.address, context.db);
  if (!ticker) return;

  await context.db
    .insert(agentStats)
    .values({ ticker, vestingReleased: event.args.amount })
    .onConflictDoUpdate((row: { vestingReleased: bigint }) => ({ vestingReleased: row.vestingReleased + event.args.amount }));
}

ponder.on("Vesting:Locked", handleLocked);
ponder.on("VestingAuto:Locked", handleLocked);
ponder.on("Vesting:Released", handleReleased);
ponder.on("VestingAuto:Released", handleReleased);
