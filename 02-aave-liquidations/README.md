# Aave V3 Ethereum Liquidations

**Who this table serves.** This package primarily serves engineering and
product consumers (B26 ruling). Typical queries they would run: joining
liquidation events to open positions for risk monitoring, per-liquidator and
per-asset flow analysis, and verifying that a downstream dashboard's
liquidation totals reproduce exactly from raw events. Finance-audit and
research users can rely on the same table because every number in this
package closes to a public, rerunnable query.

This package builds an event-level liquidation model from Aave V3 Ethereum
`LiquidationCall` events and reconciles every in-scope event against the two
current Spellbook lending legs.

For the fixed UTC window `[2026-06-14 00:00:00, 2026-07-14 00:00:00)`, the
model contains 308 events and 308 distinct `(tx_hash, evt_index)` keys. All 308
keys match both Spellbook legs exactly at the row level. The closed ledger is:

```text
308 exact matches
= 296 fully priced exact matches
+ 12 exact matches with synchronized model/Spellbook price-null status
```

The 12 price-null events are a subset of the 308 exact matches, not additional
events. They comprise three events with a missing debt-leg price and nine
events with a missing collateral-leg price; no event is missing both prices.
There are zero event-level differences and zero unresolved differences.

## Scope

| Dimension | Definition |
| --- | --- |
| Blockchain | Ethereum |
| Protocol | Aave V3 |
| Market | Main Aave market only: `project = 'aave'` and `version = '3'` |
| Time window | `2026-06-14 00:00:00 UTC` inclusive to `2026-07-14 00:00:00 UTC` exclusive |
| Event grain | One row per `(tx_hash, evt_index)` |
| Raw source | `aave_v3_ethereum.Pool_evt_LiquidationCall` |
| Spellbook debt leg | `lending.borrow`, filtered to `transaction_type = 'borrow_liquidation'` |
| Spellbook collateral leg | `lending.supply`, filtered to `transaction_type = 'deposit_liquidation'` |

The current Spellbook representation is a paired debt-leg and collateral-leg
interface. The legacy candidates `lending.liquidations` and
`aave.liquidations` did not exist in the live Dune environment during
discovery.

Three non-main-market rows per Spellbook leg were excluded—two
`aave_lido`, one `aave_etherfi`, and zero `aave_horizon`—per B04 scope ruling.
None of those excluded keys entered the reconciliation or the difference
ledger.

## Model

[liquidations_model.sql](./liquidations_model.sql) converts raw token amounts
using Ethereum token metadata and produces, at minimum:

- block time and block number;
- transaction hash and event index;
- liquidator and borrower;
- collateral and debt asset addresses;
- normalized collateral and debt amounts;
- debt-leg and collateral-leg USD values.

The model retains both priced legs. Under the approved definition,
`liquidation_amount_usd` is the debt amount in USD. Pricing uses
`prices.usd` at the event's UTC minute. An event is retained with a `NULL` USD
value when its price is unavailable.

The v1 acceptance check returned 308 rows, 308 distinct event keys, no duplicate
surplus, no raw/model field mismatches, and no amount-scaling mismatches. All 29
relevant assets had unique decimal metadata. Eight events used
`receiveAToken = true`; 300 used `false`.

## Reconciliation

[reconciliation.sql](./reconciliation.sql) joins the model to both Spellbook
legs on `(tx_hash, evt_index)`. It checks:

- key coverage and duplicate surplus;
- block number, asset, borrower, and liquidator mappings;
- raw and normalized token amounts;
- price-null status and priced USD amounts.

Spellbook stores liquidation flow amounts with a negative sign, so its USD
amounts are compared by absolute value. The model and Spellbook use the same
minute-level `prices.usd` methodology.

The result is exact at event level:

| Check | Result |
| --- | ---: |
| Model event keys | 308 |
| Matched debt-leg keys | 308 |
| Matched collateral-leg keys | 308 |
| Duplicate-key surplus, each side | 0 |
| Structural or amount mismatch rows | 0 |
| Price-null status mismatch rows | 0 |
| Priced USD mismatch rows | 0 |
| Total event-level difference keys | 0 |
| Unresolved difference keys | 0 |
| Closed-ledger status | `PASS_CLOSED_LEDGER` |

## Amounts and Price Coverage

| Metric | Model | Spellbook absolute amount |
| --- | ---: | ---: |
| Priced debt/liquidation total, USD | 14,310,881.46313344 | 14,310,881.463133432 |
| Priced collateral total, USD | 15,105,498.884850744 | 15,105,498.884850746 |
| Priced debt events | 305 | 305 |
| Priced collateral events | 299 | 299 |
| Events with both legs priced | 296 | 296 |

Deterministic totals (`DECIMAL(38,18)`, identical on both sides; source
query Q09): debt `14,310,881.463133433088215212` USD; collateral
`15,105,498.884850749385411410` USD. Six-decimal display values:
**14,310,881.463133** and **15,105,498.884851**.

The tiny independently aggregated double-precision residuals
(`7.450580596923828e-9` for debt and `-1.862645149230957e-9` for collateral)
are floating-point summation artifacts, not event differences. Same-row joined
differences sum to zero, and `DECIMAL(38,18)` totals close to exactly zero.

These USD totals cover only priced legs. They must not be interpreted as the
complete economic value of the 308 events because 12 events contain one
unpriced leg.

## Evidence

All ten evidence queries are public and rerunnable:

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

Spellbook source logic was inspected at commit
`f8e655c11eec6d11d2c1a1d3081e8511b9aa0395`:

- [Borrow enrichment macro](https://github.com/duneanalytics/spellbook/blob/f8e655c11eec6d11d2c1a1d3081e8511b9aa0395/dbt_subprojects/hourly_spellbook/macros/sector/lending/lending_enrich_borrow.sql)
- [Supply enrichment macro](https://github.com/duneanalytics/spellbook/blob/f8e655c11eec6d11d2c1a1d3081e8511b9aa0395/dbt_subprojects/hourly_spellbook/macros/sector/lending/lending_enrich_supply.sql)

## Package Contents

- `README.md` — project entry point, method, result, and limitations.
- `SUMMARY.md` — frozen numeric ledger and acceptance totals.
- `liquidations_model.sql` — raw-event model and USD enrichment.
- `reconciliation.sql` — row-level comparison and closed-ledger checks.
- `findings.md` — scope rulings, difference classification, diagnostics, and
  error log.

## Limits

The conclusions apply only to the stated Ethereum main-market window. They do
not establish equivalence for other Aave markets, chains, time periods, future
Spellbook revisions, or price sources. Missing prices are reported as `NULL`;
they are not imputed or silently excluded from event counts.
