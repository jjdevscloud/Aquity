import pg from "pg";

/**
 * Job-owned storage for Phase B's distribution results (posted epochs +
 * per-holder Merkle proofs) — deliberately NOT part of ponder.schema.ts.
 * See that file's comment on why: ponder:api's db is read-only, and there's
 * no on-chain event carrying individual holder/proof data to index (only
 * the Merkle root goes on-chain). Both src/jobs/postEpochRoot.ts (writes,
 * after a real postRoot() tx confirms) and src/api/distribution.ts's public
 * proof endpoint (reads) go through this same small schema via a plain `pg`
 * client — column names here are fully self-defined, not guessed at
 * Drizzle's conventions.
 */

export interface EpochRecord {
  ticker: string;
  epochId: bigint;
  distributor: string;
  merkleRoot: string;
  totalAllocated: bigint;
  epochStart: bigint;
  epochEnd: bigint;
  postedAt: bigint;
  txHash: string;
}

export interface ProofRecord {
  ticker: string;
  epochId: bigint;
  holder: string;
  amount: bigint;
  proof: string[];
}

let pool: pg.Pool | null = null;

export function getPool(): pg.Pool {
  if (!pool) {
    const connectionString = process.env.DATABASE_URL;
    if (!connectionString) throw new Error("Set DATABASE_URL — required for Phase B's distribution tables");
    pool = new pg.Pool({ connectionString });
  }
  return pool;
}

export async function ensureDistributionSchema(client: pg.Pool = getPool()): Promise<void> {
  // Two separate statements, not one semicolon-joined string — some
  // Postgres-wire-protocol implementations (confirmed with pglite, used to
  // validate this exact SQL locally) reject multiple commands inside a
  // single prepared/parameterized query.
  await client.query(`
    CREATE TABLE IF NOT EXISTS aquity_distribution_epoch (
      ticker TEXT NOT NULL,
      epoch_id NUMERIC NOT NULL,
      distributor TEXT NOT NULL,
      merkle_root TEXT NOT NULL,
      total_allocated NUMERIC NOT NULL,
      epoch_start NUMERIC NOT NULL,
      epoch_end NUMERIC NOT NULL,
      posted_at NUMERIC NOT NULL,
      tx_hash TEXT NOT NULL,
      PRIMARY KEY (ticker, epoch_id)
    )
  `);
  await client.query(`
    CREATE TABLE IF NOT EXISTS aquity_distribution_proof (
      ticker TEXT NOT NULL,
      epoch_id NUMERIC NOT NULL,
      holder TEXT NOT NULL,
      amount NUMERIC NOT NULL,
      proof JSONB NOT NULL,
      PRIMARY KEY (ticker, epoch_id, holder)
    )
  `);
}

export async function insertEpoch(record: EpochRecord, client: pg.Pool = getPool()): Promise<void> {
  await client.query(
    `INSERT INTO aquity_distribution_epoch
       (ticker, epoch_id, distributor, merkle_root, total_allocated, epoch_start, epoch_end, posted_at, tx_hash)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
     ON CONFLICT (ticker, epoch_id) DO NOTHING`,
    [
      record.ticker,
      record.epochId.toString(),
      record.distributor,
      record.merkleRoot,
      record.totalAllocated.toString(),
      record.epochStart.toString(),
      record.epochEnd.toString(),
      record.postedAt.toString(),
      record.txHash,
    ],
  );
}

export async function insertProofs(proofs: ProofRecord[], client: pg.Pool = getPool()): Promise<void> {
  for (const p of proofs) {
    await client.query(
      `INSERT INTO aquity_distribution_proof (ticker, epoch_id, holder, amount, proof)
       VALUES ($1,$2,$3,$4,$5)
       ON CONFLICT (ticker, epoch_id, holder) DO NOTHING`,
      [p.ticker, p.epochId.toString(), p.holder.toLowerCase(), p.amount.toString(), JSON.stringify(p.proof)],
    );
  }
}

export async function getLastEpoch(ticker: string, client: pg.Pool = getPool()): Promise<{ epochId: bigint; epochEnd: bigint; totalAllocated: bigint; distributor: string } | null> {
  const res = await client.query(
    `SELECT epoch_id, epoch_end, total_allocated, distributor FROM aquity_distribution_epoch
     WHERE ticker = $1 ORDER BY epoch_id DESC LIMIT 1`,
    [ticker],
  );
  const row = res.rows[0];
  if (!row) return null;
  return { epochId: BigInt(row.epoch_id), epochEnd: BigInt(row.epoch_end), totalAllocated: BigInt(row.total_allocated), distributor: row.distributor };
}

export async function sumPreviousAllocations(ticker: string, client: pg.Pool = getPool()): Promise<bigint> {
  const res = await client.query(`SELECT COALESCE(SUM(total_allocated), 0) AS total FROM aquity_distribution_epoch WHERE ticker = $1`, [ticker]);
  return BigInt(res.rows[0].total);
}

export async function getProof(ticker: string, epochId: string, holder: string, client: pg.Pool = getPool()): Promise<{ amount: string; proof: string[] } | null> {
  const res = await client.query(
    `SELECT amount, proof FROM aquity_distribution_proof WHERE ticker = $1 AND epoch_id = $2 AND holder = $3`,
    [ticker, epochId, holder.toLowerCase()],
  );
  const row = res.rows[0];
  if (!row) return null;
  return { amount: row.amount.toString(), proof: row.proof };
}
