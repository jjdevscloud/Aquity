import { ponder } from "ponder:registry";
import { agentStats } from "ponder:schema";
import { resolveTicker } from "./lib/agents";

async function handleDeposited({ event, context }: { event: any; context: any }) {
  const ticker = await resolveTicker(event.log.address, context.db);
  if (!ticker) return;

  await context.db
    .insert(agentStats)
    .values({ ticker, vaultBalance: event.args.amount })
    .onConflictDoUpdate((row: { vaultBalance: bigint }) => ({ vaultBalance: row.vaultBalance + event.args.amount }));
}

async function handleReleased({ event, context }: { event: any; context: any }) {
  const ticker = await resolveTicker(event.log.address, context.db);
  if (!ticker) return;

  await context.db
    .insert(agentStats)
    .values({ ticker, vaultBalance: 0n })
    .onConflictDoUpdate((row: { vaultBalance: bigint }) => ({ vaultBalance: row.vaultBalance - event.args.amount }));
}

ponder.on("Vault:Deposited", handleDeposited);
ponder.on("VaultAuto:Deposited", handleDeposited);
ponder.on("Vault:Released", handleReleased);
ponder.on("VaultAuto:Released", handleReleased);
