# Ethereum Stablecoin Organic-Activity Methodology

This project builds an address-level screening method for Ethereum USDC and
USDT activity. It asks a narrow question: among addresses with sustained
activity, how many show no screening signal, one signal family, or at least
two independent signal families?

An **actor proxy** is one Ethereum address used as the measurable stand-in for
an actor. It is not evidence that one address equals one person. The output is
a triage system, not a detector with labeled ground truth.

For UTC `[2026-06-14, 2026-07-14)`, 399,930 qualified actor proxies produced
the frozen classification below:

| Class | Rule | Actors | Share |
| --- | --- | ---: | ---: |
| `organic candidate` | 0 signal families | 246,237 | 61.570025% |
| `ambiguous` | exactly 1 signal family | 147,761 | 36.946716% |
| `likely inorganic` | at least 2 signal families | 5,932 | 1.483260% |
| Total | partition check | 399,930 | 100.000000% |

The names are deliberately asymmetric. `likely inorganic` requires at least
two families, while `organic candidate` means only that none of the four
implemented families fired. Neither class establishes intent, ownership, or
the absence of behavior the model cannot observe.

## Scope

| Dimension | Frozen definition |
| --- | --- |
| Blockchain | Ethereum |
| Tokens | USDC `0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48`; USDT `0xdac17f958d2ee523a2206206994597c13d831ec7` |
| Main window | UTC `[2026-06-14, 2026-07-14)` |
| Actor unit | One Ethereum address actor proxy |
| Primary event source | `erc20_ethereum.evt_transfer` |
| Curated reconciliation source | `tokens.transfers`, filtered to `blockchain = 'ethereum'` |
| Funding lookback | Rolling 30 days before each actor's first main-window activity |
| Qualification | At least 10 nonzero transaction-token groups and at least 4 active days for one address-token pair |
| Stablecoin valuation | One token unit equals one nominal USD for methodology calculations; this is not a market-price claim |

Both token contracts expose six verified decimals in the observed data. Base
events keep positive transfers and exclude the zero address and self-transfers.

## What the Pipeline Measures

A **transaction-token group** nets every address leg for one token in one
transaction before any metric is calculated. **Transaction-token movement**
then counts the balanced economic movement once rather than summing every raw
transfer leg. This prevents routers and multi-leg transactions from inflating
activity merely because the same value crossed several event rows.

The pipeline proceeds in six stages:

1. Read raw USDC and USDT `Transfer` events and reconcile event keys and raw
   amounts to `tokens.transfers`.
2. Net each transaction-token group and calculate exact integer movement.
3. Qualify address-token pairs using the frozen 10-group and 4-day gate, then
   roll any qualifying pair up to its address actor proxy.
4. Calculate four signal families independently.
5. Count families per actor and assign the three frozen class names.
6. Test sensitivity, inspect 40 deterministic cases, compare an adjacent
   30-day window with an identical lightweight pipeline, and report where the
   evidence does not validate the classification.

## Four Signal Families

An address receives at most one count from each family. Multiple branches
inside the temporal family do not add multiple family counts. A strong funding
flag is a subset of the funding family, not a fifth signal. Here,
`independent` means separately defined evidence families; it is not a claim of
statistical independence.

### 1. Temporal behavior

An actor hits this family when any qualified address-token pair satisfies at
least one branch:

- clock-like regularity: positive median interval, interval coefficient of
  variation at most 7,000 bps, and interquartile range divided by median at
  most 6,000 bps;
- same-second burst: zero-second intervals are at least 2,000 bps of all
  intervals;
- single-day burst: the busiest day contains at least 8,000 bps of groups and
  daily concentration HHI is at least 6,500 bps.

The main window contains 10,886 temporal-signal actors: 1,610 clock-like,
4,783 same-second-burst, and 4,597 single-day-burst actors. Branch counts may
overlap.

### 2. Behavioral richness

