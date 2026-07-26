# Findings and Rulings

## 1. Source Discovery

The verified raw decoded table is
`aave_v3_ethereum.Pool_evt_LiquidationCall`. Its 16 fields are:

| Column | Type |
| --- | --- |
| `contract_address` | `varbinary` |
| `evt_tx_hash` | `varbinary` |
| `evt_tx_from` | `varbinary` |
| `evt_tx_to` | `varbinary` |
| `evt_tx_index` | `integer` |
| `evt_index` | `bigint` |
| `evt_block_time` | `timestamp(3)` |
| `evt_block_number` | `bigint` |
| `evt_block_date` | `date` |
| `collateralasset` | `varbinary` |
| `debtasset` | `varbinary` |
| `debttocover` | `uint256` |
| `liquidatedcollateralamount` | `uint256` |
| `liquidator` | `varbinary` |
| `receiveatoken` | `boolean` |
| `user` | `varbinary` |

The current Spellbook representation is not a standalone liquidation table.
It is a paired event representation:

- `lending.borrow` contains the debt leg under
  `transaction_type = 'borrow_liquidation'`;
- `lending.supply` contains the collateral leg under
  `transaction_type = 'deposit_liquidation'`.

Both live tables expose `tx_hash` and `evt_index`, which form the reconciliation
key. Direct probes established that `lending.liquidations` and
`aave.liquidations` did not exist in the live Dune environment.

## 2. Scope Ruling

The analysis uses Ethereum, Aave V3, and the fixed half-open UTC window
`[2026-06-14 00:00:00, 2026-07-14 00:00:00)`.

The Spellbook side is restricted to the main market:

```sql
project = 'aave'
AND version = '3'
```

This filter excludes two `aave_lido` rows, one `aave_etherfi` row, and zero
`aave_horizon` rows on each Spellbook leg, per B04 scope ruling. The three
excluded rows per leg are documented as scope exclusions, not differences.
Zero excluded keys entered the reconciliation or its difference list.

The 30-day window produced 308 raw events, above the 200-event reopening
threshold. The conditional requirement to reopen B02 and consider a 90-day
window was therefore not triggered.

## 3. Raw-to-Model Validation

The event-level model contains 308 rows and 308 distinct
`(tx_hash, evt_index)` keys. The raw table also contains 308 rows and 308
distinct keys.

The acceptance checks found:

- zero duplicate-key surplus;
- zero raw-only or model-only keys;
- zero raw/model field mismatches;
- zero missing or conflicting decimal metadata across 29 relevant assets;
- zero null normalized amounts;
- zero scaling mismatches;
- zero zero-valued raw collateral or debt amounts.

Eight events have `receiveAToken = true`, while 300 have
`receiveAToken = false`.

## 4. Price Method

Both token legs are retained. `liquidation_amount_usd` is defined as the debt
amount in USD, while `collateral_amount_usd` is retained as a separate field.

The approved method joins `prices.usd` at the event's UTC minute. When a price
is missing, the event remains in the model and the affected USD field remains
`NULL`; no price is imputed.

Spellbook's relevant enrichment macros use the same minute-level price source.
The reviewed source version is commit
`f8e655c11eec6d11d2c1a1d3081e8511b9aa0395`:

