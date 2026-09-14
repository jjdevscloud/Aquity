import { ponder } from "ponder:registry";
import { agentStats } from "ponder:schema";
import { agentForAddress } from "./lib/agents";

ponder.on("Splitter:WorkReceipt", async ({ event, context }) => {
  const hit = agentForAddress(event.log.address);
  if (!hit) return; // placeholder address with no agents configured yet
  const { ticker } = hit.agent;

  const vaultShareBps = await context.client.readContract({
    abi: context.contracts.Splitter.abi,
    address: event.log.address,
    functionName: "vaultShareBps",
  });

  await context.db
    .insert(agentStats)
    .values({
      ticker,
      revenueTotal: event.args.amountIn,
      depositedFromRevenue: event.args.stockOut,
      jobsTotal: 1,
      lastPaidAt: event.block.timestamp,
      vaultShareBps: Number(vaultShareBps),
    })
    .onConflictDoUpdate((row) => ({
      revenueTotal: row.revenueTotal + event.args.amountIn,
      depositedFromRevenue: row.depositedFromRevenue + event.args.stockOut,
      jobsTotal: row.jobsTotal + 1,
      lastPaidAt: event.block.timestamp,
      vaultShareBps: Number(vaultShareBps),
    }));
});
