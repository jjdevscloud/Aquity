/**
 * Pure computation for Phase B's distribution job — no DB, no chain, so it
 * can be unit-tested in isolation (see distribution.test.ts). Everything
 * that actually touches Postgres or the RPC lives in postEpochRoot.ts.
 *
 * Implements the mandate's "weighted by balance × time held" rule
 * (AQUITY-SPEC's Distributor design, §3.3/§11.5): each holder's share of an
 * epoch's payout is proportional to the time-integral of their balance
 * over the epoch window, not just their balance at a single snapshot —
 * which is also what makes wash trading (buy right before a snapshot, sell
 * right after) unprofitable.
 */

export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

export interface TransferRow {
  from: string;
  to: string;
  value: bigint;
  timestamp: bigint;
}

/**
 * Returns each holder's balance×seconds accumulated strictly within
 * [epochStart, epochEnd). `transfers` must be every Transfer for this
 * token from genesis through at least epochEnd, sorted ascending by
 * (timestamp, blockNumber, logIndex) — pre-epoch transfers are still
 * needed to reconstruct the balances the epoch actually opens with.
 */
export function computeTimeWeightedShares(
  transfers: TransferRow[],
  epochStart: bigint,
  epochEnd: bigint,
): Map<string, bigint> {
  if (epochEnd <= epochStart) throw new Error("epochEnd must be after epochStart");

  const balances = new Map<string, bigint>();
  const weighted = new Map<string, bigint>();
  let cursor = epochStart;

  const apply = (t: TransferRow) => {
    if (t.from !== ZERO_ADDRESS) balances.set(t.from, (balances.get(t.from) ?? 0n) - t.value);
    if (t.to !== ZERO_ADDRESS) balances.set(t.to, (balances.get(t.to) ?? 0n) + t.value);
  };

  const accrue = (until: bigint) => {
    if (until <= cursor) return;
    const duration = until - cursor;
    for (const [holder, bal] of balances) {
      if (bal <= 0n) continue;
      weighted.set(holder, (weighted.get(holder) ?? 0n) + bal * duration);
    }
    cursor = until;
  };

  for (const t of transfers) {
    if (t.timestamp <= epochStart) {
      apply(t); // pre-epoch — establishes the balances the epoch opens with, no weight accrued
      continue;
    }
    if (t.timestamp >= epochEnd) break; // this and every later transfer belong to a future epoch
    accrue(t.timestamp); // credit the gap since the last event at the balances that held during it
    apply(t);
  }
  accrue(epochEnd);

  return weighted;
}

/**
 * Splits `totalAllocated` proportionally to each holder's weight. Integer
 * division remainder goes entirely to the last entry (stable given a
 * fixed input order) rather than being lost — every unit of
 * totalAllocated is always accounted for.
 */
export function allocateByWeight(weighted: Map<string, bigint>, totalAllocated: bigint): Map<string, bigint> {
  const entries = [...weighted.entries()].filter(([, w]) => w > 0n);
  const totalWeight = entries.reduce((sum, [, w]) => sum + w, 0n);
  const allocations = new Map<string, bigint>();
  if (totalWeight === 0n || totalAllocated === 0n) return allocations;

  let allocatedSoFar = 0n;
  entries.forEach(([holder, w], i) => {
    const amount = i === entries.length - 1 ? totalAllocated - allocatedSoFar : (totalAllocated * w) / totalWeight;
    if (amount > 0n) allocations.set(holder, amount);
    allocatedSoFar += amount;
  });
  return allocations;
}
