# Uniswap V3 USD Valuation Incident Repair

This change package serves engineering and product teams. They will query which rows changed, why each row changed, whether any unrelated row moved, and whether the repaired fee and revenue model can be reproduced from public data.

## What this package fixes

The legacy model used `dex.trades.amount_usd` as the fee-calculation base.

For two material WETH/AVAIL trades, `amount_usd` matched the bought WETH leg. The raw Swap events were valid, but the fee model needed the USD value of the sold input token.

For the 142 repaired rows, the fixed formula is:

```text
fixed_fee_base_usd
    = token_sold_amount
    × sold_token_minute_price_usd
```

Every other row retains the legacy fee base. The repair keeps the original Swap events and `dex.trades.amount_usd`.

## Scope

```text
Blockchain: Ethereum
Protocol:   Uniswap V3
Window:     [2026-06-14 00:00:00, 2026-07-14 00:00:00) UTC
Pool:       0x80f8143fa056a063aaeecec3323aa3426262ddb2
Pair:       WETH/AVAIL
```

Primary data paths:

* `dex.trades`
* `prices.usd`
* `tokens.erc20`
* `uniswap_v3_ethereum.uniswapv3pool_evt_swap`
* `uniswap_v3_ethereum.uniswapv3factory_evt_poolcreated`
* `uniswap_v3_ethereum.uniswapv3pool_evt_setfeeprotocol`

## Result

| Check                              |    Result |
| ---------------------------------- | --------: |
| Base trade rows                    | 3,105,881 |
| Unique `(tx_hash, evt_index)` keys | 3,105,881 |
| Target-pool rows reviewed          |       256 |
| Repaired rows                      |       142 |
| Verified no-op target rows         |       114 |
| Unaffected rows proven unchanged   | 3,105,739 |
| Legacy unpriced rows retained      |    12,314 |
| Unexpected changed rows            |         0 |

The largest reviewed row had:

```text
legacy amount_usd = $1,900,384.829449
input-side USD    = $6.234174
multiple          = 304,833.4685×
```

## Metric impact

| Metric           |              Before |               After |            Change |   Change % |
| ---------------- | ------------------: | ------------------: | ----------------: | ---------: |
| Fees             | `$7,457,019.231172` | `$7,437,622.456387` | `-$19,396.774785` | `-0.2601%` |
| Supply-side fees | `$6,036,443.164674` | `$6,020,279.185686` | `-$16,163.978988` | `-0.2678%` |
| Revenue          | `$1,420,576.066498` | `$1,417,343.270700` |  `-$3,232.795798` | `-0.2276%` |

The unrounded accounting residual is `$0.000000`. Independently rounded six-decimal outputs produce a `$0.000001` display-only residual.

## Files

| File                  | Purpose                                                          |
| --------------------- | ---------------------------------------------------------------- |
| `root_cause.md`       | Evidence, root cause, policy decisions, residuals, and error log |
| `model_fixed.sql`     | Repaired fee and revenue model                                   |
| `affected_rows.sql`   | Complete 142-row repair set with keys and reason codes           |
| `regression_diff.sql` | Expected-versus-actual and unaffected-row checks                 |
| `impact.csv`          | Before-and-after metric differences                              |
| `SUMMARY.md`          | Sixty-second recruiter summary                                   |

## Public Dune queries

| Query                                        | Purpose                      |
| -------------------------------------------- | ---------------------------- |
| [7992111](https://dune.com/queries/7992111/) | Frozen legacy model          |
| [7992273](https://dune.com/queries/7992273/) | Initial WETH/AVAIL diagnosis |
| [8072957](https://dune.com/queries/8072957/) | Accepted affected-row set    |
| [8075341](https://dune.com/queries/8075341/) | Fixed model                  |
| [8080408](https://dune.com/queries/8080408/) | Regression diff              |

## Reproduction

1. Run `affected_rows.sql`.
2. Confirm that it returns 142 unique affected keys, 140 ordinary reason rows, two material reason rows, and no null fixed values.
3. Run `model_fixed.sql`.
4. Confirm these six-decimal outputs:

```text
fees_usd            = 7437622.456387
supply_side_fees_usd = 6020279.185686
revenue_usd         = 1417343.270700
```

5. Run `regression_diff.sql`.
6. Confirm:

```text
matched_changed_rows      = 142
missing_expected_rows     = 0
unexpected_actual_changed_rows = 0
changed_unaffected_rows   = 0
all_checks_pass           = true
```

`regression_diff.sql` reads the accepted public result through `query_8072957`.

## Policy decisions

| Decision | Choice                                               |
| -------- | ---------------------------------------------------- |
| B1       | Real but extreme on-chain behavior                   |
| B2       | Repair the metric formula                            |
| B3       | Recompute all 142 affected rows in the frozen window |
| B26      | Serve engineering and product users                  |

The complete alternatives, benefits, costs, and evidence are in `root_cause.md`.

## Acceptance statement

The model changes exactly the accepted 142-row repair set. It leaves the other 3,105,739 rows unchanged at six-decimal reporting precision. Every changed row retains `tx_hash`, `evt_index`, `block_number`, and `reason_code`.

## Limits

This package does not apply a global all-pool or all-time rewrite.

The fixed USD values depend on the sold-token minute prices in `prices.usd`. A separate review is required before extending the policy outside the accepted WETH/AVAIL scope.

## Related work

This incident package follows the published Uniswap V3 revenue reconstruction:

* [Medium article](https://medium.com/@biylj52/i-rebuilt-uniswap-v3s-revenue-from-raw-on-chain-data-token-terminal-and-i-disagree-by-1-80-10688525ed0a)
* [Portfolio repository](https://github.com/six-decimals/onchain-data-portfolio)