This family identifies low counterparty breadth, despite its historical
`richness` name. An actor hits when any qualified address-token pair has at
most two distinct direct counterparties and its largest counterparty accounts
for at least 9,500 bps of direct-counterparty transaction participations.

The main window contains 4,226 actors in this family.

### 3. Funding source

For each qualified actor, the pipeline looks back 30 days from the actor's
first main-window activity. The funding-source proxy is the one direct source
on the earliest positive combined-net-inflow transaction, provided the outer
transaction sender is external to the actor. Sources annotated in
`cex.addresses` are excluded before clustering.

A candidate actor belongs to a non-CEX source cluster with at least 10 actors
where either:

- at least 8,000 bps of the cluster shares an exact funding amount; or
- at least 5,000 bps shares a funding hour.

The strong subset requires both conditions. The frozen manifest contains
1,876 candidate actors and 32 strong actors. Both flags count as one funding
family.

### 4. Economic rationality

For each transfer-bearing Ethereum transaction, the pipeline compares the
transaction's execution fee in USD with combined USDC/USDT movement valued at
nominal face value. A transaction fires when execution fee is at least the
movement value. An actor hits the family when at least 50% of its qualified
nonzero transaction groups fire.

This B5-20 threshold produces 142,666 economic-signal actors. The family is a
cost-pressure diagnostic. It does not prove that an actor is irrational or
automated.

## Strict and Inclusive Estimates

The `ambiguous` class is reported twice instead of being silently assigned:

| Estimate | Actors | Share |
| --- | ---: | ---: |
| Strict organic: `organic candidate` only | 246,237 | 61.570025% |
| Inclusive organic: `organic candidate + ambiguous` | 393,998 | 98.516740% |
| Strict inorganic: `likely inorganic` only | 5,932 | 1.483260% |
| Inclusive inorganic: `ambiguous + likely inorganic` | 153,693 | 38.429975% |

The wide interval is not a confidence interval. It is the exact consequence
of leaving all 147,761 one-family actors unresolved.

## Sybil, Wash, and Bot Detection

The classifier implements a screening rule: one signal family never moves an
actor into `likely inorganic`; two independent families do. This reduces the
risk that ordinary batching, payroll, treasury operations, market making, or
one expensive small transfer is treated as sufficient evidence by itself.

The wash-oriented extension is intentionally separate. Among 1,876 funding
candidates, the pair probe found 476 canonical token-address pairs with events
in both directions, covering 3,714 events and 13,138 directed event-pair
combinations. A 20-cell mutual-best sensitivity grid tested time windows from
5 minutes to 7 days and amount-return tolerances from 0 to 500 bps. No cell was
approved as a classification threshold, and the wash grid is not included in
the four-family classification.

Reverse transfers can be refunds, settlement, routing, treasury operations,
or market making. Shared funding can reflect custodians, bridges, payroll, or
services. Repeated timing can reflect automation without deceptive intent.
The model therefore uses `candidate`, `ambiguous`, and `likely inorganic`, not
`confirmed Sybil`, `wash trader`, or `bot`.

## Validation Results

### Threshold sensitivity

The economic actor gate was tested before B5-20 was frozen:

| Economic actor gate | Economic actors | `organic candidate` | `ambiguous` | `likely inorganic` |
| --- | ---: | ---: | ---: | ---: |
| At least one fee>=movement group | 220,652 | 172,177 | 218,057 | 9,696 |
| At least 25% of nonzero groups | 167,516 | 222,271 | 170,850 | 6,809 |
| At least 50% of nonzero groups — frozen | 142,666 | 246,237 | 147,761 | 5,932 |

The final count for `likely inorganic` is therefore conditional on the
approved 50% gate; the sensitivity grid shows how much this one decision
moves the classification.

### Deterministic 40-case audit