- [Borrow enrichment macro](https://github.com/duneanalytics/spellbook/blob/f8e655c11eec6d11d2c1a1d3081e8511b9aa0395/dbt_subprojects/hourly_spellbook/macros/sector/lending/lending_enrich_borrow.sql)
- [Supply enrichment macro](https://github.com/duneanalytics/spellbook/blob/f8e655c11eec6d11d2c1a1d3081e8511b9aa0395/dbt_subprojects/hourly_spellbook/macros/sector/lending/lending_enrich_supply.sql)

Spellbook represents liquidation flows with negative signed amounts. The
reconciliation therefore compares model amounts with the absolute values of
the corresponding Spellbook amounts.

## 5. Event-Level Reconciliation

Every one of the 308 model event keys matches one debt leg and one collateral
leg. All key, structural, raw-amount, normalized-amount, price-null-status, and
priced-USD mismatch counts are zero.

The exact-match accounting is:

```text
308 exact-match keys
= 296 fully priced exact-match keys
+ 12 matched price-null keys
```

The 12 price-null keys are a subset of the 308 exact matches, not extra rows.
On the affected leg, both the model and Spellbook are `NULL`, so the row still
matches. The 12 keys partition into three missing debt prices and nine missing
collateral prices, with zero events missing both legs. They must not be added
to 308 as if the result contained 320 events.

The missing debt-price asset is:

| Asset | Event count |
| --- | ---: |
| `USDtb` | 3 |

The missing collateral-price assets are:

| Asset | Event count |
| --- | ---: |
| `PT-USDe-25SEP2025` | 1 |
| `PT-eUSDE-14AUG2025` | 1 |
| `PT-sUSDE-25SEP2025` | 4 |
| `PT-sUSDE-27NOV2025` | 3 |

Representative missing debt-price events:

| Transaction hash | Event index | Asset |
| --- | ---: | --- |
| `0x9CD594FC54AD4BBCB3DA4C5761AC59AFB3A2710A86944D4DDB82E8E303804C13` | 117 | `USDtb` |
| `0xC53034B4E9A1B0D1FF1F7F95251243C788C6E0C2237C20A0A26C7CA5C5EAAB8E` | 230 | `USDtb` |
| `0x26004E3DE906D4A82CDCE3BC0F6F3850864590BD405530CA40BD8A07104E0A92` | 443 | `USDtb` |

Representative missing collateral-price events:

| Transaction hash | Event index | Asset |
| --- | ---: | --- |
| `0xFCDBE42AAB031F78BBD55AB554D994139B34196A26EDA941BFEBB086153CF34B` | 958 | `PT-sUSDE-25SEP2025` |
| `0xFCDBE42AAB031F78BBD55AB554D994139B34196A26EDA941BFEBB086153CF34B` | 980 | `PT-sUSDE-27NOV2025` |
| `0xFCDBE42AAB031F78BBD55AB554D994139B34196A26EDA941BFEBB086153CF34B` | 989 | `PT-sUSDE-25SEP2025` |

## 6. USD Totals and Floating-Point Diagnostic

The frozen Step 6 totals are:

| Measure | Model | Spellbook absolute amount | Independent residual |
| --- | ---: | ---: | ---: |
| Debt / primary liquidation USD | 14,310,881.46313344 | 14,310,881.463133432 | `7.450580596923828e-9` |
| Collateral USD | 15,105,498.884850744 | 15,105,498.884850746 | `-1.862645149230957e-9` |

Deterministic totals (`DECIMAL(38,18)`, identical on both sides; source
query Q09): debt `14,310,881.463133433088215212` USD; collateral
`15,105,498.884850749385411410` USD. Six-decimal display values:
**14,310,881.463133** and **15,105,498.884851**.

A diagnostic rerun produced different last-bit independent `DOUBLE`
residuals—`1.862645149230957e-9` for debt and
`5.587935447692871e-9` for collateral—while all of the following remained
zero:

- same-row joined `DOUBLE` residuals;
- sums of event-level USD differences;
- `DECIMAL(38,18)` residuals.

The variation by calculation path confirms a floating-point aggregation
artifact. It is not an event difference and does not replace the frozen Step 6
totals. B09 classifies both calculation paths as correct for their numeric
representation.

The priced totals cover 305 debt legs and 299 collateral legs. They do not
include the affected `NULL` legs and must not be presented as complete economic
coverage of all 308 events.

## 7. Difference Classification and Closure

Reason codes used by the diagnostic:

| Reason code | Meaning | Event count |
| --- | --- | ---: |
| `EXACT_MATCH` | All comparable event fields agree, including matched null status | 308 |
| `MATCHED_NULL_DEBT_PRICE` | Debt price is absent on both sides; subset of `EXACT_MATCH` | 3 |
| `MATCHED_NULL_COLLATERAL_PRICE` | Collateral price is absent on both sides; subset of `EXACT_MATCH` | 9 |
| `FLOAT_AGGREGATION_ARTIFACT` | Non-event diagnostic for last-bit `DOUBLE` summation | 1 diagnostic |

The event-difference ledger closes as:

```text
0 event differences
= 0 model-correct differences
+ 0 Spellbook-correct differences
+ 0 methodology-difference events
+ 0 unresolved differences
```

Both the exact-match partition residual and the difference-classification
residual are zero. The final acceptance result is `PASS_CLOSED_LEDGER`.

## 8. B-Class Ruling Record

| Ruling | Selected option | Recorded effect |
| --- | --- | --- |
| B01 | Option 3 | Reconcile the raw event to paired `lending.borrow` and `lending.supply` legs. |
| B02 | Option 1 | Use the fixed 30-day window `[2026-06-14, 2026-07-14)` UTC. |
| B03 | Option 1 | Restrict the work to Ethereum. |
| B04 | Option 1 | Restrict Spellbook to the main Aave V3 market; exclude three non-main-market rows per leg. |
| B05 | Option 1 | Use `prices.usd`. |
| B06 | Option 1 | Join price at the event's UTC minute. |
| B07 | Option 1 | Retain missing-price events and mark the affected USD value `NULL`. |
| B08 | Option 1 | Retain both legs and use debt USD as the primary liquidation USD measure. |
| B09 | Option 3 | Treat the tiny aggregate residuals as calculation-path differences for which both results are correct; do not count them as event differences. |
| B10 | Option 2 initially; superseded | Rebuild of the evidence SQL was attempted, failed review, and was abandoned in favor of restoring the original accepted SQL from the working conversation. See error log #27 and #28. |

## 9. Evidence Map

| # | Claim | Reproducible query |
| --- | --- | --- |
| Q01 | Raw LiquidationCall schema | https://dune.com/queries/8091621/ |
| Q02 | Live lending table inventory | https://dune.com/queries/8092115/ |
| Q03 | Spellbook borrow schema | https://dune.com/queries/8092234/ |
| Q04 | Spellbook supply schema | https://dune.com/queries/8092242/ |
| Q05 | Window, market scope, counts, and exclusions | https://dune.com/queries/8092277/ |
| Q06 | Event-level liquidation model | https://dune.com/queries/8092290/ |
| Q07 | Raw-to-model row and amount acceptance | https://dune.com/queries/8092298/ |
| Q08 | Key, field, amount, and USD reconciliation | https://dune.com/queries/8092306/ |
| Q09 | Missing-price samples and floating-point proof | https://dune.com/queries/8092322/ |
| Q10 | Exact-match and difference-ledger closure | https://dune.com/queries/8092350/ |

## 10. Limits

The findings apply only to Aave V3 Ethereum's main market in the frozen
30-day window and to the observed versions of Dune and Spellbook. They do not
establish equivalence for other chains, Aave markets, time periods, pricing
methods, or future upstream revisions. The four missing-price asset labels are
reported as observed; no unsupported root cause is assigned.

## 11. Error Log

### #21

- What went wrong: I treated `dune.information_schema` as an exhaustive catalog for Dune decoded and curated datasets. The discovery query returned `NO_MATCH` for both sides even though that result could not establish that the underlying tables were absent.
- How it was found: The user ran the discovery query and both `raw_decoded` and `spellbook_candidate` returned `NO_MATCH`.
- How it was fixed: I stopped relying on catalog-wide metadata discovery and switched to direct `DESCRIBE` probes against each candidate table.

### #22

- What went wrong: I promoted `lending.liquidations` from a candidate to the direct Spellbook probe before its availability had been established in the user's Dune environment.
- How it was found: `DESCRIBE lending.liquidations` failed with `Table 'delta_prod.lending.liquidations' does not exist` under execution ID `01KY8GSTKT3FCSZV1SNPAXGHSH`.
- How it was fixed: I retained the failed probe as evidence, stopped treating `lending.liquidations` as the current table, and moved to direct verification of the alternative candidate `aave.liquidations`.

### #23

- What went wrong: I used `aave.liquidations` because an indexed public Dune query referenced it, but I did not verify that the query still used a live table. The table does not exist in the user's current Dune environment.
- How it was found: `DESCRIBE aave.liquidations` failed with `Table 'delta_prod.aave.liquidations' does not exist` under execution ID `01KY8GY0TT5TP9P1HDFD55JQCF`.
- How it was fixed: I discarded stale public-query references, checked Dune's current curated lending catalog, and switched to live schema enumeration before probing any further table.

### #24

- What went wrong: I stated that `DESCRIBE lending.supply` was expected to return 18 rows.
- How it was found: The user's live Dune result returned 19 rows, with `evt_index integer` as the final column.
- How it was fixed: I replaced the expected schema with the live 19-column schema and will treat executed Dune results, rather than documentation-derived column counts, as the schema authority.

### #25

- What went wrong: I misread the correct `- 0 MATCHED_BOTH_LEGS_NULL` inclusion-exclusion term in `SUMMARY.md` as malformed text and attempted to replace it.
- How it was found: The patch failed because the malformed text was not present; direct inspection showed that the existing formula was already correct.
- How it was fixed: No document change was made to the formula, and the correct `- 0 MATCHED_BOTH_LEGS_NULL` term was retained.

### #26

- What went wrong: I chained three file-validation commands with shell semicolons even though the working rules prohibit command chaining with separators.
- How it was found: I reviewed the completed validation command and identified the three semicolon-separated `git diff --no-index --check` segments.
- How it was fixed: The validation itself made no file changes; I recorded the violation and will run subsequent commands as separate tool calls or through structured orchestration.

### #27

- What went wrong: While completing Steps 1 through 9, the final accepted SQL for the evidence queries was not saved and named in Dune at the moment each result was frozen. When the release step required public URLs, the queries had to be recovered.
- How it was found: The release checklist requested public URLs for ten evidence queries, and the saved queries did not exist.
- How it was fixed: The original accepted SQL was recovered from the working conversation, re-created in Dune, re-run against the frozen window, verified against every frozen value, then saved, named, described, and set to Public. A new working rule requires every accepted query to be saved and named immediately after acceptance.

### #28

- What went wrong: An attempted from-scratch rebuild of the ten evidence queries delivered SQL containing text corruption: an orphan duplicated code fragment inside the Q07 acceptance metric and a broken comparison clause inside the Q10 final acceptance CASE.
- How it was found: External review before execution identified the corrupted segments; self-check had not detected them.
- How it was fixed: The rebuild was abandoned. The original accepted SQL restored from the working conversation was used instead, making the corrupted rebuild irrelevant to the published evidence.
