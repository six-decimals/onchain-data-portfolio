# Findings and Rulings

## 1. Question and Ruling

The analyst needs to prioritize Ethereum stablecoin actors for review without
pretending that public labels provide ground truth. The model therefore
classifies sustained USDC/USDT address activity by the number of independent
screening families it hits.

The ruling is narrow:

```text
0 families  -> organic candidate
1 family    -> ambiguous
2+ families -> likely inorganic
```

For UTC `[2026-06-14, 2026-07-14)`, the model places 5,932 of 399,930
qualified address actor proxies, or 1.483260%, in `likely inorganic`. This is a
review queue. It is not a claim that 5,932 persons, Sybil accounts, bots, or
wash traders were identified.

## 2. Source and Grain Rulings

The live schemas were empirically checked before the final pipeline was built.

| Purpose | Table | Fields used |
| --- | --- | --- |
| Primary transfer events | `erc20_ethereum.evt_transfer` | `contract_address`, `evt_tx_hash`, `evt_tx_index`, `evt_index`, `evt_block_time`, `evt_block_number`, `evt_block_date`, `from`, `to`, `value` |
| Curated reconciliation | `tokens.transfers` | `blockchain`, `block_date`, `block_time`, `tx_hash`, `evt_index`, `from`, `to`, `contract_address`, `amount_raw`, `amount`, `price_usd`, `amount_usd` |
| Outer transaction and gas | `ethereum.transactions` | `hash`, `block_time`, `block_number`, `block_date`, `from`, `to`, `gas_used`, `gas_price`, `success` |
| Curated fee anchor | `gas.fees` | Ethereum-filtered transaction fee fields |
| Primary ETH price | `prices.hour` | `timestamp`, `blockchain`, `contract_address`, `symbol`, `price`, `decimals` |
| Entity annotation | `labels.addresses` | `blockchain`, `address`, `name`, `category`, `contributor`, `source`, `created_at`, `updated_at`, `model_name`, `label_type` |
| CEX annotation | `cex.addresses` | `blockchain`, `address`, `cex_name`, `distinct_name`, `added_by`, `added_date` |

`erc20_ethereum.evt_transfer` is the primary source. `tokens.transfers` is an
independent curated reconciliation layer and must be filtered to
`blockchain = 'ethereum'`. Labels and CEX lists are annotations, not on-chain
ownership records.

The token scope is exact:

- USDC: `0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48`;
- USDT: `0xdac17f958d2ee523a2206206994597c13d831ec7`.

Both expose six decimals in the verified data. Base events retain positive
amounts and exclude the zero address and self-transfers.

The event grain is token contract plus transaction hash plus event index. The
main-window audit found 50,207,977 rows, the same number of distinct event
keys, zero duplicate surplus, and exact raw/curated amount reconciliation.

## 3. Transaction-Token Movement

Raw event volume is not economic movement. Routers and multi-leg transfers can
move the same value through several addresses in one transaction. The model
first calculates each address's signed net amount for one token and
transaction:

```text
signed net = incoming raw amount - outgoing raw amount
```

It then calculates balanced transaction-token movement:

```text
movement_raw = sum(abs(address signed net)) / 2
```

The division by two counts the balanced value once because every retained
inflow has a corresponding outflow. Nonzero net residual, inflow/outflow
mismatch, and movement-above-gross checks were all zero in the frozen base.

Main-window movement:

| Token | Eligible events | Transaction-token groups | Exact movement raw | Movement / eligible gross |
| --- | ---: | ---: | ---: | ---: |
| USDC | 19,190,433 | 7,174,029 | 364,368,047,345,240,847 | 26.778500% |
| USDT | 26,448,839 | 11,350,500 | 247,805,960,113,938,207 | 44.360300% |

Here, gross means the positive transfer amount after the base-event eligibility
filters; it is not the unfiltered Q01 raw-amount total. The lower ratios show
why summing eligible event legs would answer a different question. They do not
by themselves distinguish organic from inorganic activity.

## 4. Qualification Ruling

An address-token pair qualifies at:

- at least 10 nonzero transaction-token groups; and
- at least 4 active UTC dates.

