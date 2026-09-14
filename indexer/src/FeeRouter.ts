import { ponder } from "ponder:registry";
import { agentStats } from "ponder:schema";
import { agentForAddress } from "./lib/agents";

ponder.on("FeeRouter:FeesClaimedAndSplit", async ({ event, context }) => {
  const hit = agentForAddress(event.log.address);
  if (!hit) return;
  const { ticker } = hit.agent;

  const feeSplitBps = await context.client.readContract({
    abi: context.contracts.FeeRouter.abi,
    address: event.log.address,
    functionName: "feeSplitBps",
  });

  await context.db
    .insert(agentStats)
    .values({
      ticker,
      depositedFromFees: event.args.holderShare,
      agentWalletFunded: event.args.agentShare,
      lastPaidAt: event.block.timestamp,
      feeSplitBps: Number(feeSplitBps),
    })
    .onConflictDoUpdate((row) => ({
      depositedFromFees: row.depositedFromFees + event.args.holderShare,
      agentWalletFunded: row.agentWalletFunded + event.args.agentShare,
      lastPaidAt: event.block.timestamp,
      feeSplitBps: Number(feeSplitBps),
    }));
});
