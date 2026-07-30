Optimization Notes: Incremental Uniswap V3 Fees and Revenue

1. Objective and validation scope

This project converts a full-refresh Uniswap V3 fee and protocol-revenue query into a trade-level incremental dbt model. The model keeps the audit key (tx_hash, evt_index) and materializes complete UTC-date partitions.

The validation scope is Ethereum Uniswap V3 over UTC [2026-06-14 00:00:00, 2026-07-14 00:00:00). The model calculates:

fee_base_usd

fee_tier

fee_divisor

fees_usd

revenue_usd

supply_side_fees_usd

repair status and reason_code

Formal USD calculations use DECIMAL(38,18). Published totals use six decimal places. A row with no priced fee base contributes zero to USD totals and remains visible through the unpriced-row count.

2. Decisions

Decision

Ruling

Accepted cost

B8=2

Recompute the latest three complete UTC dates. Use a full refresh after a model-definition change and a date-bounded backfill for an older known issue.

An unknown source update arriving more than three dates late is not corrected automatically.

B9=3

Reuse the common DECIMAL fee and revenue arithmetic. Keep Uniswap V3 token-side selection and protocol-state intervals protocol-specific.

The shared macros do not hide protocol-specific state logic.

B3-02=1

Use same-snapshot row parity as the acceptance anchor.

Historical totals remain records of their original source snapshot, not permanent regression constants.

B3-03=2

Delete and reinsert complete block_date partitions. Keep (tx_hash, evt_index) as the row audit key.

Each incremental run rewrites overlapping dates instead of appending only unseen rows.

B3-04=2

Start with three benchmark runs per model. Add two runs when max > 2 × min, then use the five-run median.

The test spends two extra runs when the first three runs are volatile.

B10=2

Keep the finest trade-level output and accept the observed slower Dune query.

The project does not claim a wall-clock speed improvement.

3. Why the historical totals are not regression constants

The repaired baseline query originally observed 3,105,881 trades and 12,314 unpriced fee-base rows. It produced:

fees: 7,437,622.456387 USD

revenue: 1,417,343.270700 USD

supply-side fees: 6,020,279.185686 USD

Source: Dune query 8075341.

The same fixed block-time window later contained 3,105,887 trades and 12,224 unpriced fee-base rows. It produced:

fees: 7,437,623.041819 USD

revenue: 1,417,343.393348 USD

supply-side fees: 6,020,279.648471 USD

Sources: incremental validation query 8127229 and same-snapshot parity query 8127558.

The window did not change, but the source content did. The trade count increased by six and the unpriced count decreased by 90. A fixed event-time filter therefore did not create an immutable data snapshot. B3-02=1 replaced historical-total matching with baseline-versus-optimized comparison inside one query execution.

4. Changes to the computation path

The baseline path reads every trade in the requested history and admits the full PoolCreated and SetFeeProtocol histories before joining protocol state to trades.

The incremental path changes four parts of that work:

It reads only the UTC-date partitions selected for the current run.

It derives candidate_pools from those trades before reading pool metadata and protocol-setting events.

It materializes trade-level fee, revenue, repair, and state fields for downstream use.

It moves the common DECIMAL arithmetic into macros while leaving the Uniswap V3 state override in the protocol model.

In the full-window parity query, candidate-pool filtering reduced the logical PoolCreated input from 71,616 rows to 16,092 rows, or 77.5302%. It reduced the logical SetFeeProtocol input from 71,425 rows to 16,092 rows, or 77.4701%.

These are row counts admitted to the query logic. They are not Dune scanned-byte measurements and do not prove an equal reduction in execution cost.

5. Correctness checks

The delete-and-insert simulation recomputed 284,882 rows for three dates and retained 2,821,005 older rows. Their union contained 3,105,887 rows, equal to the full-refresh result.

The incremental validation query returned:

full-only keys: 0

simulated-only keys: 0

