# Project Summary: Ethereum Stablecoin Organic-Activity Screening

## Frozen Scope

| Item | Frozen value |
| --- | --- |
| Blockchain | Ethereum |
| Tokens | USDC and USDT |
| Main window | UTC `[2026-06-14, 2026-07-14)` |
| Adjacent validation window | UTC `[2026-05-15, 2026-06-14)` |
| Actor unit | One Ethereum address actor proxy |
| Primary event source | `erc20_ethereum.evt_transfer` |
| Curated reconciliation source | `tokens.transfers`, Ethereum only |
| Qualification | At least 10 nonzero transaction-token groups and at least 4 active days on any address-token pair |
| Funding lookback | Rolling 30 days before first main-window activity |
| Stablecoin value assumption | One token unit equals one nominal USD; not a market-price claim |
| Final economic actor threshold | Fee>=movement in at least 50% of qualified nonzero groups |
| Classification | 0 families = `organic candidate`; 1 = `ambiguous`; at least 2 = `likely inorganic` |

USDC contract:
`0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48`

USDT contract:
`0xdac17f958d2ee523a2206206994597c13d831ec7`

Both tokens expose six verified decimals in the observed source data.

## Raw-Event Coverage

| Metric | USDC | USDT | Combined |
| --- | ---: | ---: | ---: |
| Raw transfer rows | 20,913,680 | 29,294,297 | 50,207,977 |
| Distinct event keys | 20,913,680 | 29,294,297 | 50,207,977 |
| Exact raw amount sum | 1,392,959,140,953,201,434 | 558,705,568,640,688,007 | 1,951,664,709,593,889,441 |
| Duplicate-key surplus | 0 | 0 | 0 |
| Null event keys | 0 | 0 | 0 |

Raw and curated row counts, event keys, and exact raw amounts reconcile for
the frozen main window.

## Movement and Qualification Ledger

| Metric | USDC | USDT | Combined |
| --- | ---: | ---: | ---: |
| Eligible main-window events | 19,190,433 | 26,448,839 | 45,639,272 |
| Transaction-token groups | 7,174,029 | 11,350,500 | 18,524,529 |
| Positive-movement groups | 7,135,869 | 11,325,997 | 18,461,866 |
| Exact movement raw | 364,368,047,345,240,847 | 247,805,960,113,938,207 | 612,174,007,459,179,054 |
| Qualified address-token pairs | 159,125 | 262,930 | 422,055 |
| Qualified nonzero groups | 17,272,514 | 24,813,646 | 42,086,160 |

Distinct qualified actor proxies: **399,930**.

The combined movement raw value equals
`612,174,007,459.179054` nominal USD after one exact six-decimal conversion.

## Four-Family Ledger

| Signal family | Frozen actor count | Share of qualified actors |
| --- | ---: | ---: |
| Temporal behavior | 10,886 | 2.721976% |
| Behavioral richness / counterparty concentration | 4,226 | 1.056685% |
| Funding source | 1,876 | 0.469082% |
| Strong funding subset | 32 | 0.008001% |
| Economic rationality | 142,666 | 35.672743% |

Temporal branch counts are 1,610 clock-like-regular, 4,783 same-second-burst,
and 4,597 single-day-burst actors. Branches may overlap, and their union is
10,886.

The strong funding count is a subset of 1,876 and does not add a fifth signal
family.

## Final Main-Window Classification

| Class | Actors | Share | Family-count rule |
| --- | ---: | ---: | --- |
| `organic candidate` | 246,237 | 61.570025% | 0 |
| `ambiguous` | 147,761 | 36.946716% | 1 |
| `likely inorganic` | 5,932 | 1.483260% | at least 2 |
| Total | 399,930 | 100.000000% | exact partition |

Strict and inclusive reporting:

| Estimate | Actors | Share |
| --- | ---: | ---: |
| Strict organic | 246,237 | 61.570025% |
| Inclusive organic | 393,998 | 98.516740% |
| Strict inorganic | 5,932 | 1.483260% |
| Inclusive inorganic | 153,693 | 38.429975% |

The inclusive estimates assign every ambiguous actor to the named side. They
are bounds under a classification convention, not statistical confidence
intervals.

## Economic-Threshold Sensitivity

| Actor gate | Economic actors | `organic candidate` | `ambiguous` | `likely inorganic` | Strict inorganic share |
| --- | ---: | ---: | ---: | ---: | ---: |
| At least one fee>=movement group | 220,652 | 172,177 | 218,057 | 9,696 | 2.424424% |
| At least 25% of nonzero groups | 167,516 | 222,271 | 170,850 | 6,809 | 1.702548% |
| At least 50% — B5-20 frozen | 142,666 | 246,237 | 147,761 | 5,932 | 1.483260% |

