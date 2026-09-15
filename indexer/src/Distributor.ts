import { ponder } from "ponder:registry";
import { agentStats } from "ponder:schema";
import { resolveTicker } from "./lib/agents";

async function handleClaimed({ event, context }: { event: any; context: any }) {
  const ticker = await resolveTicker(event.log.address, context.db);
  if (!ticker) return;

  await context.db
    .insert(agentStats)
    .values({ ticker, distributedToHolders: event.args.amount })
    .onConflictDoUpdate((row: { distributedToHolders: bigint }) => ({
      distributedToHolders: row.distributedToHolders + event.args.amount,
    }));
}

ponder.on("Distributor:Claimed", handleClaimed);
ponder.on("DistributorAuto:Claimed", handleClaimed);
