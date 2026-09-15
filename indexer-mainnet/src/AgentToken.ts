import { ponder } from "ponder:registry";
import { agentTokenTransfer } from "ponder:schema";

/**
 * Records every Transfer of every agent token, full history (not just a
 * running balance) — Phase B's distribution job needs to reconstruct each
 * holder's time-weighted balance within an arbitrary epoch window, which a
 * running-total table can't answer on its own.
 *
 * Keyed by the token's own address, not ticker — see ponder.schema.ts's
 * doc comment on agentTokenTransfer for why (a real ordering bug found via
 * this session's own fork/live testing: a ticker reverse-index wouldn't
 * exist yet for a token's very first transfer).
 */
ponder.on("AgentTokenAuto:Transfer", async ({ event, context }) => {
  await context.db.insert(agentTokenTransfer).values({
    id: `${event.block.number}-${event.log.logIndex}`,
    agentToken: event.log.address,
    from: event.args.from,
    to: event.args.to,
    value: event.args.value,
    blockNumber: event.block.number,
    timestamp: event.block.timestamp,
  });
});