The audit selects 10 addresses from each of four strata: organic boundary,
ambiguous boundary, `likely inorganic` boundary, and high-cooccurrence
extreme.
It then recomputes 10,710 qualified nonzero transaction groups and 5,617
fee>=movement groups for those 40 addresses. All case-level implementation
checks pass.

Only 12 of 40 addresses have any `labels.addresses` annotation, producing 74
annotation rows; none matches `cex.addresses`. Those labels are external and
often describe activity or platform usage rather than legal ownership. The
case audit validates reproducibility and exposes examples for manual review;
it does not establish classification precision or recall.

### Adjacent-window comparison

The lightweight validation uses identical qualification, temporal, richness,
and economic logic in two adjacent nonoverlapping 30-day windows. It excludes
funding history, CEX filtering, clustering, and wash diagnostics in both
windows.

| Window | Qualified actors | `likely inorganic` | Share |
| --- | ---: | ---: | ---: |
| `[2026-06-14, 2026-07-14)` | 399,930 | 5,525 | 1.381492% |
| `[2026-05-15, 2026-06-14)` | 350,671 | 3,306 | 0.942764% |

The difference is 0.438728 percentage points. It shows level sensitivity
under the same lightweight method; it is not a time validation of the full
four-family model.

## Reproducibility

All 28 Dune queries are public. The complete name-to-link ledger is frozen
in [SUMMARY.md](./SUMMARY.md). Core queries are:

- [Four-signal fusion](https://dune.com/queries/8233932)
- [Funding-signal manifest](https://dune.com/queries/8233139)
- [Mutual-best reverse-event sensitivity](https://dune.com/queries/8229715)
- [Known-entity and extreme-case audit](https://dune.com/queries/8238802)
- [Individual-case evidence audit](https://dune.com/queries/8238924)
- [Two-window lightweight validation](https://dune.com/queries/8239247)

The five Q11A manifest blocks reconstruct to 1,876 unique addresses and 32
strong flags. Joining the blocks with `~` produces 88,171 characters and
SHA-256:

```text
3abbfd393dad2c51d95e40c35cc07323b150e86f90e60c2fd4ce7141435997c1
```

## Glossary

| Term | Meaning in this project |
| --- | --- |
| Actor proxy | One Ethereum address used as a measurable stand-in for an actor; not proof of a person or entity. |
| Address-token pair | One actor proxy paired with USDC or USDT. |
| Transaction-token group | All transfer legs for one token in one transaction after address-level netting. |
| Transaction-token movement | Balanced value counted once after netting; not the sum of raw transfer legs. |
| Qualified pair | An address-token pair with at least 10 nonzero groups across at least 4 active days. |
| Signal family | One independent screening dimension; multiple branches inside one family still count once. |
| `organic candidate` | A qualified actor with zero implemented signal families. |
| `ambiguous` | A qualified actor with exactly one signal family. |
| `likely inorganic` | A qualified actor with at least two signal families; not confirmed misconduct. |
| Strict estimate | Leaves every ambiguous actor out of the named side. |
| Inclusive estimate | Assigns every ambiguous actor to the named side. |
| Nominal USD | Stablecoin face-value assumption of one token unit per USD; not a market-price observation. |
| Implementation check | A structural identity for joins, partitions, units, or anchors; not a truth label. |

## Package Contents

- `README.md` — entry point, method, results, glossary, and limitations.
- `SUMMARY.md` — frozen numeric ledger and complete public-query inventory.
- `findings.md` — detailed rulings, validation evidence, failure modes, and
  correction record.

## Limits

The result applies only to Ethereum USDC/USDT activity in the stated windows,
under the frozen thresholds and observed Dune tables. Address labels and CEX
lists have incomplete and time-varying coverage. The method does not observe
off-chain ownership, account relationships, intent, private relays, or actors
that split activity below the qualification gate. Internal zero-residual
checks validate implementation only. Without labeled ground truth, precision,
recall, and a causal interpretation remain unmeasured.