field-mismatch keys: 0

duplicate-key surplus rows: 0

fee row-difference sum: 0.000000 USD

revenue row-difference sum: 0.000000 USD

supply-side row-difference sum: 0.000000 USD

full accounting residual: 0.000000 USD

simulated accounting residual: 0.000000 USD

same_snapshot_incremental_parity_pass = true

The baseline-versus-optimized parity query independently compared both paths within one Dune statement. It found zero source-key differences, zero model-key differences, zero field mismatches, zero row-level USD differences, and zero aggregate USD differences. Both paths produced 142 repaired rows: 140 ordinary repairs and two material repairs.

These checks prove equality for the observed source snapshot and model scope. They do not prove that a future source revision, schema change, or protocol-rule change will preserve parity without a new test.

6. Benchmark method

Both benchmark queries ran on Dune Medium. Each query contained only its model's daily computation path and excluded parity-check work.

The test began with three runs per model. Both models met the volatility trigger, max > 2 × min, so each model received two additional runs.

Model

Dune query

Selected trade rows

Accepted times

Min

Median

Max

Full window

8145809

3,105,887

7s, 8s, 21s, 5s, 10s

5s

8s

21s

Three dates

8145953

284,882

11s, 13s, 6s, 7s, 10s

6s

10s

13s

Every accepted run reproduced its model fingerprint. The full-window fingerprint included 142 repaired rows and an accounting residual of 0.000000 USD. The three-date fingerprint included seven repaired rows and an accounting residual of 0.000000 USD.

The first full-window run took seven seconds at 2026-07-29 06:08:04.239 UTC. Its Dune page was deleted, so it has only a conversation record. benchmark.csv discloses the missing page archive instead of assigning that run a query URL.

The measured speedup was:

(8 - 10) / 8 × 100 = -25.0000%

The three-date query was 25.0000% slower by the five-run median. The required 50.0000% improvement was not met.

7. What the benchmark does and does not show

The three-date query selected 2,821,005 fewer trade rows than the full-window query, a reduction of 90.8277%.

The benchmark proves:

fewer trades met the incremental date filter;

fewer pool and setting rows entered the optimized lookup logic;

row-level and aggregate parity held on the tested snapshot;

the observed Dune Medium median moved from eight seconds to ten seconds.

The benchmark does not prove:

a 90.8277% reduction in scanned bytes;

lower warehouse write cost;

faster execution of a materialized dbt run;

whether fixed query overhead, shared-engine variation, joins, or cache behavior caused the wall-clock result.

No query profile or scanned-byte evidence is available to separate those possible causes. They remain hypotheses.

8. B10 trade-off

B10=2 keeps trade-level data instead of replacing it with a pre-aggregated output. This preserves the evidence needed to inspect one swap, reproduce a total, trace a repair reason, and test protocol-state assignment.

The cost is explicit: the tested Dune equivalent did not run faster. This project demonstrates an incremental model with exact same-snapshot parity and bounded recomputation. It does not demonstrate a Dune wall-clock performance win.

A later aggregate model could serve repeated daily or chain-level queries without removing the detailed table. That would be a separate model, benchmark, and acceptance decision. It is not part of the current performance claim.

9. Operational limits

Daily runs recompute the latest three complete UTC dates.

A known older issue requires a date-bounded backfill.

A model-definition change requires a full refresh.

A source update arriving outside the overlap can leave an older partition stale until a backfill or full refresh occurs.

A duplicate (tx_hash, evt_index) key, a source-schema change, or a changed protocol-fee rule invalidates the current acceptance evidence.

The special input-side fee-base repair is bounded to its identified pool and date range. It is not a general anomaly detector.

Rows without a priced fee base remain counted but do not add to USD fees, revenue, or supply-side fees.

The production check must therefore keep key uniqueness, unpriced-row counts, repaired-row counts, row-level parity, and the accounting residual visible.
