# Project Summary: Incremental Uniswap V3 Fees and Revenue

## Problem

The repaired Uniswap V3 model recalculated all trades on every run. The goal was to limit daily work without changing trade-level outputs. Source rows inside UTC `[2026-06-14, 2026-07-14)` moved from 3,105,881 to 3,105,887, so acceptance moved from historical totals to same-snapshot parity.

## Method

The dbt model replaces the latest three complete UTC dates. Logic changes use a full refresh; older issues use bounded backfills. DECIMAL formulas are shared, while token-side and protocol-state logic stays protocol-specific. Candidate pools restrict joins. The audit key is `(tx_hash, evt_index)`.

## Key results

| Check | Result |
| --- | ---: |
| Current full-snapshot rows | 3,105,887 |
| Three-date recomputed rows | 284,882 |
| Retained rows | 2,821,005 |
| Full-only / simulated-only keys | 0 / 0 |
| Field-mismatch keys | 0 |
| Fees | `7,437,623.041819` USD |
| Protocol revenue | `1,417,343.393348` USD |
| Supply-side fees | `6,020,279.648471` USD |
| Accounting residual | `0.000000` USD |

The three-date filter selected `90.8277%` fewer trades. Logical pool/setting-event rows fell `77.5302%`/`77.4701%`; these are not scanned bytes. Five Dune Medium runs per model gave full/three-date medians of 8/10 seconds. Speedup was `-25.0000%`; the `50.0000%` target failed.

## Decisions and audit status

Eight decisions were frozen: B3-01, B8, B9, B3-02, B3-03, B3-04, B10, and B26. B10 preserves trade-level granularity; B26 selects engineering and product teams.

- Unexplained key, field, or monetary residuals: **0**
- Logged project errors: **11** (`#29`–`#39`)
- Performance failure is disclosed separately, not counted as a residual.

## Evidence

- [Incremental reconstruction and parity](https://dune.com/queries/8127229)
- [Same-snapshot baseline parity](https://dune.com/queries/8127558)
- [Benchmark record](benchmark.csv)
- [Full methodology and limitations](optimization_notes.md)
