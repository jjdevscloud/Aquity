/**
 * Phase B's distribution job — computes one epoch's time-weighted payout
 * for one agent and posts the real Merkle root to its real, deployed
 * Distributor. Manually triggered (not a cron) on purpose: this logic has
 * never run against real money before, and the plan this was built from
 * explicitly calls for a human in the loop for the first several epochs.
 *
 * Run:
 *   npm run post-epoch -- --ticker=KITHGOFO --vault=0x... --distributor=0x...
 *
 * Required env vars (same indexer-mainnet .env.local the server itself
 * uses, plus two new ones):
 *   ROBINHOOD_MAINNET_RPC_URL, DATABASE_URL          — already required
 *   INDEXER_API_BASE          this indexer's own base URL (fetches transfer
 *                             history + agent identity through it — see
 *                             src/api/distribution.ts and src/api/index.ts
 *                             — rather than a second, riskier direct-SQL
 *                             path against Ponder-managed tables)
 *   INTERNAL_JOB_SECRET       must match the running server's value
 *   ROOT_POSTER_PRIVATE_KEY   signs the real postRoot() transaction; the
 *                             address it derives to must match whatever
 *                             PonsLauncherV2/DeployRevenueStackMainnet
 *                             actually set as this Distributor's rootPoster
 */
