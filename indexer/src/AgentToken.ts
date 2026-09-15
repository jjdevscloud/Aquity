import { ponder } from "ponder:registry";
import { agentTokenBalance } from "ponder:schema";
import { resolveTicker } from "./lib/agents";

const ZERO = "0x0000000000000000000000000000000000000000";

async function handleTransfer({ event, context }: { event: any; context: any }) {
  const ticker = await resolveTicker(event.log.address, context.db);
  if (!ticker) return;
  const { from, to, value } = event.args;

  if (from !== ZERO) {
    await context.db
      .insert(agentTokenBalance)
      .values({ ticker, holder: from, balance: -value })
      .onConflictDoUpdate((row: { balance: bigint }) => ({ balance: row.balance - value }));
  }
  if (to !== ZERO) {
    await context.db
      .insert(agentTokenBalance)
      .values({ ticker, holder: to, balance: value })
      .onConflictDoUpdate((row: { balance: bigint }) => ({ balance: row.balance + value }));
  }
}

// AgentToken (curated, agents.config.json) and AgentTokenAuto (any agent
// launched through Launcher.sol's auto-deploying `launch()`) are the same
// ERC-20 ABI watched over two different address sources — see
// ponder.config.ts and src/lib/agents.ts's resolveTicker.
ponder.on("AgentToken:Transfer", handleTransfer);
ponder.on("AgentTokenAuto:Transfer", handleTransfer);
