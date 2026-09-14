import { ponder } from "ponder:registry";
import { agentStats } from "ponder:schema";
import { agentForAddress } from "./lib/agents";

ponder.on("Vault:Deposited", async ({ event, context }) => {
  const hit = agentForAddress(event.log.address);
  if (!hit) return;

  await context.db
    .insert(agentStats)
    .values({ ticker: hit.agent.ticker, vaultBalance: event.args.amount })
    .onConflictDoUpdate((row) => ({ vaultBalance: row.vaultBalance + event.args.amount }));
});

ponder.on("Vault:Released", async ({ event, context }) => {
  const hit = agentForAddress(event.log.address);
  if (!hit) return;

  await context.db
    .insert(agentStats)
    .values({ ticker: hit.agent.ticker, vaultBalance: 0n })
    .onConflictDoUpdate((row) => ({ vaultBalance: row.vaultBalance - event.args.amount }));
});
