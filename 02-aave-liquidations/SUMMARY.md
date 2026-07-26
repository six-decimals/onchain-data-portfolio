# Reconciliation Summary

## Frozen Scope

| Item | Frozen value |
| --- | --- |
| Blockchain | Ethereum |
| Protocol and version | Aave V3 |
| Market | Main Aave market only |
| Window start | `2026-06-14 00:00:00 UTC` |
| Window end | `2026-07-14 00:00:00 UTC` |
| End-boundary rule | Exclusive |
| Event key | `(tx_hash, evt_index)` |
| Primary USD measure | Debt amount in USD |
| Price source | `prices.usd` |
| Price timestamp | Event UTC minute |
| Missing-price handling | Retain the event and mark the affected USD field `NULL` |

## Event Ledger

```text
308 EXACT_MATCH
= 296 FULLY_PRICED_EXACT
+ 12 MATCHED_PRICE_NULL

12 MATCHED_PRICE_NULL
= 3 MATCHED_NULL_DEBT_PRICE
+ 9 MATCHED_NULL_COLLATERAL_PRICE
- 0 MATCHED_BOTH_LEGS_NULL
```

The 12 price-null rows are included in the 308 exact-match keys. `NULL = NULL`
here means that the model and the corresponding Spellbook leg agree on the
absence of a price. The accounting must not be read as `308 + 3 + 9 = 320`.

| Metric | Frozen value |
| --- | ---: |
| Raw event rows | 308 |
| Raw distinct event keys | 308 |
| Model rows | 308 |
| Model distinct event keys | 308 |
| Spellbook debt-leg rows and keys | 308 |
| Spellbook collateral-leg rows and keys | 308 |
| Duplicate-key surplus on any in-scope side | 0 |
| Fully priced exact-match keys | 296 |
| Matched price-null keys | 12 |
| Debt-price-null keys | 3 |
| Collateral-price-null keys | 9 |
| Both-legs-price-null keys | 0 |
| Exact-match partition residual | 0 |

## Difference Ledger

```text
0 EVENT_DIFFERENCES
= 0 MODEL_CORRECT
+ 0 SPELLBOOK_CORRECT
+ 0 METHODOLOGY_DIFFERENCE
+ 0 UNRESOLVED
```

| Difference measure | Frozen value |
| --- | ---: |
| Raw-only event keys | 0 |
| Model-only event keys | 0 |
| Model keys without debt leg | 0 |
| Debt-leg keys without model | 0 |
| Model keys without collateral leg | 0 |
| Collateral-leg keys without model | 0 |
| Raw/model field mismatch rows | 0 |
| Structural mapping mismatch rows | 0 |
| Raw amount mismatch rows | 0 |
| Normalized token amount mismatch rows | 0 |
| Price-null status mismatch rows | 0 |
| Priced USD mismatch rows | 0 |
| Total event-level difference keys | 0 |
| Difference reason-code sum | 0 |
| Difference classification residual | 0 |
| Unresolved difference keys | 0 |

## Scope Exclusions

The Spellbook comparison explicitly filters to
`project = 'aave' AND version = '3'`.

| Excluded project | Debt-leg rows | Collateral-leg rows |
| --- | ---: | ---: |
| `aave_lido` | 2 | 2 |
| `aave_etherfi` | 1 | 1 |
| `aave_horizon` | 0 | 0 |
| Total | 3 | 3 |

These rows were excluded per B04 scope ruling. Excluded keys entering the
reconciliation were zero on both legs, so the excluded rows are not part of
the difference ledger.

## Model Acceptance

| Metric | Frozen value |
| --- | ---: |
| Relevant asset count | 29 |
| Assets missing decimal metadata | 0 |
| Metadata duplicate surplus | 0 |
| Assets with decimal conflicts | 0 |
| Null normalized collateral amounts | 0 |
| Null normalized debt amounts | 0 |
| Collateral scaling mismatches | 0 |
| Debt scaling mismatches | 0 |
| Zero raw collateral amounts | 0 |
| Zero raw debt amounts | 0 |
| `receiveAToken = true` | 8 |
| `receiveAToken = false` | 300 |
| Model v1 acceptance | `PASS` |

## Price Coverage

| Coverage measure | Frozen value |
| --- | ---: |
| Debt-priced events | 305 |
| Collateral-priced events | 299 |
| Both-legs-priced events | 296 |
| Any-leg-unpriced events | 12 |
| Debt-only-unpriced events | 3 |
| Collateral-only-unpriced events | 9 |
| Neither-leg-priced events | 0 |

Missing debt price:

| Asset | Events |
| --- | ---: |
| `USDtb` | 3 |

Missing collateral prices:

| Asset | Events |
| --- | ---: |
| `PT-USDe-25SEP2025` | 1 |
| `PT-eUSDE-14AUG2025` | 1 |
| `PT-sUSDE-25SEP2025` | 4 |
| `PT-sUSDE-27NOV2025` | 3 |
| Total | 9 |

## USD Totals

| Measure | Model | Spellbook absolute amount | Independent `DOUBLE` residual |
| --- | ---: | ---: | ---: |
| Debt / primary liquidation USD | 14,310,881.46313344 | 14,310,881.463133432 | `7.450580596923828e-9` |
| Collateral USD | 15,105,498.884850744 | 15,105,498.884850746 | `-1.862645149230957e-9` |

Deterministic totals (`DECIMAL(38,18)`, identical on both sides; source
query Q09): debt `14,310,881.463133433088215212` USD; collateral
`15,105,498.884850749385411410` USD. Six-decimal display values:
**14,310,881.463133** and **15,105,498.884851**.

The independently aggregated `DOUBLE` residuals are calculation-path artifacts.
The diagnostic produced zero joined row-difference sums and exact zero
`DECIMAL(38,18)` residuals for both legs. The artifact count is one accounting
diagnostic and is not an event-difference count.

The totals include priced legs only. Three debt legs and nine collateral legs
remain `NULL` under the approved no-imputation rule.

## Acceptance

| Check | Frozen result |
| --- | --- |
| Step 6 reconciliation | `PASS_EXACT_RECONCILIATION` |
| Step 7 diagnostic | `FLOAT_AGGREGATION_ARTIFACT_CONFIRMED` |
| Step 8 closed ledger | `PASS_CLOSED_LEDGER` |

## Public Evidence

| # | Evidence | Public query |
| --- | --- | --- |
| Q01 | Raw LiquidationCall schema | https://dune.com/queries/8091621/ |
| Q02 | Live lending table inventory | https://dune.com/queries/8092115/ |
| Q03 | Spellbook borrow schema | https://dune.com/queries/8092234/ |
| Q04 | Spellbook supply schema | https://dune.com/queries/8092242/ |
| Q05 | Baseline and scope counts | https://dune.com/queries/8092277/ |
| Q06 | Event-level liquidation model | https://dune.com/queries/8092290/ |
| Q07 | Raw-to-model acceptance | https://dune.com/queries/8092298/ |
| Q08 | Spellbook reconciliation | https://dune.com/queries/8092306/ |
| Q09 | Missing-price and float diagnostic | https://dune.com/queries/8092322/ |
| Q10 | Closed reconciliation ledger | https://dune.com/queries/8092350/ |