An address enters the actor universe when either its USDC or USDT pair
qualifies. This produces:

| Metric | USDC | USDT | Combined |
| --- | ---: | ---: | ---: |
| Qualified pairs | 159,125 | 262,930 | 422,055 |
| Qualified nonzero groups | 17,272,514 | 24,813,646 | 42,086,160 |

Distinct qualified address actor proxies: 399,930.

This gate removes low-observation addresses before behavioral thresholds are
applied. It also creates a false-negative channel: an actor can deliberately
split activity across addresses or remain below either gate.

## 5. Signal-Family Rulings

### 5.1 Temporal behavior

Each qualified address-token pair is tested for three patterns:

1. `clock_like_regular`: median interval is positive, interval CV is at most
   7,000 bps, and `(p75 - p25) / median` is at most 6,000 bps;
2. `same_second_burst`: zero-second intervals are at least 2,000 bps of all
   intervals;
3. `single_day_burst`: maximum-day share is at least 8,000 bps and daily HHI is
   at least 6,500 bps.

Any branch on any qualified token pair gives the address one temporal family.
The three branches cannot add three family counts. The main-window union is
10,886 actors.

These patterns can detect rigid automation or bursts, but automation is not
synonymous with abuse. Payroll, treasury execution, scheduled payments, and
operational batching can produce the same shapes.

### 5.2 Behavioral richness

The historical family name is `richness`, but the firing condition is low
breadth and high concentration:

```text
distinct direct counterparties <= 2
AND maximum counterparty share >= 9,500 bps
```

Any qualifying token pair gives the address one richness family. The main
window contains 4,226 such actors.

The signal can find repetitive closed interaction, but it also captures
ordinary users who repeatedly use one router, exchange deposit address,
merchant, or counterparty.

### 5.3 Funding source

The funding analysis orders each actor's main-window activity by
`block_number`, transaction index, transaction hash, and token. It then scans
the preceding 30 days and finds the earliest transaction with positive
combined USDC/USDT net inflow.

The B5-17 funding proxy requires:

- positive combined net inflow;
- exactly one direct source address;
- one matching raw transaction row; and
- an outer transaction sender different from the actor.

Of 399,930 actors, 372,096 satisfy this proxy. Sources in `cex.addresses` split
79,253 actors from 292,843 actors funded by non-CEX-annotated sources.

The B5-18 candidate gate requires a non-CEX source cluster of at least 10
actors and either:

- exact same-amount share of at least 8,000 bps; or
- same-hour share of at least 5,000 bps.

The candidate set is 83 sources and 1,876 actors. Requiring both conditions
produces a strong subset of 3 sources and 32 actors. Candidate and strong count
as one family.

CEX exclusion removes one known false-positive type. It does not prove that
the remaining source controls its recipients. Bridges, payroll distributors,
custodians, routers, and ordinary services can remain.

### 5.4 Economic rationality

For each transfer-bearing Ethereum transaction:

```text
fee_wei = gas_used * gas_price
fee_usd = fee_wei / 1e18 * hourly ETH price
movement_usd = combined USDC/USDT movement_raw / 1e6
fee_to_movement_bps = 10,000 * fee_usd / movement_usd
```

The ETH price comes from the empirically selected Ethereum hourly-price row in
`prices.hour`. Stablecoin movement is valued at one nominal USD per token unit,
not from a market-price observation.

A transaction fires when `fee_to_movement_bps >= 10,000`. B5-20 assigns the
economic family to an address when at least 50% of its qualified nonzero
groups fire. This produces 142,666 actors.

The exact main-window fee ledger contains 17,564,979 unique transactions,
2,687,504,361,668,181,160,550 wei, and 4,547,915.054730 USD in execution
fees. Exact aggregation occurs before unit conversion.

The signal identifies transactions where measured execution cost is at least
measured nominal movement. It does not prove irrationality: a small stablecoin
movement can be incidental to a larger transaction purpose that this metric
does not value.

## 6. Fusion Result

The four separately defined family booleans are added once per actor. This
design separation is not a claim of statistical independence. At the frozen
B5-20 economic gate:

