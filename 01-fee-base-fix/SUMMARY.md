# Uniswap V3 Fee-Base Incident Repair

This change package serves engineering and product teams. They will query which rows changed, why each row changed, whether any unrelated row moved, and whether the repaired fee and revenue model can be reproduced from public data.

## Problem

The legacy revenue model used `dex.trades.amount_usd` as the fee base.

For two material WETH/AVAIL trades, that value matched the bought WETH leg. It was a valid trade valuation, but it was the wrong base for an input-token fee calculation.

The largest row had:

```text
legacy amount_usd = $1,900,384.829449
input-side USD    = $6.234174
multiple          = 304,833.4685×
```

The raw Swap integers matched the decoded token direction. The incident was therefore classified as a metric-formula error, not corrupted raw data.

## Method

The investigation used the fixed UTC window:

```text
[2026-06-14 00:00:00, 2026-07-14 00:00:00)
```

It followed five steps:

1. Inspect the Dune table schemas before selecting fields.
2. Reconcile the two material trades with `uniswap_v3_ethereum.uniswapv3pool_evt_swap`.
3. Compare the sold-token and bought-token USD values.
4. Enumerate every row that changes at six decimal places.
5. Run a full regression against all 3,105,881 base rows.

The fixed fee base is:

```text
token_sold_amount × sold_token_minute_price_usd
```

The model keeps the original Swap events and `dex.trades.amount_usd`.

## Key numbers

| Check                              |    Result |
| ---------------------------------- | --------: |
| Base trades                        | 3,105,881 |
| Unique `(tx_hash, evt_index)` keys | 3,105,881 |
| Legacy unpriced rows               |    12,314 |
| WETH/AVAIL rows reviewed           |       256 |
| Rows repaired                      |       142 |
| Verified no-op target rows         |       114 |
| Ordinary repair reason rows        |       140 |
| Material repair reason rows        |         2 |
| Unexpected changed rows            |         0 |
| Unaffected rows proven unchanged   | 3,105,739 |

## Metric impact

| Metric           |              Before |               After |            Change |
| ---------------- | ------------------: | ------------------: | ----------------: |
| Fees             | `$7,457,019.231172` | `$7,437,622.456387` | `-$19,396.774785` |
| Supply-side fees | `$6,036,443.164674` | `$6,020,279.185686` | `-$16,163.978988` |
| Revenue          | `$1,420,576.066498` | `$1,417,343.270700` |  `-$3,232.795798` |

The repair reduced fees by `0.2601%`, supply-side fees by `0.2678%`, and revenue by `0.2276%`.

## Acceptance result

The expected and actual repair sets both contain 142 rows.

```text
missing expected rows       = 0
unexpected changed rows     = 0
fixed-value mismatches      = 0
reason-code mismatches      = 0
changed unaffected rows     = 0
newly null rows             = 0
all_checks_pass             = true
```

## Decision record

Decision count: **4**

* **B1:** Real but extreme on-chain behavior.
* **B2:** Repair the metric formula.
* **B3:** Correct and recompute every affected row in the frozen window.
* **B26:** Serve engineering and product users.

## Residuals

Residual count: **1**

`R-01 / DISPLAY_ROUNDING_6DP` is `$0.000001`.

It comes from subtracting three outputs that were rounded independently to six decimal places. The unrounded accounting residual is `$0.000000`.

## Error log

Error-log count: **9**

The numbered log runs from `#11` through `#19`. It includes the initial misclassification of the incident, SQL alias errors, ordering correction, affected-row overcount, the unavailable CSV-export request, and an inconsistent valuation label in the first SUMMARY draft.

The complete entries are in `root_cause.md`.

## Public evidence

* [Before model — Dune 7992111](https://dune.com/queries/7992111/)
* [Initial WETH/AVAIL diagnosis — Dune 7992273](https://dune.com/queries/7992273/)
* [Affected rows — Dune 8072957](https://dune.com/queries/8072957/)
* [Fixed model — Dune 8075341](https://dune.com/queries/8075341/)
* [Regression diff — Dune 8080408](https://dune.com/queries/8080408/)

## Files

* `root_cause.md`
* `model_fixed.sql`
* `affected_rows.sql`
* `regression_diff.sql`
* `impact.csv`
* `SUMMARY.md`

Scope warning: this package repairs only the accepted WETH/AVAIL rows inside the frozen window. It does not claim an all-pool or all-time correction.
