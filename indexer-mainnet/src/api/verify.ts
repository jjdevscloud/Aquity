import { randomBytes } from "node:crypto";
import { Hono } from "hono";
import { privateKeyToAccount } from "viem/accounts";

/**
 * Real implementation of the mandate flow's X-verification step and the
 * `verifier` role AgentRegistry.sol expects: an off-chain backend that
 * reads a claim post and, once confirmed, signs an EIP-712 `XVerification`
 * attestation the contract checks on-chain (see _checkVerifierSignature).
 *
 * Differs from /indexer's version (testnet, human self-signs as its own
 * agent) in exactly one way: the thing posted to X is the *agent's own
 * wallet address*, not a random code — that's what ties the human's
 * verified X account to a specific agent wallet it doesn't control the
 * key for. No X Developer API access is used or required — Twitter/X's
 * public oEmbed endpoint (unauthenticated, meant for embedding tweets on
 * other sites) is enough to read a specific post back.
 */

const registryAddress = process.env.AGENT_REGISTRY_ADDRESS as `0x${string}` | undefined;
const chainId = Number(process.env.ROBINHOOD_CHAIN_ID);

// Trim and unquote defensively — a copy-paste into an env var UI easily
// picks up surrounding quotes or trailing whitespace, and viem's
// privateKeyToAccount rejects anything that isn't exactly 0x + 64 hex chars.
const rawVerifierKey = process.env.VERIFIER_PRIVATE_KEY?.trim().replace(/^['"]|['"]$/g, "");
const verifierKey =
  rawVerifierKey && /^0x[0-9a-fA-F]{64}$/.test(rawVerifierKey) ? (rawVerifierKey as `0x${string}`) : undefined;

if (process.env.VERIFIER_PRIVATE_KEY && !verifierKey) {
  console.error(
    "[verify] VERIFIER_PRIVATE_KEY is set but isn't a valid 0x-prefixed 32-byte key — X verification will 503 until it's fixed",
  );
}

// A bad key must only disable /api/verify/*, never take down the rest of
// the API.
let verifierAccount: ReturnType<typeof privateKeyToAccount> | null = null;
if (verifierKey) {
  try {
    verifierAccount = privateKeyToAccount(verifierKey);
  } catch (err) {
    console.error("[verify] Failed to load VERIFIER_PRIVATE_KEY:", err);
  }
}

const domain = {
  name: "AquityAgentRegistry",
  version: "1",
  chainId,
  verifyingContract: registryAddress,
} as const;

const types = {
  XVerification: [
    { name: "owner", type: "address" },
    { name: "agentId", type: "string" },
    { name: "xHandle", type: "string" },
    { name: "nonce", type: "uint256" },
  ],
} as const;

type Pending = {
  nonce: string;
  owner: string;
  agentId: string;
  xHandle: string;
  agentKey: string;
  expiresAt: number;
};

// In-memory is fine here: a claim is generated and confirmed within minutes
// by the same visitor, and losing pending state on a restart just means
// clicking "check now" again. Nothing about registration itself depends on
// this surviving a redeploy — AgentRegistry.sol only records the final
// signed attestation, not this handshake.
const pending = new Map<string, Pending>();
const TTL_MS = 30 * 60 * 1000;

function pendingKey(owner: string, agentId: string, xHandle: string) {
  return `${owner.toLowerCase()}:${agentId}:${xHandle.toLowerCase()}`;
}

function normalizeHandle(h: string) {
  return h.trim().replace(/^@/, "").toLowerCase();
}

function sweepExpired() {
  const now = Date.now();
  for (const [key, v] of pending) {
    if (v.expiresAt < now) pending.delete(key);
  }
}

const app = new Hono();

app.post("/api/verify/start", async (c) => {
  if (!verifierAccount || !registryAddress || !Number.isFinite(chainId)) {
    return c.json({ error: "X verification is not configured on this server" }, 503);
  }

  const body = await c.req.json().catch(() => null);
  const owner = typeof body?.owner === "string" ? body.owner : "";
  const agentId = typeof body?.agentId === "string" ? body.agentId.trim() : "";
  const xHandle = normalizeHandle(typeof body?.xHandle === "string" ? body.xHandle : "");
  const agentKey = typeof body?.agentKey === "string" ? body.agentKey : "";

  if (!/^0x[0-9a-fA-F]{40}$/.test(owner)) return c.json({ error: "Missing or invalid owner address" }, 400);
  if (!/^0x[0-9a-fA-F]{40}$/.test(agentKey)) return c.json({ error: "Missing or invalid agent wallet address" }, 400);
  if (!agentId) return c.json({ error: "Missing agent ID" }, 400);
  if (!xHandle) return c.json({ error: "Missing X handle" }, 400);

  sweepExpired();

  // uint256 on-chain — draw from the full 256-bit space, not Node's
  // randomInt (capped at 2^48).
  const nonce = BigInt(`0x${randomBytes(32).toString("hex")}`).toString();

  pending.set(pendingKey(owner, agentId, xHandle), {
    nonce,
    owner,
    agentId,
    xHandle,
    agentKey,
    expiresAt: Date.now() + TTL_MS,
  });

  return c.json({ nonce, agentKey });
});

app.post("/api/verify/confirm", async (c) => {
  if (!verifierAccount || !registryAddress || !Number.isFinite(chainId)) {
    return c.json({ error: "X verification is not configured on this server" }, 503);
  }

  const body = await c.req.json().catch(() => null);
  const owner = typeof body?.owner === "string" ? body.owner : "";
  const agentId = typeof body?.agentId === "string" ? body.agentId.trim() : "";
  const xHandle = normalizeHandle(typeof body?.xHandle === "string" ? body.xHandle : "");
  const nonce = typeof body?.nonce === "string" ? body.nonce : "";
  const tweetUrl = typeof body?.tweetUrl === "string" ? body.tweetUrl.trim() : "";

  if (!/^0x[0-9a-fA-F]{40}$/.test(owner)) return c.json({ error: "Missing or invalid owner address" }, 400);
  if (!tweetUrl) return c.json({ error: "Paste the link to your post first" }, 400);

  sweepExpired();
  const key = pendingKey(owner, agentId, xHandle);
  const record = pending.get(key);
  if (!record || record.nonce !== nonce) {
    return c.json({ error: "No pending verification for that handle — start again" }, 404);
  }

  let oembed: { author_url?: string; html?: string };
  try {
    const res = await fetch(
      `https://publish.twitter.com/oembed?omit_script=true&dnt=true&url=${encodeURIComponent(tweetUrl)}`,
    );
    if (!res.ok) throw new Error(`oEmbed returned ${res.status}`);
    oembed = (await res.json()) as typeof oembed;
  } catch {
    return c.json(
      { error: "Couldn't read that post — make sure the link is correct and the post is public" },
      422,
    );
  }

  const postedHandle = normalizeHandle((oembed.author_url ?? "").split("/").pop() ?? "");
  if (!postedHandle || postedHandle !== record.xHandle) {
    return c.json({ error: `That post isn't from @${record.xHandle}` }, 422);
  }
  if (!oembed.html || !oembed.html.toLowerCase().includes(record.agentKey.toLowerCase())) {
    return c.json({ error: "That post doesn't contain your agent's wallet address" }, 422);
  }

  const verifierSignature = await verifierAccount.signTypedData({
    domain,
    types,
    primaryType: "XVerification",
    message: {
      owner: owner as `0x${string}`,
      agentId,
      xHandle: record.xHandle,
      nonce: BigInt(record.nonce),
    },
  });

  pending.delete(key);

  return c.json({ verifierSignature, xNonce: record.nonce, xHandle: record.xHandle });
});

export default app;