| Class | Actors | Share |
| --- | ---: | ---: |
| `organic candidate` | 246,237 | 61.570025% |
| `ambiguous` | 147,761 | 36.946716% |
| `likely inorganic` | 5,932 | 1.483260% |

The exact partition closes to 399,930.

The strongest conclusion is not that 1.483260% is the true inorganic share.
It is that 5,932 addresses meet a transparent two-family review rule under
the frozen definitions, while 147,761 one-family addresses remain unresolved.

Strict/inclusive bounds preserve that unresolved group:

- organic: 61.570025% strict to 98.516740% inclusive;
- inorganic: 1.483260% strict to 38.429975% inclusive.

These are assignment bounds, not probability intervals.

## 7. Economic-Threshold Sensitivity

The actor-level economic gate was the only unfrozen aggregation threshold when
Q11B first ran. Its grid produced:

| Gate | Economic actors | `likely inorganic` | Share |
| --- | ---: | ---: | ---: |
| At least one fee>=movement group | 220,652 | 9,696 | 2.424424% |
| At least 25% of groups | 167,516 | 6,809 | 1.702548% |
| At least 50% of groups | 142,666 | 5,932 | 1.483260% |

The third row was frozen as B5-20. The 4,129-address range between the
first and third counts for `likely inorganic` shows that the output is
materially conditional on this decision.

## 8. Sybil, Wash, and Bot Investigation

### 8.1 Reverse-edge universe

Among the 1,876 funding candidates, 83,075 candidate-touching events reduce to
26,548 directed token-address pairs. Exactly 952 directed rows have a reverse
edge, forming 476 canonical pairs with 3,714 events and 13,138 possible
directed cross-direction combinations.

The 476-pair manifest was frozen before exact matching. This architectural
decision prevents every wash diagnostic from rebuilding qualification, the
30-day funding graph, CEX filtering, and source clustering.

### 8.2 Mutual-best sensitivity

Q10B tested 20 combinations:

- time windows: 5 minutes, 1 hour, 6 hours, 24 hours, and 7 days;
- amount-return tolerances: 0, 10, 100, and 500 bps.

Each event selects its closest qualifying reverse event. Exact raw-amount
difference and deterministic event order break ties. Only mutual selections
remain.

No cell was frozen as a wash threshold, so this signal was not required for
the final four-family classifier. The validation record is intentionally
partial: rows 1-10 were fully reviewed; row 11 anchors and rows 11-20
`implementation_checks_pass` were spot-checked; specific latter-half grid
values were not reviewed. A duplicate `maximum_time_gap_seconds` alias makes
that copied display column invalid. The calculation was not rerun because the
defect is in the output layer and does not change matching.

### 8.3 Interpretation

Reverse transfers are not wash truth. Refunds, settlement, treasury movement,
routing, market making, and repeated ordinary counterparties can all generate
two-way edges. The current evidence supports a review feature, not a verdict.

## 9. Funding-Manifest Verification

Q11A exported the 1,876 funding actors in five chunks. Query-external
reconstruction found:

- actor counts `400 + 400 + 400 + 400 + 276 = 1,876`;
- strong counts `7 + 5 + 7 + 9 + 4 = 32`;
- 1,876 parsed rows and 1,876 distinct addresses;
- chunk characters `88,167`, plus four delimiters = `88,171`.

Reconstructed manifest SHA-256:

```text
3abbfd393dad2c51d95e40c35cc07323b150e86f90e60c2fd4ce7141435997c1
```

This validates copy completeness. It does not validate the behavioral meaning
of the funding signal.

## 10. Forty-Case Audit

Audit option A selects four disjoint ten-address strata:

1. zero-family organic boundary;
2. one-family ambiguous boundary;
3. two-family `likely inorganic` boundary;
4. three-or-more-family high-cooccurrence extreme.

For the first three strata, addresses nearest the 50% economic boundary rank
first. High-cooccurrence cases rank by family count, economic share,
zero-second share, qualified group count, and finally address dictionary order.
The address key makes every tie deterministic.

Only after the 40 addresses are selected does the query join
`labels.addresses` and `cex.addresses`. This prevents external annotations
from changing selection and avoids joining those tables to all 399,930 actors.

