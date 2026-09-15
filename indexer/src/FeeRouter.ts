import { ponder } from "ponder:registry";
import { agentStats } from "ponder:schema";
import { FeeRouterAbi } from "../abis/FeeRouter";
import { resolveTicker } from "./lib/agents";

async function handleFeesClaimedAndSplit({ event, context }: { event: any; context: any }) {
  const ticker = await resolveTicker(event.log.address, context.db);
  if (!ticker) return;

  const feeSplitBps = await context.client.readContract({
    abi: FeeRouterAbi,
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
    .onConflictDoUpdate((row: { depositedFromFees: bigint; agentWalletFunded: bigint }) => ({
      depositedFromFees: row.depositedFromFees + event.args.holderShare,
      agentWalletFunded: row.agentWalletFunded + event.args.agentShare,
      lastPaidAt: event.block.timestamp,
      feeSplitBps: Number(feeSplitBps),
    }));
}

ponder.on("FeeRouter:FeesClaimedAndSplit", handleFeesClaimedAndSplit);
ponder.on("FeeRouterAuto:FeesClaimedAndSplit", handleFeesClaimedAndSplit);