import { pathToFileURL } from "node:url";
import { createPublicClient, createWalletClient, http, parseAbi, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import { computeTimeWeightedShares, allocateByWeight, type TransferRow } from "./distribution.ts";
import { ensureDistributionSchema, getLastEpoch, sumPreviousAllocations, insertEpoch, insertProofs } from "../src/lib/distributionDb.ts";

const ERC20_ABI = parseAbi(["function balanceOf(address) view returns (uint256)"]);
const DISTRIBUTOR_ABI = parseAbi([
  "function postRoot(uint256 epochId, bytes32 merkleRoot, uint256 totalAllocated) external",
  "function rootPoster() view returns (address)",
]);

function parseArgs(): { ticker: string; vault: Hex; distributor: Hex } {
  const args = Object.fromEntries(
    process.argv.slice(2).map((a) => {
      const [k, v] = a.replace(/^--/, "").split("=");
      return [k, v];
    }),
  );
  const ticker = args.ticker?.toUpperCase();
  const vault = args.vault as Hex | undefined;
  const distributor = args.distributor as Hex | undefined;
  if (!ticker || !vault || !distributor) {
    throw new Error("Usage: post-epoch -- --ticker=TICKER --vault=0x... --distributor=0x...");
  }
  return { ticker, vault, distributor };
}

async function main() {
  const { ticker, vault, distributor } = parseArgs();

  const rpcUrl = process.env.ROBINHOOD_MAINNET_RPC_URL;
  const apiBase = process.env.INDEXER_API_BASE;
  const internalSecret = process.env.INTERNAL_JOB_SECRET;
  const rootPosterKey = process.env.ROOT_POSTER_PRIVATE_KEY as Hex | undefined;
  if (!rpcUrl) throw new Error("Set ROBINHOOD_MAINNET_RPC_URL");
  if (!apiBase) throw new Error("Set INDEXER_API_BASE");
  if (!internalSecret) throw new Error("Set INTERNAL_JOB_SECRET");
  if (!rootPosterKey) throw new Error("Set ROOT_POSTER_PRIVATE_KEY");

  await ensureDistributionSchema();

  const publicClient = createPublicClient({ transport: http(rpcUrl) });
  const account = privateKeyToAccount(rootPosterKey);
  const walletClient = createWalletClient({ account, transport: http(rpcUrl) });

  const onChainRootPoster = await publicClient.readContract({ address: distributor, abi: DISTRIBUTOR_ABI, functionName: "rootPoster" });
  if (onChainRootPoster.toLowerCase() !== account.address.toLowerCase()) {
    throw new Error(`ROOT_POSTER_PRIVATE_KEY derives to ${account.address}, but Distributor.rootPoster() is ${onChainRootPoster}`);
  }

  // ---------- 1. figure out the epoch window and how much is new ----------

  const agentsRes = await fetch(`${apiBase}/api/agents`);
  if (!agentsRes.ok) throw new Error(`GET /api/agents failed: ${agentsRes.status}`);
  const agents = (await agentsRes.json()) as { ticker: string; pairAddress: Hex }[];
  const agent = agents.find((a) => a.ticker === ticker);
  if (!agent) throw new Error(`No agent found for ticker ${ticker}`);

  const last = await getLastEpoch(ticker);
  const epochStart = last?.epochEnd ?? 0n;
  const epochId = (last?.epochId ?? 0n) + 1n;

  const block = await publicClient.getBlock();
  const epochEnd = block.timestamp;
  if (epochEnd <= epochStart) throw new Error("No time has passed since the last epoch — nothing to do");

  const vaultBalance = await publicClient.readContract({ address: agent.pairAddress, abi: ERC20_ABI, functionName: "balanceOf", args: [vault] });
  const previouslyAllocated = await sumPreviousAllocations(ticker);
  const totalAllocated = vaultBalance - previouslyAllocated;

  if (totalAllocated <= 0n) {
    console.log(`Nothing new to distribute for ${ticker} — vault balance ${vaultBalance}, already allocated ${previouslyAllocated}.`);
    return;
  }

  // ---------- 2. compute each holder's time-weighted share ----------

  const transfersRes = await fetch(`${apiBase}/api/internal/transfers/${ticker}`, { headers: { "x-internal-secret": internalSecret } });
  if (!transfersRes.ok) throw new Error(`GET /api/internal/transfers/${ticker} failed: ${transfersRes.status}`);
  const rawTransfers = (await transfersRes.json()) as { from: string; to: string; value: string; timestamp: string }[];
  const transfers: TransferRow[] = rawTransfers.map((t) => ({ from: t.from, to: t.to, value: BigInt(t.value), timestamp: BigInt(t.timestamp) }));

  const weighted = computeTimeWeightedShares(transfers, epochStart, epochEnd);
  const allocations = allocateByWeight(weighted, totalAllocated);

  if (allocations.size === 0) {
    console.log(`No holders held any ${ticker} during [${epochStart}, ${epochEnd}) — skipping this epoch, funds stay in the Vault for next time.`);
    return;
  }

  // ---------- 3. build the real Merkle tree ----------

  const entries = [...allocations.entries()].map(([holder, amount]) => [epochId, holder, amount] as [bigint, string, bigint]);
  const tree = StandardMerkleTree.of(entries, ["uint256", "address", "uint256"]);

  console.log(`Epoch ${epochId} for ${ticker}: ${allocations.size} holders, ${totalAllocated} total, root ${tree.root}`);

  // ---------- 4. post the real root on-chain ----------

  const hash = await walletClient.writeContract({
    address: distributor,
    abi: DISTRIBUTOR_ABI,
    functionName: "postRoot",
    args: [epochId, tree.root as Hex, totalAllocated],
    chain: null,
  });
  console.log(`postRoot tx sent: ${hash} — waiting for confirmation...`);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") throw new Error(`postRoot reverted on-chain: ${hash}`);

  // ---------- 5. persist the epoch + every holder's proof ----------

  await insertEpoch({
    ticker,
    epochId,
    distributor,
    merkleRoot: tree.root,
    totalAllocated,
    epochStart,
    epochEnd,
    postedAt: block.timestamp,
    txHash: hash,
  });

  const proofRecords = [...allocations.entries()].map(([holder, amount], i) => ({
    ticker,
    epochId,
    holder,
    amount,
    proof: tree.getProof(i),
  }));
  await insertProofs(proofRecords);

  console.log(`Done — epoch ${epochId} posted (${hash}) and ${proofRecords.length} proofs stored.`);
}

// Only run when executed directly (`node postEpochRoot.ts ...`), not when
// merely imported — defense in depth alongside living outside src/, after
// Ponder's own dev server was found auto-discovering and importing every
// .ts file under src/ as a potential indexing module, which ran main()
// as an unwanted side effect of that scan.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error(err);
      process.exit(1);
    });
}
