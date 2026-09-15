import { ponder } from "ponder:registry";
import { agentStats } from "ponder:schema";
import { SplitterAbi } from "../abis/Splitter";
import { resolveTicker } from "./lib/agents";

async function handleWorkReceipt({ event, context }: { event: any; context: any }) {
  const ticker = await resolveTicker(event.log.address, context.db);
  if (!ticker) return; // placeholder address with no agents configured yet

  const vaultShareBps = await context.client.readContract({
    abi: SplitterAbi,
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
    .onConflictDoUpdate((row: { revenueTotal: bigint; depositedFromRevenue: bigint; jobsTotal: number }) => ({
      revenueTotal: row.revenueTotal + event.args.amountIn,
      depositedFromRevenue: row.depositedFromRevenue + event.args.stockOut,
      jobsTotal: row.jobsTotal + 1,
      lastPaidAt: event.block.timestamp,
      vaultShareBps: Number(vaultShareBps),
    }));
}

ponder.on("Splitter:WorkReceipt", handleWorkReceipt);
ponder.on("SplitterAuto:WorkReceipt", handleWorkReceipt);