Every row partitions to 399,930 actors and passed its implementation checks.

## Transaction-Economic Ledger

| Metric | Frozen value |
| --- | ---: |
| Unique transfer-bearing transactions | 17,564,979 |
| Positive-movement transactions | 17,528,440 |
| Zero-movement transactions | 36,539 |
| Exact movement raw | 612,174,007,459,179,054 |
| Exact execution fee, wei | 2,687,504,361,668,181,160,550 |
| Exact execution fee, USD | 4,547,915.054730 |

The fee/movement comparison values stablecoin movement at nominal face value.
It does not value stablecoins from a market-price feed.

## Funding-Graph Ledger

| Metric | Frozen value |
| --- | ---: |
| Qualified actor proxies | 399,930 |
| Actors with observed positive lookback inflow | 386,628 |
| Lookback-censored actors | 13,302 |
| Single-direct-source actors | 385,881 |
| Ambiguous multi-source actors | 747 |
| External-initiation actors | 372,372 |
| B5-17 funding proxies | 372,096 |
| CEX-annotated source actors | 79,253 |
| Non-CEX source actors | 292,843 |
| Distinct non-CEX source addresses | 111,724 |
| Candidate sources / actors | 83 / 1,876 |
| Strong sources / actors | 3 / 32 |

Candidate funding rule: source-cluster size at least 10 and either exact-amount
share at least 8,000 bps or same-hour share at least 5,000 bps. Strong requires
both shares.

## Funding Manifest Integrity

Q11A emitted five copyable blocks:

| Chunk | Actors | Strong actors | Characters |
| --- | ---: | ---: | ---: |
| 1 | 400 | 7 | 18,799 |
| 2 | 400 | 5 | 18,799 |
| 3 | 400 | 7 | 18,799 |
| 4 | 400 | 9 | 18,799 |
| 5 | 276 | 4 | 12,971 |
| Sum | 1,876 | 32 | 88,167 |

Four inter-chunk `~` delimiters produce 88,171 characters. Reconstruction
found 1,876 manifest rows, 1,876 distinct addresses, and 32 parsed strong
flags. SHA-256 of the reconstructed text:

```text
3abbfd393dad2c51d95e40c35cc07323b150e86f90e60c2fd4ce7141435997c1
```

## Reverse-Event Diagnostics

| Metric | Frozen value |
| --- | ---: |
| Candidate-touching events | 83,075 |
| Candidate endpoint participations | 84,764 |
| Directed token-address pairs | 26,548 |
| Reverse-matched directed pair rows | 952 |
| Canonical reverse-edge pairs | 476 |
| Events on those pairs | 3,714 |
| Unordered cross-direction combinations | 6,569 |
| Directed combinations | 13,138 |
| Maximum combinations per directed pair | 465 |

Q10B computed a 20-cell mutual-best grid. Validation scope is deliberately
layered:

- rows 1-10 were fully verified;
- row 11 anchors and `implementation_checks_pass` for rows 11-20 were
  spot-checked;
- specific grid values in rows 11-20 were not verified;
- duplicate `maximum_time_gap_seconds` output aliases make that copied column
  invalid; `time_window_label` and the static SQL grid define each cutoff;
- no grid cell is an approved classification threshold.

The reverse-event result is screening evidence and is not part of the final
four-family classification.

## Forty-Case Audit

| Stratum | Selected actors | Labeled actors | Label rows | CEX matches |
| --- | ---: | ---: | ---: | ---: |
| Organic boundary | 10 | 3 | 21 | 0 |
| Ambiguous boundary | 10 | 5 | 32 | 0 |
| `likely inorganic` boundary | 10 | 1 | 1 | 0 |
| High-cooccurrence extreme | 10 | 3 | 20 | 0 |
| Total | 40 | 12 | 74 | 0 |

Q12B recomputed all 10,710 qualified nonzero transaction groups and all 5,617
fee>=movement groups represented by those cases. Funding and strong-funding
flags were inherited from Q12A rather than recomputed. All 40 case rows and
all four strata passed their checks.

## Adjacent-Window Lightweight Check

| Window | Qualified actors | Temporal | Richness | Economic | `organic candidate` | `ambiguous` | `likely inorganic` | Strict inorganic share |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `[2026-06-14, 2026-07-14)` | 399,930 | 10,886 | 4,226 | 142,666 | 247,696 | 146,709 | 5,525 | 1.381492% |
| `[2026-05-15, 2026-06-14)` | 350,671 | 8,312 | 4,557 | 96,155 | 244,970 | 102,395 | 3,306 | 0.942764% |

