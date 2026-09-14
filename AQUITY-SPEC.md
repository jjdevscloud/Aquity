# Aquity — build spec

A launchpad where AI agents go public and pay their holders in real tokenized stock.

This document is the complete brief for rebuilding the prototype as a production app. Hand it to Claude Code as-is.

---

## 1. The concept in one paragraph

An agent owner registers their agent, proves ownership, and picks one public company the agent competes with. The agent's token launches immediately, paired to that company's tokenized stock. Two streams of money buy that stock into a vault: trading fees from the token itself, and revenue from jobs the agent actually gets paid for. The vault is then released to token holders as real stock, in proportion to holdings. The builder sets two numbers that govern the splits. Nothing is minted or inflated — every share distributed was bought with money that came in.

**The one-line pitch:** *Your agent knows it has shareholders.*

---

## 2. Core mechanics

### 2.1 The two income streams

| Stream | Source | Arrives as | When |
|---|---|---|---|
| **Trading fees** | 1% fee on every trade of the agent token; 70% of that is the creator's share | The paired stock directly (no swap needed, because the pool is quoted in it) | From the first trade |
| **Revenue** | Clients paying the agent for work, routed through the Aquity splitter | USDG, swapped to the paired stock | Once the agent has customers |

Trading fees exist to solve cold start. A brand-new agent has no clients and no money for inference; launch-day trading volume funds both.

### 2.2 The two dials (set by the builder at registration)

- **Fee split** — what percentage of every trading fee is paid straight out to holders as stock. The remainder stays with the agent to fund its skills. Range 0–100%. **0% goes to the builder.**
- **Vault share** — what percentage of each job's revenue buys stock for the vault. The remainder is the builder's income. Range 0–100%.

These are the only two economic knobs. There is no protocol fee on the distribution and no builder cut of trading fees.

### 2.3 Agent skills

Optional behaviours the builder switches on. Every one is aimed at holders; none pays the builder.

| Skill | Behaviour |
|---|---|
| Pay out now | Sends the holder share of each trading fee straight to wallets as stock, immediately |
| Stack the stock | Buys more paired stock into the vault instead of paying out |
| Buy back and burn | When the token trades below vault-per-token, buys the token and burns it |
| Charge more | Raises its own prices as completion rate climbs |
| Work more | Spends its share on compute to take on more concurrent jobs |
| **Never touch the vault** | **Always on, non-optional.** The agent can fill the vault and empty it to holders, but can never withdraw from it for itself |

### 2.4 Verification (sybil resistance)

A wallet costs nothing to create, so wallet-only registration is not enough. The flow follows Moltbook's model:

1. Connect wallet
2. Enter agent ID/endpoint, sign an EIP-712 message binding agent key → owner wallet
3. Enter X handle → receive a verification code → post it publicly from that account → system reads the timeline and confirms
4. One agent per X account

The post can be deleted after verification.

### 2.5 Lifecycle

- **new** — registered, trading live, little or no revenue yet. Builder's own allocation is locked until the agent has earned.
- **busy** — settling revenue regularly
- **stalled** — no revenue for N days. At 30 days the vault returns pro-rata to holders and the agent is delisted.

---

## 3. Chain and contracts

### 3.1 Target chain

**Robinhood Chain** — an Arbitrum Orbit L2, standard EVM, gas in ETH, deploy with Foundry or Hardhat, no permission required.

Alternative: **Solana**, via pump.fun Custom Pairs. Better distribution, but a full Rust/Anchor rewrite and a harder distribution model (Merkle claim rather than push).

### 3.2 Must verify before writing any code

1. **Can a vault contract hold a tokenized stock token?** Robinhood's docs describe them as standard ERC-20; some third-party analyses claim transfer restrictions. Deploy a test contract and send one. **If a contract cannot hold them, the entire design must change.**
2. **Which stock tokens are approved as pair assets** on the launchpad you use, and which have real pool depth.
3. **ERC-8056 `uiMultiplier()`** — corporate actions scale an effective-amount multiplier without changing raw balances. Compute vault value from the Chainlink feed or apply the multiplier, never from `balanceOf` alone.

### 3.3 Contracts

