import { ponder } from "ponder:registry";
import { agentTokenBalance } from "ponder:schema";
import { agentForAddress } from "./lib/agents";

const ZERO = "0x0000000000000000000000000000000000000000";

ponder.on("AgentToken:Transfer", async ({ event, context }) => {
  const hit = agentForAddress(event.log.address);
  if (!hit) return;
  const { ticker } = hit.agent;
  const { from, to, value } = event.args;

  if (from !== ZERO) {
    await context.db
      .insert(agentTokenBalance)
      .values({ ticker, holder: from, balance: -value })
      .onConflictDoUpdate((row) => ({ balance: row.balance - value }));
  }
  if (to !== ZERO) {
    await context.db
      .insert(agentTokenBalance)
      .values({ ticker, holder: to, balance: value })
      .onConflictDoUpdate((row) => ({ balance: row.balance + value }));
  }
});
