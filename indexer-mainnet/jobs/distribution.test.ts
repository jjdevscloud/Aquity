import { test } from "node:test";
import assert from "node:assert/strict";
import { computeTimeWeightedShares, allocateByWeight, ZERO_ADDRESS, type TransferRow } from "./distribution.ts";

const A = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const B = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
const C = "0xcccccccccccccccccccccccccccccccccccccc";

test("single holder for the whole epoch gets full weight", () => {
  const transfers: TransferRow[] = [{ from: ZERO_ADDRESS, to: A, value: 100n, timestamp: 0n }];
  const weighted = computeTimeWeightedShares(transfers, 0n, 100n);
  assert.equal(weighted.get(A), 100n * 100n);
  assert.equal(weighted.size, 1);
});

test("holder who joins mid-epoch is weighted only for the time they held", () => {
  const transfers: TransferRow[] = [
    { from: ZERO_ADDRESS, to: A, value: 100n, timestamp: 0n },
    { from: A, to: B, value: 100n, timestamp: 50n }, // halfway through [0,100)
  ];
  const weighted = computeTimeWeightedShares(transfers, 0n, 100n);
  assert.equal(weighted.get(A), 100n * 50n); // held 100 for the first 50s
  assert.equal(weighted.get(B), 100n * 50n); // held 100 for the last 50s
});

test("transfers before epochStart establish the opening balance without accruing weight", () => {
  const transfers: TransferRow[] = [
    { from: ZERO_ADDRESS, to: A, value: 100n, timestamp: 0n }, // long before the epoch
  ];
  const weighted = computeTimeWeightedShares(transfers, 1000n, 1100n);
  assert.equal(weighted.get(A), 100n * 100n); // held the whole 100s epoch, unaffected by when it originally minted
});

test("a transfer exactly at epochEnd does not count toward this epoch", () => {
  const transfers: TransferRow[] = [
    { from: ZERO_ADDRESS, to: A, value: 100n, timestamp: 0n },
    { from: A, to: B, value: 100n, timestamp: 100n }, // exactly at epochEnd
  ];
  const weighted = computeTimeWeightedShares(transfers, 0n, 100n);
  assert.equal(weighted.get(A), 100n * 100n, "A should be credited for the full epoch");
  assert.equal(weighted.get(B), undefined, "B only receives the transfer at the boundary, after the epoch closes");
});

test("wash trading (buy then sell within the same epoch) earns less weight than holding through it", () => {
  const held: TransferRow[] = [{ from: ZERO_ADDRESS, to: A, value: 100n, timestamp: 0n }];
  const washed: TransferRow[] = [
    { from: ZERO_ADDRESS, to: B, value: 100n, timestamp: 10n },
    { from: B, to: C, value: 100n, timestamp: 20n }, // held for only 10 of the 100 seconds
  ];
  const weightedHeld = computeTimeWeightedShares(held, 0n, 100n);
  const weightedWashed = computeTimeWeightedShares(washed, 0n, 100n);
  const bWeight = weightedWashed.get(B) ?? 0n;
  assert.ok((weightedHeld.get(A) ?? 0n) > bWeight, "holding the whole epoch must out-earn a quick round-trip");
  assert.equal(bWeight, 100n * 10n);
});

test("epochEnd must be after epochStart", () => {
  assert.throws(() => computeTimeWeightedShares([], 100n, 100n));
  assert.throws(() => computeTimeWeightedShares([], 200n, 100n));
});

test("allocateByWeight splits proportionally and accounts for every unit via the remainder", () => {
  const weighted = new Map([
    [A, 60n],
    [B, 30n],
    [C, 10n],
  ]);
  const allocations = allocateByWeight(weighted, 1000n);
  assert.equal(allocations.get(A), 600n);
  assert.equal(allocations.get(B), 300n);
  // C gets the remainder rather than losing dust to integer division —
  // 10/100*1000 = 100 exactly here, but the mechanism is what's tested.
  const total = [...allocations.values()].reduce((s, v) => s + v, 0n);
  assert.equal(total, 1000n, "every unit of totalAllocated must be accounted for");
});

test("allocateByWeight handles an odd total that doesn't divide evenly", () => {
  const weighted = new Map([
    [A, 1n],
    [B, 1n],
    [C, 1n],
  ]);
  const allocations = allocateByWeight(weighted, 100n);
  const total = [...allocations.values()].reduce((s, v) => s + v, 0n);
  assert.equal(total, 100n, "no dust lost to rounding — the last holder absorbs the remainder");
});

test("allocateByWeight returns empty when nobody held anything", () => {
  const allocations = allocateByWeight(new Map(), 1000n);
  assert.equal(allocations.size, 0);
});

test("allocateByWeight returns empty when totalAllocated is zero", () => {
  const allocations = allocateByWeight(new Map([[A, 100n]]), 0n);
  assert.equal(allocations.size, 0);
});