The lightweight main-window counts differ from Q11B because funding is
excluded from both windows. The 0.438728 percentage-point share difference is
therefore valid only for the identical three-family lightweight pipeline.

## Validation Status

| Check | Status |
| --- | --- |
| Raw/curated event reconciliation | Passed |
| Exact raw-amount and movement identities | Passed |
| Qualification and actor partitions | Passed |
| Four-family classification partition | Passed |
| Economic-threshold sensitivity | Passed as diagnostic; B5-20 frozen at 50% |
| Funding manifest reconstruction | Passed outside the query |
| Forty-case implementation recomputation | Passed |
| Known-entity truth validation | Inconclusive: 12/40 labeled, 0 CEX matches, no ownership ground truth |
| Adjacent-window structural comparison | Passed for the lightweight pipeline only |
| Reverse-event grid | Computation passed; latter-half specific values remain unverified |
| Precision and recall | Not measurable with available labels |

## Complete Dune Library Inventory

All 28 entries are Public as of 2026-08-06. The seven descriptions that carry
key claims were reviewed line by line and passed after three corrections.
Descriptions for the other 21 entries were not independently reviewed and are
not represented as verified here.

| Library name | Public query |
| --- | --- |
| 05-Q12C-two-window-lightweight-validation | https://dune.com/queries/8239247 |
| 05-Q12A0-label-cex-schema-evidence | https://dune.com/queries/8234174 |
| 05-Q12B-individual-case-evidence-audit | https://dune.com/queries/8238924 |
| 05-Q12A-known-entity-extreme-case-audit | https://dune.com/queries/8238802 |
| 05-Q11B-four-signal-fusion | https://dune.com/queries/8233932 |
| 05-Q11A-funding-signal-manifest | https://dune.com/queries/8233139 |
| 05-Q10B-mutual-best-reverse-event-sensitivity | https://dune.com/queries/8229715 |
| 05-Q10A3-reverse-pair-manifest | https://dune.com/queries/8227981 |
| 05-Q10A2-directed-pair-reverse-edge-cost-probe | https://dune.com/queries/8227726 |
| 05-Q10A1-B5-18-candidate-actor-participation-anchor | https://dune.com/queries/8227504 |
| 05-Q09B4-Joint Funding-Source Signal Coverage Matrix | https://dune.com/queries/8227331 |
| 05-Q09B3-size-conditioned-funding-source-thresholds | https://dune.com/queries/8227163 |
| 05-Q09B2-non-cex-funding-source-clusters | https://dune.com/queries/8227042 |
| 05-Q09B1-qualified-actors-funding-proxy-classification | https://dune.com/queries/8226759 |
| 05-Q09A-funding-source-support-table-schema | https://dune.com/queries/8226477 |
| 05-Q08C-main-window-economic-rationality-distribution | https://dune.com/queries/8226371 |
| 05-Q08B-one-day-gas-price-coverage-reconciliation | https://dune.com/queries/8225808 |
| 05-Q08A-economic-rationality-source-schema | https://dune.com/queries/8208905 |
| 05-Q07-qualified-counterparty-richness-distributions | https://dune.com/queries/8204099 |
| 05-Q06B-qualified-interval-regularity-distributions | https://dune.com/queries/8203914 |
| 05-Q06A-qualified-daily-temporal-distributions | https://dune.com/queries/8197624 |
| 05-Q05-address-temporal-distributions | https://dune.com/queries/8197538 |
| 05-Q04-transaction-feature-distributions | https://dune.com/queries/8197356 |
| 05-Q03B-full-window-transaction-token-movement | https://dune.com/queries/8197270 |
| 05-Q03A-transaction-token-movement-feasibility | https://dune.com/queries/8197151 |
| 05-Q02-USDC-USDT-base-event-audit | https://dune.com/queries/8193392 |
| 05-Q01-USDC-USDT-transfer-coverage | https://dune.com/queries/8171875 |
| 05-Q00-Transfer-source-schema-verification | https://dune.com/queries/8167086 |

## Evidence Boundary

Implementation identities establish that event keys, joins, exact amounts,
partitions, and copied manifests are internally consistent. They do not prove
that the class names are true. Shared funding, repeated amounts, concentrated
counterparties, timing regularity, reverse transfers, and high fee/movement
ratios all have legitimate alternative explanations. The project therefore
stops at screening categories and reports unresolved actors explicitly.