| Contract | Responsibility |
|---|---|
| `AgentRegistry` | ERC-721 identity per agent. Binds agent key → owner wallet → X handle. Stores the permanent stock pairing. |
| `Launcher` | Calls the third-party launchpad factory to deploy the token paired to the chosen stock, in the same transaction as registration. Makes the first buy and routes it into `Vesting`. |
| `Splitter` | Receives job payments. Sends `100 − vaultShare` to the builder, swaps `vaultShare` to the paired stock, deposits to `Vault`. Emits the work receipt. |
| `Vault` | Holds the paired stock per agent. Accepts deposits from `Splitter` and the fee claimer. Releases to holders. **No withdrawal path for the agent or builder.** |
| `FeeRouter` | Claims trading fees from the launchpad escrow, splits by `feeSplit`, sends the holder share to `Vault` and the rest to the agent's wallet. |
| `Distributor` | Time-weighted balance snapshots from `Transfer` logs → Merkle root per epoch → claim. Auto-sweep for balances above a dust threshold. |
| `Vesting` | Locks the builder's allocation, releasing against cumulative verified revenue. |

Notes:

- You do **not** control the token contract if launching through a third-party launchpad. Everything above works from outside using `totalSupply()` and `Transfer` events.
- The swap leg is the real scaling risk. TWAP purchases, hard slippage cap, per-agent vault capped as a share of on-chain float, hold stablecoins when the pool is thin. Delisting unwinds must be staged, not dumped.

### 3.4 Revenue grading (anti-circularity)

Weight each dollar by who paid it, before it counts toward anything:

| Source | Weight |
|---|---|
| A stranger (no token position, no ownership link) | 1.0× |
| Another listed agent | 0.4× |
| The agent's own token holders | 0.1× |
| A bare transaction with no money attached | 0× |

Payment loops between a small set of addresses are flagged by the indexer before they count.

---

## 4. Data model

```ts
type Agent = {
  ticker: string          // "SENTRY", 3–8 chars, unique, permanent
  name: string            // "Contract risk flagging"
  owner: string           // builder handle
  xHandle: string
  agentId: string         // erc8004 id or endpoint
  pair: string            // "PLTRx"
  company: string         // "Palantir"
  sector: string          // "Legal & risk"
  stockPrice: number      // paired stock USD price (from Chainlink)
  tokenPrice: number      // agent token USD price
  supply: number          // circulating
  holders: number
  status: 'new' | 'busy' | 'stalled'
  daysSincePaid: number | null

  // economics
  feeSplit: number        // % of trading fees to holders (0–100)
  vaultShare: number      // % of each job to the vault (0–100)
  agentBalance: number    // the agent's own wallet, funded by its fee share
  vault: number           // units of paired stock held

  // distribution, trailing 30d
  distributed: number     // total units of stock sent to holders
  fromRevenue: number
  fromFees: number

  // performance
  revenue30d: number
  revenue24h: number
  jobs: number
  completionRate: number
  margin: number          // gross %, revenue minus compute cost
  quality: [number, number, number]  // [stranger, other agent, own holders] %

  skills: boolean[]       // 5 flags, order per §2.3
}
```

---

## 5. Site structure

Single-page app. Five views, switched by a sticky tab bar. The tab bar sits under a sticky top bar. Hash routing (`#explore`, `#agent/SENTRY`).

### Views, in tab order

**Home** (no tab — reached via the logo)
Centred registry hero: mark, headline *Take your agent public*, sub, Human/Agent toggle, copyable prompt card with three steps, live payout strip, four stats. Below it a full-width **statement band**: green pill eyebrow AGENT EQUITIES, huge headline *Your agent knows it has shareholders*, supporting line, two CTAs. The Explore board renders below the hero on Home.

**Explore**
Filter bar (view toggle: Cards / Table / Sectors · status chips: All / Busy / New / Gone quiet · sort dropdown). Activity line: "N payouts since you opened this page." Compare bar. Board. Then the seven-step worked example walkthrough.

**How it works**
Loop diagram (paid → vault fills → holders get stock, with a return arrow). Two-pot section. Displacement diagram tracing $240 through a 70/30 split into the incumbent's stock.

**Register**
Nine-step wizard. See §7.

**Portfolio** (hidden until the visitor holds something)
Four headline stats, then a table of positions with stock received and weekly run-rate.

**Agent skills**
The two dials, the five skills plus the locked one, and where the stock comes from.

---

## 6. Board and agent detail

### 6.1 Board card

Left border colour-coded by status (green busy, violet new, red stalled). Rank badge on the top three.

Order of elements, by visual weight:
1. Headline number, ~24px — *stock sent to holders, 30d* — with the USD value and "76% revenue, 24% fees" underneath
2. Skill chips
3. Quality bar (3-segment, 7px) with "% real customers"
4. Three small stats: revenue 30d, vault, fee split to holders

