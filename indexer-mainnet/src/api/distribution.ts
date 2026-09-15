import { Hono } from "hono";
import { db } from "ponder:api";
import { agentTokenTransfer, ponsLaunch } from "ponder:schema";
import { eq } from "ponder";
import { getProof, getLastEpoch, ensureDistributionSchema } from "../lib/distributionDb";

/**
 * Phase B's distribution surface: one public read endpoint (what the
 * frontend's claim widget fetches) plus one internal read endpoint
 * src/jobs/postEpochRoot.ts (an external script, outside Ponder's own
 * runtime) uses for transfer history — through Ponder's own `db` here,
 * correctly typed, rather than the job guessing at Drizzle's column names
 * over a raw Postgres connection. Posted-epoch/proof data itself lives in a
 * separate, job-owned schema — see src/lib/distributionDb.ts's doc comment
 * for why (ponder:api's db is read-only; this file just reads from that
 * separate schema directly, same as the job writes to it).
 */
const app = new Hono();

// The job (src/jobs/postEpochRoot.ts) also calls this before its first real
// write, but this API can be hit before any epoch has ever been posted —
// without this, a plain "no epoch yet" 404/null response becomes a raw
// "relation does not exist" 500 instead. Cached so it only runs once per
// server lifetime, not per request.
let schemaReady: Promise<void> | null = null;
function ensureSchemaOnce(): Promise<void> {
  if (!schemaReady) schemaReady = ensureDistributionSchema();
  return schemaReady;
}

const INTERNAL_SECRET = process.env.INTERNAL_JOB_SECRET;

function requireInternalSecret(c: any): Response | null {
  if (!INTERNAL_SECRET) return c.json({ error: "INTERNAL_JOB_SECRET not configured on this server" }, 503);
  if (c.req.header("x-internal-secret") !== INTERNAL_SECRET) return c.json({ error: "unauthorized" }, 401);
  return null;
}

/** Public — what the frontend's claim widget fetches. */
app.get("/api/distribution/:ticker/:epoch/proof/:holder", async (c) => {
  await ensureSchemaOnce();
  const ticker = c.req.param("ticker").toUpperCase();
  const epochId = c.req.param("epoch");
  const holder = c.req.param("holder");

  const row = await getProof(ticker, epochId, holder);
  if (!row) return c.json({ error: "no proof for that ticker/epoch/holder" }, 404);

  return c.json({ ticker, epochId, holder: holder.toLowerCase(), amount: row.amount, proof: row.proof });
});

/** Public — lets the frontend's claim widget discover which epoch to ask
 * for a proof against, without needing to guess or increment ids itself. */
app.get("/api/distribution/:ticker/latest", async (c) => {
  await ensureSchemaOnce();
  const ticker = c.req.param("ticker").toUpperCase();
  const last = await getLastEpoch(ticker);
  if (!last) return c.json(null);
  return c.json({ ticker, epochId: last.epochId.toString(), totalAllocated: last.totalAllocated.toString(), distributor: last.distributor });
});

/** Internal — used only by src/jobs/postEpochRoot.ts, which has no other
 * correctly-typed way to read Ponder-indexed transfer history. Resolves
 * ticker -> agentToken via ponsLaunch first — see agentTokenTransfer's
 * schema comment for why transfers are keyed by address, not ticker. */
app.get("/api/internal/transfers/:ticker", async (c) => {
  const denied = requireInternalSecret(c);
  if (denied) return denied;

  const ticker = c.req.param("ticker").toUpperCase();
  const launchRows = await db.select().from(ponsLaunch).where(eq(ponsLaunch.ticker, ticker));
  const launch = launchRows[0];
  if (!launch) return c.json({ error: `no Pons launch found for ticker ${ticker}` }, 404);

  const rows = await db.select().from(agentTokenTransfer).where(eq(agentTokenTransfer.agentToken, launch.agentToken));
  const sorted = rows
    .map((r) => ({ from: r.from, to: r.to, value: r.value.toString(), timestamp: r.timestamp.toString(), blockNumber: r.blockNumber.toString() }))
    .sort((a, b) => (BigInt(a.timestamp) < BigInt(b.timestamp) ? -1 : BigInt(a.timestamp) > BigInt(b.timestamp) ? 1 : Number(BigInt(a.blockNumber) - BigInt(b.blockNumber))));

  return c.json(sorted);
});

export default app;
