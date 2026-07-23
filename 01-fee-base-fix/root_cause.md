# Uniswap V3 USD Valuation Incident: Root Cause and Repair

This change package serves engineering and product teams. They will query which rows changed, why each row changed, whether any unrelated row moved, and whether the repaired fee and revenue model can be reproduced from public data.

## 1. Incident summary

The legacy model used `dex.trades.amount_usd` as the fee-calculation base for every trade. That field can represent a valid USD value for the trade while matching the output leg instead of the input leg.

A fee base is the amount to which a fee rate is applied, like the bill total used to calculate a service charge.

Uniswap V3 charges the swap fee in the input token. The official V3 pool contract labels `SwapCache.feeProtocol` as the protocol fee for the input token. It also records `feeGrowthGlobalX128` for the input token and describes `StepComputations.feeAmount` as the fee paid in. The Uniswap support documentation states the same rule in plain language.

Sources:

- [Uniswap V3 core — `contracts/UniswapV3Pool.sol`](https://github.com/Uniswap/v3-core/blob/main/contracts/UniswapV3Pool.sol)
- [Uniswap Labs — What is a liquidity provider fee?](https://support.uniswap.org/hc/en-us/articles/20901935681677-What-is-a-liquidity-provider-LP-fee)

The repair does not rewrite the Swap events or delete `dex.trades.amount_usd`. It changes the metric formula for 142 evidence-backed rows. Their fee base becomes:

```text
token_sold_amount × sold_token_minute_price_usd
````

## 2. Frozen scope

The analysis uses this fixed UTC window:

```text
[2026-06-14 00:00:00, 2026-07-14 00:00:00)
```

The base relation is:

```text
dex.trades
```

The filters are:

```text
blockchain = 'ethereum'
project = 'uniswap'
version = '3'
```

The frozen base contains 3,105,881 rows. It contains 3,105,881 distinct `(tx_hash, evt_index)` keys. The duplicate-key surplus is zero. The legacy USD field is null for 12,314 rows.

The incident repair is limited to this pool:

```text
0x80f8143fa056a063aaeecec3323aa3426262ddb2
```

The pool metadata is:

| Position | Token | Address                                      | Decimals |
| -------- | ----- | -------------------------------------------- | -------: |
| token0   | WETH  | `0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2` |       18 |
| token1   | AVAIL | `0xeeb4d8400aeefafc1b2953e0094134a887c76bd8` |       18 |

The metadata source is `tokens.erc20`. Each address returned one metadata row.

The fixed USD input value uses:

```text
prices.usd.price
```

The price join is:

```text
prices.usd.blockchain = 'ethereum'
prices.usd.contract_address = dex.trades.token_sold_address
prices.usd.minute = DATE_TRUNC('minute', dex.trades.block_time)
```

The target pool contains 256 trades in the frozen window. All 256 have an input-token minute price. The price join creates no duplicate `(tx_hash, evt_index)` keys.

Sources: Dune queries [8072957](https://dune.com/queries/8072957/) and [8080408](https://dune.com/queries/8080408/).

## 3. What the extreme rows contained

The largest observed legacy value was:

```text
legacy amount_usd = $1,900,384.829449
input-side USD    = $6.234174
multiple          = 304,833.4685×
```

Its key is:

```text
block_number = 25467373
tx_hash      = 0xb1a43313b51512b45fc5d921838a8a6427266f4326e5d82cde7cdbe02daa3349
evt_index    = 18
```

The trade sold `2,154.172018403229700000` AVAIL and received `1,072.464039915017000000` WETH. The AVAIL minute price was `$0.002894000000000000`. The legacy USD value matched the bought WETH leg at six decimal places.

A second material row had this key:

```text
block_number = 25467373
tx_hash      = 0x8e9729a99617f32f9a235ed315bc5affd9749547c5d2bda50c8166648211293e
evt_index    = 28
```

It sold `6,635,159.648062751000000000` AVAIL and received `33.053308304379910000` WETH. Its legacy fee base was `$58,569.801249`. Its fixed input-side fee base was `$19,202.152021`.

The raw Swap source was:

```text
uniswap_v3_ethereum.uniswapv3pool_evt_swap
```

The first material event contained:

```text
amount0 = -1072464039915017062545
amount1 =  2154172018403229647873
```

The second material event contained:

```text
amount0 = -33053308304379908572
amount1 =  6635159648062750744729690
```

For both events, negative `amount0` represented WETH leaving the pool and positive `amount1` represented AVAIL entering the pool. The raw integers matched `dex.trades.token_bought_amount_raw` and `dex.trades.token_sold_amount_raw`.

This evidence supports a real but extreme on-chain swap. It does not support a decoder correction or deletion of the trade.

## 4. Root cause

The root cause was a metric-formula mismatch.

The legacy query calculated fees as:

```text
dex.trades.amount_usd × fee_tier / 1,000,000
```

The field `dex.trades.amount_usd` was not proven false. For the two material rows, it matched the USD value of the WETH output leg. The problem appeared only when the revenue model treated that general trade value as the input-token fee base.

The fixed query uses:

```text
fixed_fee_base_usd
    = token_sold_amount
    × prices.usd price for token_sold_address

fees_usd
    = fixed_fee_base_usd
    × fee_tier
    / 1,000,000

revenue_usd
    = fees_usd
    / active input-token protocol-fee divisor
```

The model still orders fee-setting events by `block_number, evt_index`. It still leaves the 12,314 unpriced base rows unvalued.

## 5. Layer diagnosis

| Layer                         | Decision                      | Evidence                                                                                          |
| ----------------------------- | ----------------------------- | ------------------------------------------------------------------------------------------------- |
| Raw capture or decoder        | Do not change                 | The two material Swap events reconcile to the raw sold and bought token integers.                 |
| Protocol staging              | Do not change                 | The material rows preserve the correct input and output direction.                                |
| Canonical model               | Do not change                 | WETH and AVAIL addresses and decimals are unique in `tokens.erc20`.                               |
| Metric formula                | Change                        | The legacy formula used a general trade USD value as the input-token fee base.                    |
| Price, label, or filter layer | Do not change in this package | The old WETH-side value can be valid as a trade valuation. The model used it in the wrong metric. |

Every modified row is therefore classified at the metric-formula layer.

The row-level reason codes are:

| Reason code                                 | Rows |
| ------------------------------------------- | ---: |
| `FEE_BASE_INPUT_SIDE_REVALUATION`           |  140 |
| `FEE_BASE_INPUT_SIDE_REVALUATION_GT_100PCT` |    2 |
| Unexpected reason code                      |    0 |

Each row retains `tx_hash`, `evt_index`, `block_number`, the before value, the after value, and its reason code.

Source: Dune query [8072957](https://dune.com/queries/8072957/).

## 6. Affected-row policy

A target-pool row enters the repair set only when all conditions below hold:

1. It falls inside the frozen UTC window.
2. It belongs to the WETH/AVAIL pool.
3. The sold-token amount is present.
4. The sold-token minute price is present.
5. The legacy and fixed fee bases differ at six decimal places.

The target pool contains 256 reviewed rows. The repair changes 142 rows. The other 114 rows are verified no-ops at six decimal places.

The 142 rows are ordered by:

```text
block_number, evt_index, tx_hash
```

No affected key is duplicated. No fixed fee base is null.

## 7. Before, affected, and after tables

| Table    | Public query                                      | Purpose                       |
| -------- | ------------------------------------------------- | ----------------------------- |
| Before   | [Dune 7992111](https://dune.com/queries/7992111/) | Frozen legacy model           |
| Affected | [Dune 8072957](https://dune.com/queries/8072957/) | The 142 rows that must change |
| After    | [Dune 8075341](https://dune.com/queries/8075341/) | Repaired model and totals     |

The before query remains public and unchanged. It is the historical comparison point.

## 8. Financial impact

| Metric           |              Before |               After |            Change |   Change % |
| ---------------- | ------------------: | ------------------: | ----------------: | ---------: |
| Fees             | `$7,457,019.231172` | `$7,437,622.456387` | `-$19,396.774785` | `-0.2601%` |
| Supply-side fees | `$6,036,443.164674` | `$6,020,279.185686` | `-$16,163.978988` | `-0.2678%` |
| Revenue          | `$1,420,576.066498` | `$1,417,343.270700` |  `-$3,232.795798` | `-0.2276%` |

Before source: Dune query [7992111](https://dune.com/queries/7992111/).

After source: Dune query [8075341](https://dune.com/queries/8075341/).

The repair does not change the 3,105,881-row population. It changes the fee base for 142 rows.

## 9. Regression result

The regression query compares the accepted affected set with an independent reconstruction of the repair policy.

It returned:

```text
expected affected rows       = 142
actual changed rows           = 142
matched changed rows          = 142
missing expected rows         = 0
unexpected changed rows       = 0
fixed-value mismatches        = 0
reason-code mismatches        = 0
changed unaffected rows       = 0
unchanged unaffected rows     = 3,105,739
newly null rows               = 0
unexpectedly filled null rows = 0
all_checks_pass               = true
```

All 3,105,739 unaffected rows remained unchanged at the required six-decimal reporting precision.

Source: Dune query [8080408](https://dune.com/queries/8080408/).

## 10.  Metric policy decisions

### B1 — What was the abnormal number?

Options considered:

1. Real but extreme on-chain behavior.
2. Contract-event decoding error.
3. Protocol-level conversion error.
4. Canonical mapping error.
5. Price or address-label error.

Decision: **B1 = 1. Real but extreme on-chain behavior.**

Reason: The two material rows reconcile to the raw Swap integers and trade direction. Their legacy USD values match the WETH output leg. That is not evidence that the Swap or `amount_usd` must be deleted.

Benefit: The package preserves valid raw and canonical data.

Cost: The document cannot describe `dex.trades.amount_usd` as corrupted. The error exists only when the fee model uses it as the input-token fee base.

### B2 — Which layer should be repaired?

Options considered:

1. Raw capture or decoder.
2. Protocol staging model.
3. Canonical model.
4. Metric formula.
5. Price, label, or filter layer.

Decision: **B2 = 4. Metric formula.**

Reason: Uniswap V3 takes the fee in the input token. The old model applied the fee tier to a trade USD value that could match the output leg.

Benefit: The repair changes the layer that created the wrong metric and preserves the underlying Swap facts.

Cost: The repair is narrow. It does not claim that every use of `dex.trades.amount_usd` is wrong.

### B3 — How should historical rows be handled?

Options considered:

1. Correct and recompute all affected history.
2. Temporarily exclude the rows.
3. Keep the rows and add an error or low-confidence flag.
4. Isolate the rows until more evidence is available.

Decision: **B3 = 1. Correct and recompute all affected history inside the frozen window.**

Reason: The package has a deterministic input-side value for all 142 affected rows.

Benefit: The fixed model keeps the trades and returns complete revised metrics.

Cost: Published metrics for the frozen window change. This decision does not authorize an untested all-time or all-pool backfill.

### B26 — Which customer does this table serve?

Options considered:

1. Financial risk.
2. Engineering and product.
3. Research and strategy.

Decision: **B26 = 2. Engineering and product.**

These users will query the changed keys, the reason codes, the fixed fee bases, the regression result, and the reproducibility of the model.

Benefit: This matches the operational purpose of a data incident change package.

Cost: Financial impact remains an acceptance result instead of the main product narrative.

## 11. Residual explanation

A residual is the amount left after both sides of an accounting equation are subtracted, like the final cent left after splitting a bill.

### R-01 — `DISPLAY_ROUNDING_6DP`

```text
Displayed fees
- displayed supply-side fees
- displayed revenue
= $0.000001
```

Each displayed metric is rounded independently to six decimal places. The unrounded accounting residual in Dune query 8075341 is `$0.000000`.

This is a display-only residual. It does not represent a missing trade or an unexplained model change.

Residual count: **1**.

## 12. Error log

### #11

**Error →** I described Dune query 7992111 as an input-side model.

**How discovered →** The frozen SQL showed that it used `dex.trades.amount_usd` directly.

**Correction →** I preserved its exact results but renamed it the legacy Dune USD model.

### #12

**Error →** I ranked tied trades with `block_time` instead of the required event order.

**How discovered →** The project rule requires every ordering and reconciliation to use `block_number, evt_index`.

**Correction →** I changed the ordering to `block_number, evt_index, tx_hash`.

### #13

**Error →** I treated all 256 reviewed WETH/AVAIL trades as affected.

**How discovered →** A six-decimal comparison found 142 changed rows and 114 verified no-ops.

**Correction →** I limited the affected set to the 142 rows whose fee bases change at six decimal places.

### #14

**Error →** A diagnostic query exposed an ambiguous `legacy_amount_usd` reference.

**How discovered →** Dune returned `Column 'legacy_amount_usd' is ambiguous`.

**Correction →** I qualified the overlapping fields with explicit CTE aliases.

### #15

**Error →** I assumed that an available input-side price was automatically the correct explanation.

**How discovered →** A two-leg comparison showed that the legacy value matched the bought WETH leg.

**Correction →** I separated trade valuation from fee-base valuation and checked the raw Swap direction.

### #16

**Error →** A query referenced `s.contract_address` after the CTE had renamed that field to `pool`.

**How discovered →** Dune returned `Column 's.contract_address' cannot be resolved`.

**Correction →** I joined with the exposed `pool` alias.

### #17

**Error →** I initially treated the WETH-side USD value as a price-source error.

**How discovered →** The raw `amount0` and `amount1` integers matched the decoded sold and bought token fields for both material rows.

**Correction →** I kept the raw Swap and `dex.trades.amount_usd`, changed B1 to real but extreme behavior, and repaired the metric formula.

### #18

**Error →** I requested a CSV export from a Dune account that does not provide CSV export.

**How discovered →** The account limitation was confirmed during affected-row validation.

**Correction →** I replaced CSV-based validation with one-row acceptance queries and five specified row samples.

### #19

**Error →** The first SUMMARY draft labeled the two largest-row values as `legacy fee base` and `fixed fee base`, while `root_cause.md` identified them as legacy `amount_usd` and input-side USD.

**How discovered →** A cross-file label check found that the same two values described different data layers.

**Correction →** I restored the source-level labels: `legacy amount_usd` and `input-side USD`. The fee-base interpretation remains in the model-formula section.

Error-log count: **9**.

## 13. Limits

This package repairs only the 142 accepted WETH/AVAIL keys in the frozen window.

It does not prove that every other pool uses the correct USD fee base. A global change would require a separate affected-set review and regression test.

The repaired USD values still depend on `prices.usd`. If the sold-token minute price is missing or wrong, the token-denominated fee can remain correct while its USD value is wrong.

The conclusion would need to be reopened if:

* the public Dune source tables change their historical rows;
* `prices.usd` changes the relevant minute prices;
* the affected query no longer returns the same 142 keys;
* Uniswap fee mechanics are interpreted differently from the deployed V3 core contract.

## 14. Package files

* `model_fixed.sql` — repaired fee and revenue model.
* `affected_rows.sql` — the complete 142-row repair set.
* `regression_diff.sql` — full-set and unaffected-row regression checks.
* `impact.csv` — before-and-after metric differences.
* `root_cause.md` — incident evidence, decisions, residuals, and error log.

