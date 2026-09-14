import { Hono } from "hono";
import { cors } from "hono/cors";
import { db } from "ponder:api";
import { agentIdentity, agentStats, agentTokenBalance } from "ponder:schema";
import { agents as agentConfigs } from "../lib/agents";

const app = new Hono();
app.use("/api/*", cors());

/**
 * Shapes AQUITY-SPEC.md §4's Agent type from indexed on-chain data plus
 * agents.config.json's curatorial metadata. See aquity.html's
 * agentFromIndexer() for the matching frontend-side field mapping, and this
 * project's README "Known limitations" for what's a real computed value
 * here versus an honest placeholder (prices, revenue grading, skills).
 */
app.get("/api/agents", async (c) => {
  const [statsRows, identityRows, balanceRows] = await Promise.all([
    db.select().from(agentStats),
    db.select().from(agentIdentity),
    db.select().from(agentTokenBalance),
  ]);

  const statsByTicker = new Map(statsRows.map((row) => [row.ticker, row]));
  const identityByTicker = new Map(identityRows.map((row) => [row.ticker, row]));

  const holdersByTicker = new Map<string, number>();
  for (const row of balanceRows) {
    if (row.balance > 0n) {
      holdersByTicker.set(row.ticker, (holdersByTicker.get(row.ticker) ?? 0) + 1);
    }
  }

  const nowSeconds = Math.floor(Date.now() / 1000);

  const result = agentConfigs.map((config) => {
    const stats = statsByTicker.get(config.ticker);
    const identity = identityByTicker.get(config.ticker);
    const jobsTotal = stats?.jobsTotal ?? 0;
    const lastPaidAt = stats?.lastPaidAt ?? null;
    const daysSincePaid =
      lastPaidAt !== null ? Math.floor((nowSeconds - Number(lastPaidAt)) / 86_400) : null;

    // AQUITY-SPEC.md §2.5 lifecycle. "stalled" at 30 days is the delisting
    // threshold in the spec; the actual delist-and-return-pro-rata action
    // isn't implemented anywhere — this only affects the displayed status.
    const status: "new" | "busy" | "stalled" =
      jobsTotal === 0 ? "new" : daysSincePaid !== null && daysSincePaid >= 30 ? "stalled" : "busy";

    return {
      ticker: config.ticker,
      name: config.name,
      owner: identity?.owner ?? null,
      xHandle: identity?.xHandle ?? null,
      agentId: identity?.agentId ?? null,
      pair: config.pairSymbol,
      company: config.company,
      sector: config.sector,
      operator: config.operator ?? null,

      // Not indexed here — needs a price feed (Chainlink latestRoundData()
      // or a DEX quote, AQUITY-SPEC.md §9 "Prices"). 0 rather than a
      // fabricated number.
      stockPrice: 0,
      tokenPrice: 0,
      supply: 0,

      holders: holdersByTicker.get(config.ticker) ?? 0,
      status,
      daysSincePaid,

      feeSplit: (stats?.feeSplitBps ?? 0) / 100,
      vaultShare: (stats?.vaultShareBps ?? 0) / 100,
      agentBalance: toDisplayAmount(stats?.agentWalletFunded),
      vault: toDisplayAmount(stats?.vaultBalance),

      distributed: toDisplayAmount(stats?.distributedToHolders),
      fromRevenue: toDisplayAmount(stats?.depositedFromRevenue),
      fromFees: toDisplayAmount(stats?.depositedFromFees),

      // Cumulative-to-date, not yet a rolling 30d/24h window — that needs a
      // day-bucketed table this indexer doesn't build yet.
      revenue30d: toDisplayAmount(stats?.revenueTotal),
      revenue24h: 0,
      jobs: jobsTotal,

      // Revenue grading (AQUITY-SPEC.md §3.4) isn't implemented anywhere in
      // the contracts or this indexer yet — these are honest placeholders,
      // not computed values. See README "Known limitations".
      completionRate: 100,
      margin: 0,
      quality: jobsTotal > 0 ? [100, 0, 0] : [0, 0, 0],
      skills: [false, false, false, false, false],
      history: [] as number[],

      vestingTotalAllocation: toDisplayAmount(stats?.vestingTotalAllocation),
      vestingReleased: toDisplayAmount(stats?.vestingReleased),
    };
  });

  return c.json(result);
});

/**
 * Raw amounts are base units. Assumes 18 decimals, which most ERC-20s use
 * but isn't guaranteed for USDG or a given tokenized stock — if either uses
 * a different decimals(), this needs a per-token divisor, not a constant.
 */
function toDisplayAmount(value: bigint | null | undefined): number {
  if (value === null || value === undefined) return 0;
  return Number(value) / 1e18;
}

export default app;
