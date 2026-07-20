# Onchain Data Portfolio

Data models, metric replication, and data-quality forensics on public blockchain data.

**Working standard:** every number is rerunnable, every judgment is logged, and every deliverable ships with its own correction log and regression evidence.

---

## Published

### Uniswap V3 Revenue — Independent Replication vs Token Terminal

**[English](英文Medium链接) · [中文](中文Medium链接) · 5 public Dune queries**

Rebuilt 30-day fees / supply-side fees / revenue on Ethereum from **3,105,881** raw swaps — pool matching, fee-tier decoding, and a protocol-fee timeline reconstructed in strict `block_number + evt_index` order.

**Headline result:** all three metrics land **+1.8–1.9%** above Token Terminal's CSV for the identical scope. The gap is confirmed and bounded. The cause is deliberately *not* over-attributed — their pricing and filtering rules are unpublished, and the analysis stops where the evidence stops.

Selected findings:

- A **$6.23** trade carried a **$1.9M** price tag in `dex.trades.amount_usd` (≈305,000× inflation). The entire window was repriced from the input side.
- **62,093** CollectProtocol withdrawal events reconciled against successful calls: **exact match, zero mismatches**.
- Accrued revenue vs priceable withdrawals: a **$62,087.50** gap, shown to be non-attributable with current evidence — and left that way.
- Ships with a 10-entry correction log (including two misjudgments of my own), kept verbatim.

---

## Pipeline

| # | Deliverable | Scope | Status |
|---|---|---|---|
| 01 | Data-incident change package for the WETH/AVAIL mispricing (256 trades): root cause, fix policy, regression diff, impact table | Uniswap V3 / Ethereum | **in progress** |
| 02 | `lending.liquidations` — event-level liquidation model | Aave V3 | queued |
| 03 | Incremental dbt model for a full-history fees/revenue scan | Uniswap V3 | queued |
| 04 | Reverse-engineering an undocumented protocol into production-ready models | TBD, new chain preferred | queued |
| 05 | Organic-activity methodology: separating real usage from wash trading and incentive noise | Stablecoins | queued |

---

## How this work is produced

SQL is AI-generated and human-verified: generate → run on real data → reconcile → correct. Nothing enters a conclusion without surviving that loop. Convention decisions — fix vs drop vs flag, denominator choices, exclusion rules — are recorded as explicit rulings inside each deliverable: the same audit posture I would demand from any table I had to trust.