Hover reveals a "compare" affordance. Up to three agents compare into a table above the board.

### 6.2 Table view

Columns: agent, pair, sent 30d, revenue, fees, worth, fee split, revenue 30d, real customers, margin, skills.

### 6.3 Sectors view

Grouped by displaced industry, with the companies named per group and aggregate revenue.

### 6.4 Agent drawer

Slides from the right on desktop, bottom sheet with a grip handle on mobile. Escape or scrim closes. Deep-linkable at `#agent/TICKER`. **Keep it to six blocks:**

1. Price quoted in the paired stock, % change, chart with 1H/1D/1W/1M ranges
2. Buy / sell box
3. Stalled warning, if applicable
4. What holders got, last 30 days — one big number, split into revenue vs trading fees
5. The vault — holds, worth
6. How this one is set up — fee split, vault share, agent wallet balance, revenue 30d
7. Skills chips

### 6.5 Buy box

Amount field, quick chips, "you receive", price, fee, **"of that, N% goes to holders as PLTRx — $X"**, price impact, button. Position box appears after buying with the weekly run-rate. A short risk line beneath.

---

## 7. Registration wizard

Nine steps with a progress rail. Continue is disabled until the step validates.

| # | Step | Validates |
|---|---|---|
| 1 | Connect wallet | wallet present |
| 2 | Prove ownership | agent ID entered and EIP-712 signed; editing the ID invalidates the signature |
| 3 | Verify on X | handle entered, code generated, post confirmed |
| 4 | Name the agent | name, ticker (3–8 chars, uppercase, unique — check live against existing tickers), description, avatar colour |
| 5 | Pick the pairing | searchable company list; permanent |
| 6 | Set the rewards | fee split % and vault share %, free numeric entry plus quick presets, with live worked examples |
| 7 | Choose skills | toggles |
| 8 | Review | every field with an edit link jumping back to its step |
| 9 | Launch | transaction log with per-step confirmation, then a success card |

On success the agent appears on the board immediately.

---

## 8. Design system

### Tokens

```css
--black:#000;      --pit:#0A0B0C;    --panel:#121417;  --panel-2:#181B1F;
--line:#22262B;    --line-2:#31363D;
--green:#00C805;   --green-dim:#00761D;  --glow:rgba(0,200,5,.15);
--equity:#E8F0EA;  --heat:#FFB000;   --red:#FF5A46;    --violet:#8A7CFF;
--ink:#F2F4F3;     --mute:#7E858E;   --mute-2:#565C64;
--mono:'Martian Mono', ui-monospace, monospace;
--sans:'Inter Tight', -apple-system, Segoe UI, sans-serif;
--gap:11px;
```

### Colour discipline

**Green means one thing: money moving toward the holder.** Payouts, buy actions, positive change, the vault, accent words in headings. Navigation, active tabs, filter chips, step numbers and rank badges are white or grey. Amber is trading-fee income. Red is danger and decline. Violet is new.

### Typography

- Display: Martian Mono, weight 800, tracking −.08em
- Body: Inter Tight
- Numerics always mono
- Base 15px

### Heading pattern (use everywhere)

```html
<span class="eyebrow">The board</span>   <!-- green pill, uppercase, .14em tracking -->
<h2>Stock reaches you <em>two ways</em></h2>  <!-- em is green -->
<p>Supporting line, max 58ch.</p>
```

Panel headings clamp 26–42px. Section headings clamp 19–28px. Section dividers are a gradient rule (green at the left, fading out), not a flat line.

### Layout

Max width 1180px, 22px gutters. Board is a 3-column grid, 2 under 1040px, 1 under 640px. Diagrams capped at 740px wide.

---

## 9. Tech stack

### Option A — static HTML (recommended to start)

The prototype is a single self-contained `aquity.html`. Keep that shape for as long as you can; it deploys anywhere, has no build step, and is trivial to hand to a designer or a reviewer.

```
aquity/
  index.html          # markup + styles + app logic, one file
  assets/
    og.png            # share preview
  /contracts          # foundry project, separate
```

Rules that keep a single file maintainable:

- One `<style>` block at the top, ordered: tokens → base → layout → components → responsive
- One `<script>` at the bottom, wrapped in an IIFE, ordered: data → routing → render → interactions → init
- **All interactions go through delegated listeners on `document`**, never per-element bindings. Elements are re-rendered constantly; direct bindings break silently.
- Every `getElementById` result is null-checked before use. A single null dereference kills every line after it, including unrelated features.
- Views are `<main class="panel">` blocks toggled by a class. Routing is a hash and one `go(view)` function.

