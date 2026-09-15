import { ponder } from "ponder:registry";
import { autoAgent, autoAgentAddress } from "ponder:schema";
import { ERC20Abi } from "../abis/ERC20";

/**
 * The other half of Launcher.sol's automation (AQUITY-SPEC.md §10 Phase 5):
 * one AgentFullyLaunched event carries every address the agent's revenue
 * stack needs, so a registration never again needs the manual
 * agents.config.json edit + indexer redeploy the very first (YREV) agent
 * did. This handler is what makes that new agent findable at all — without
 * it, none of the *Auto factory contracts (src/Splitter.ts etc.) would know
 * which ticker their events belong to, and src/api/index.ts wouldn't know
 * the agent exists.
 */
ponder.on("Launcher:AgentFullyLaunched", async ({ event, context }) => {
  const { ticker } = event.args;

  const addressRows: { address: `0x${string}`; ticker: string }[] = [
    { address: event.args.agentToken, ticker },
    { address: event.args.vault, ticker },
    { address: event.args.splitter, ticker },
    { address: event.args.feeRouter, ticker },
    { address: event.args.distributor, ticker },
    { address: event.args.vesting, ticker },
  ];
  for (const row of addressRows) {
    await context.db.insert(autoAgentAddress).values(row).onConflictDoNothing();
  }

  // The stock token's own name()/symbol() give us "company"/"pairSymbol"
  // for free — no curation needed, unlike agents.config.json's cohort.
  const [company, pairSymbol] = await Promise.all([
    context.client.readContract({ abi: ERC20Abi, address: event.args.stockToken, functionName: "name" }),
    context.client.readContract({ abi: ERC20Abi, address: event.args.stockToken, functionName: "symbol" }),
  ]);

  await context.db
    .insert(autoAgent)
    .values({
      ticker,
      name: event.args.name,
      sector: event.args.sector,
      company,
      pairSymbol,
      pairAddress: event.args.stockToken,
      agentTokenAddress: event.args.agentToken,
      vaultAddress: event.args.vault,
      splitterAddress: event.args.splitter,
      feeRouterAddress: event.args.feeRouter,
      distributorAddress: event.args.distributor,
      vestingAddress: event.args.vesting,
      startBlock: event.block.number,
    })
    .onConflictDoNothing();
});
