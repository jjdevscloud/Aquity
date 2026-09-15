import { Hono } from "hono";
import { cors } from "hono/cors";
import { db } from "ponder:api";
import { agentIdentity, ponsLaunch } from "ponder:schema";
import verifyApp from "./verify";
import distributionApp from "./distribution";

const app = new Hono();
app.use("/api/*", cors());
app.route("/", verifyApp);
app.route("/", distributionApp);

/**
 * Real mainnet agents — identity from AgentRegistry, launch facts from
 * PonsLauncher's real Pons v2 launch. Deliberately thin: there's no
 * Vault/Splitter/Distributor for this flow yet (Phase B), so no revenue,
 * vault, or distribution stats to report — trading/price data already
 * lives on Pons itself (and is already served live by GMGN, Axiom, etc.,
 * which is exactly what showed up when this was checked manually). This
 * endpoint is identity + "where to find it," not a stats mirror.
 */
app.get("/api/agents", async (c) => {
  const [identityRows, launchRows] = await Promise.all([
    db.select().from(agentIdentity),
    db.select().from(ponsLaunch),
  ]);

  const launchByTicker = new Map(launchRows.map((row) => [row.ticker, row]));

  const result = identityRows.map((identity) => {
    const launch = launchByTicker.get(identity.ticker);
    return {
      ticker: identity.ticker,
      name: launch?.name ?? identity.ticker,
      owner: identity.owner,
      agentKey: identity.agentKey,
      xHandle: identity.xHandle,
      agentId: identity.agentId,
      pairAddress: identity.pairAddress,
      agentTokenAddress: identity.agentTokenAddress,
      curveAddress: launch?.curve ?? null,
      registeredAt: Number(identity.registeredAt),
      // Only set for enforced-mode agents (see PonsLauncherV2.sol's
      // EnforcedRevenueRoutingDeployed) — null/absent means the agent's own
      // wallet still receives creator fees directly (voluntary mode).
      enforced: !!(launch && launch.vault),
      vaultAddress: launch?.vault ?? null,
      distributorAddress: launch?.distributor ?? null,
      revenueRouterAddress: launch?.revenueRouter ?? null,
      // Confirmed working format (navigated there directly this session).
      // Not adding an Axiom deep link here — its search found our token
      // fine, but its exact token-page URL pattern was never actually
      // confirmed (a misclick landed on an unrelated wallet-tracker panel
      // instead), and this file doesn't guess URLs it hasn't verified.
      links: {
        gmgn: `https://gmgn.ai/robinhood/token/${identity.agentTokenAddress}`,
      },
    };
  });

  return c.json(result);
});

export default app;