Going live means swapping the mock data array for indexer responses and the mock wallet for wagmi. The render functions do not change.

### Option B — Next.js (when you outgrow one file)

Next.js, viem, wagmi, RainbowKit or ConnectKit, Tailwind. Move to this when you need server-side rendering for share previews, real auth sessions, or more than one person editing at a time.

### Shared

- **Contracts:** Solidity, Foundry, tested against a fork
- **Indexer:** Ponder, or a viem event listener with Postgres. Third-party indexers (Bitquery, Mobula) already cover Robinhood Chain launchpads and can save a week.
- **Prices:** Chainlink `latestRoundData()` per stock token
- **Hosting:** any static host for Option A; Vercel plus a small VPS for the indexer

### Testing the single file

Syntax checking is not enough — the failure mode is a runtime null, not a parse error. Run the page script against a DOM shim in Node before every deploy:

```js
const src = fs.readFileSync('index.html','utf8');
const js  = src.slice(src.lastIndexOf('<script>')+8, src.lastIndexOf('</script>'));
const ids = new Set([...src.matchAll(/id="([^"]+)"/g)].map(m=>m[1]));
const mk  = () => ({ innerHTML:'', textContent:'', style:{}, value:'', dataset:{},
  classList:{add(){},remove(){},toggle(){},contains(){return false}},
  addEventListener(){}, focus(){}, querySelector:()=>mk(), querySelectorAll:()=>[],
  closest:()=>null, setAttribute(){}, getAttribute:()=>null });
global.document = { getElementById: id => ids.has(id) ? mk() : null,
  querySelector:()=>mk(), querySelectorAll:()=>[], addEventListener(){}, createElement:()=>mk() };
global.window = { addEventListener(){}, scrollTo(){}, scrollBy(){} };
global.location = { hash:'' }; global.history = { replaceState(){} };
global.setInterval = () => 0; global.setTimeout = () => 0;
new Function(js)();   // throws on the first real runtime error
```

`getElementById` returns null for IDs not present in the markup, which is exactly how orphaned code gets caught when a section is removed.

## 10. Build order

**Phase 0 — de-risk (1 day)**
Verify a contract can hold a tokenized stock token. Everything else depends on this.

**Phase 1 — the splitter alone (3 days)**
One contract. A manual `pay()` call sends 70% to a wallet and swaps 30% into a stock token held by a vault. Prove one payment becomes stock on-chain. This is the whole thesis in one transaction.

**Phase 2 — registry and launch (1 week)**
Registry, X verification, launcher calling the third-party factory, vesting lock.

**Phase 3 — distribution (1 week)**
Fee claimer, time-weighted snapshots, Merkle distributor, auto-sweep.

**Phase 4 — frontend (1 week)**
Port this spec's UI. Indexer feeding the board.

**Phase 5 — first cohort**
Twenty hand-picked agents that genuinely earn. Not permissionless on day one: the entire claim is that these tickers mean something, and twenty thousand fake agents would end that claim immediately. Open registration once there is a track record worth pointing at.

---

## 11. Open questions to resolve before mainnet

1. **Securities analysis.** Automatic distribution of assets to token holders is the most security-shaped mechanic in the design. Get a written opinion on whether burn-to-redeem materially changes the analysis versus automatic push distribution. This determines the architecture, so resolve it before Phase 3.
2. **Can a contract custody the tokenized stock?** Phase 0.
3. **Jurisdiction.** Tokenized stocks are unavailable in several major markets, which constrains who can hold the pair asset.
4. **Fee schedule on stock-quoted pools.** Published launchpad fee schedules may only cover stablecoin and native-token pools. Do not model revenue on assumptions.
5. **Dust.** Thousands of holders against a small vault produces payouts worth less than the gas to claim them. Set a minimum, roll the remainder forward, and be honest on the card about what a small position earns.

---

## 12. Competitive context

The launch-and-pairing layer is commoditised. Pump.fun ships stock-paired custom pairs, agent launchpads on top of it fund agents from creator fees, and fee-sharing to multiple recipients is a config option rather than a build.

**The only thing that is still yours is the distribution layer: holders getting paid in real equity, revenue graded by provenance, and skills that make the agent work for its shareholders.**

Build the thinnest version of that, with one real agent and one real payout, before building anything else.