The result contains:

- 40 distinct addresses, 10 per stratum;
- 12 labeled addresses and 74 label rows;
- zero CEX-annotated addresses.

Q12B independently rebuilds the case-level temporal, counterparty, and
economic evidence. It reproduces 10,710 qualified nonzero groups and 5,617
fee>=movement groups. Funding flags remain inherited from Q12A and are not
recomputed.

The audit proves deterministic selection and case-level reproducibility. It
does not estimate classifier accuracy. Many returned labels are usage or
persona annotations rather than named legal entities, and no CEX control group
appears in the sample.

## 11. Adjacent-Window Validation

Q12C applies one parameterized lightweight pipeline to two adjacent,
nonoverlapping 30-day windows. The CTE bodies and thresholds are identical.
Funding history, CEX exclusion, clustering, and wash expansion are excluded
from both windows so the comparison is lightweight against lightweight.

| Window | Qualified actors | `likely inorganic` | Share |
| --- | ---: | ---: | ---: |
| Main | 399,930 | 5,525 | 1.381492% |
| Preceding | 350,671 | 3,306 | 0.942764% |

The main-window share is 0.438728 percentage points higher, or 46.5363%
relative to the preceding-window share. This establishes level sensitivity
under identical lightweight logic. It does not identify the cause and does
not validate the full four-family classification over time.

## 12. False Positives and False Negatives

| Channel | Direction | Why it matters |
| --- | --- | --- |
| Payroll, custodians, bridges, routers, and distributors | False positive | Many recipients can share source, amount, or hour without common control. |
| One dominant exchange, router, merchant, or counterparty | False positive | Low breadth and high counterparty concentration can be ordinary usage. |
| Scheduled operations and batching | False positive | Regular intervals or same-second bursts can be legitimate automation. |
| Small incidental stablecoin leg in a complex transaction | False positive | Gas can exceed observed stablecoin movement while the transaction has another purpose. |
| Refunds, settlement, treasury, and market making | False positive | Two-way transfers can look like reverse-event loops. |
| Address splitting below 10 groups or 4 days | False negative | The actor never enters the qualified universe. |
| Multiple funding sources or censored history | False negative | The single-source proxy rejects or cannot classify the actor. |
| Missing or stale CEX/entity annotations | Either | Annotation joins can fail to exclude a service or fail to supply an audit anchor. |
| Behavior outside USDC/USDT and Ethereum | False negative | The method cannot observe other assets or chains. |
| Adversarial threshold avoidance | False negative | Actors can vary timing, amounts, counterparties, or source structure around fixed gates. |

Without labeled ground truth, the project cannot quantify these rates.

## 13. Cost and Degradation Architecture

Every query runs on Dune's free tier, so computational cost is part of the
methodology.

| Layer | Execution rule |
| --- | --- |
| Main-window events and simple aggregates | Run in full. |
| Qualification and accepted temporal/counterparty distributions | Run in full once. |
| Thirty-day funding graph and clustering | Run once, freeze anchors and actor manifest, never rebuild downstream. |
| Reverse-event matching | Restrict to the frozen 476 canonical pairs. |
| Four-family fusion | Hardcode the verified 1,876-actor funding manifest. |
| Case audit | Select at most 40 actors before joining annotation tables. |
| Out-of-sample comparison | Use the same lightweight pipeline in both windows; exclude funding and wash layers. |
| Copied query output | At most 10 rows, preferably at most 5; use packed manifests when needed. |

This architecture was not optional optimization. Multiple queries exceeded
Dune's stage limit when pipeline reconstruction, historical-anchor proof, and
manifest formatting were combined.

## 14. Decision Register

The project decision ledger, kept outside this repository, holds the
authoritative numbering. The preserved decisions needed to reproduce the
final model are:

| Decision | Frozen effect |
| --- | --- |
| B5-11 | Qualify at 10 nonzero groups and 4 active days. |
| B5-12 | Temporal family uses the three implemented branches and any-pair actor roll-up. |
| B5-13 | Counterparty family uses at most 2 counterparties and at least 9,500 bps maximum share, with any-pair roll-up. |
| B5-14 | Option A accepted before fee-source implementation; original option prose is not reconstructed. |
| B5-15 | Transaction economic signal is fee>=movement. |
| B5-16 | Actor proxy unit is one Ethereum address. |
| B5-17 | Funding proxy is the earliest positive combined-net-inflow transaction with one direct source and external initiation. |
| B5-18 | Cluster at least 10; candidate uses amount>=8,000 bps OR hour>=5,000 bps; strong uses both. |
| B5-19 | Exact reverse-event diagnostics proceed only on the frozen 476-pair manifest. |
| B5-20 | Economic actor family requires fee>=movement in at least 50% of qualified nonzero groups. |
| Audit option A | Four deterministic 10-address strata, total cap 40. |

B5-01 through B5-10 were approved in the original methodology draft, but
their verbatim prose is unavailable in the preserved record. This document
does not reconstruct or paraphrase missing rulings as if they were recovered.

## 15. Implementation Failures and Corrections

The external correction ledger remains authoritative. This table records
only failures whose technical substance is preserved; it does not invent
missing error numbers.

| Failure | Evidence or symptom | Permanent correction |
| --- | --- | --- |
| UNNEST alias arity mismatch | `Column alias list has 1 entries but u has 2 columns` | Derive row shape and alias arity before delivery. |
| Time-zone type assumed instead of evidenced | Three Q08B type/function failures | Verify live field type and trace every time conversion. |
| Non-ASCII whitespace in generated SQL | Clean-text query required another execution | Scan every delivery for Unicode whitespace, zero-width characters, and BOM. |
| Wei converted before aggregation | Low-order exact digits were lost | Aggregate `DECIMAL(38,0)` wei first, convert once, and recompose to the integer source. |
| Invalid integer/text assembly | Output contained `112.000000.701...` | Cast quotient and remainder through explicit zero-scale integer text. |
| Adjacent duplicated keyword | `IS IS` appeared in split SQL | Scan `IS IS`, `NOT NOT`, `AND AND`, `OR OR`, and `IN IN`. |
| Full pipelines exceeded stage limits | Q09B, Q10A, Q10B, and two Q11A attempts failed | Split the pipeline, freeze manifests, and remove historical revalidation from downstream queries. |
| Q10B requested 20 copied rows | Dune Free copy returned only the first 10 | Every copied output must be <=10 rows; packed text is preferred. |
| Duplicate Q10B output alias | Copied `maximum_time_gap_seconds` surfaced the global maximum | Mark the column invalid, use `time_window_label`, and do not rerun a passed 11-minute query for a display-only defect. |
| Oversized numeric literal | `2687504361668181160550` was rejected | Use the typed literal `DECIMAL '2687504361668181160550'`. |
| Save instruction issued before result acceptance | Validation order was reversed | Run, keep page open, validate, then save/name/describe. |

Relevant preserved stage-limit execution IDs include:

- Q09B: `01KZ7W3RC9DX9BAVJMQGQRZR5G`;
- Q10A: `01KZ82BT4912D6TVTQE0FN0R5S`;
- full-upstream Q10B: `01KZ87HCHEGSWESCFM9E5HVVB4`;
- Q11A attempts: `01KZ98QH4VXFZS23H1ETW3N228` and
  `01KZ9A12NGVYNC0BDS6Q5EWEND`.

## 16. Evidence Boundary

Proven for the frozen source snapshot and queries:

- raw/curated event keys and exact raw amounts reconcile;
- transaction-token movement and unit conversions close internally;
- qualification, family counts, and class partitions satisfy their identities;
- funding and reverse-pair manifests reconstruct without row loss;
- the 40 selected cases reproduce their expected nonzero and economic groups;
- identical lightweight pipelines produce the reported two-window results.

Not proven:

- that one address equals one person or organization;
- that shared funding establishes common control;
- that reverse transfers are wash activity;
- that timing regularity establishes a bot;
- that fee>=movement establishes irrationality or malicious automation;
- classifier precision, recall, or causal meaning;
- equivalence on other chains, tokens, windows, or future table versions.

The final classification remains useful because every gate is explicit and
reviewable. Its defensible use is prioritization under stated constraints, not
automated accusation.
