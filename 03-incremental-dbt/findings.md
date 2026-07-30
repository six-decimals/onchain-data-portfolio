# Findings: Uniswap V3 SetFeeProtocol State Reconstruction

## 1. Question

The repaired baseline admitted 71,381 decoded SetFeeProtocol rows before joining protocol state to trades. The investigation asked:

1. Were these repeated changes to the same pools?
2. Did the model or a join duplicate the events?
3. Why did zero appear repeatedly in the state reconstruction?
4. What can the data prove about a batch-like pattern, and what remains unknown?

## 2. Evidence

The table names and fields were verified in Dune before the state model was written:

- [03-01A-pool-created-schema](https://dune.com/queries/8120957)
- [03-01B-fee-setting-schema](https://dune.com/queries/8122289)
- [03-01C-dex-trades-schema](https://dune.com/queries/8120988)
- [03-01D-prices-usd-schema](https://dune.com/queries/8121053)
- [03-01E-baseline-scan-inventory](https://dune.com/queries/8121270)
- [03-01F-protocol-state-snapshot](https://dune.com/queries/8122281)

The relevant decoded SetFeeProtocol fields are:

- `contract_address`
- `evt_block_number`
- `evt_index`
- `feeprotocol0old`
- `feeprotocol0new`
- `feeprotocol1old`
- `feeprotocol1new`

The contract behavior is defined in the official
[UniswapV3Pool.sol](https://github.com/Uniswap/v3-core/blob/main/contracts/UniswapV3Pool.sol):

- `initialize` writes `feeProtocol = 0`;
- `setFeeProtocol` accepts zero or a divisor from 4 through 10 for each token side;
- the function writes the packed state and emits SetFeeProtocol;
- the function does not require the new value to differ from the old value.

The contract explains how an unchanged or zero-valued call can emit an event. It does not explain why the authorized caller submitted a particular call.

## 3. Frozen structural result

Query 03-01F freezes the event structure through Ethereum block 25,622,409:

| Check | Result |
| --- | ---: |
| PoolCreated rows | 71,570 |
| Distinct created pools | 71,570 |
| SetFeeProtocol rows | 71,381 |
| Distinct SetFeeProtocol event keys | 71,381 |
| Duplicate event-key surplus rows | 0 |
| Conflicting pool-event keys | 0 |
| Distinct pools with a SetFeeProtocol event | 71,381 |
| Pools with exactly one event | 71,381 |
| Pools with multiple events | 0 |
| Pools with no event | 189 |
| Pools in settings but absent from PoolCreated | 0 |
| Pool-partition residual | 0 |
| `all_checks_pass` | `true` |

The partition closes exactly:

`71,381 one-event pools + 0 multiple-event pools + 189 zero-event pools = 71,570 created pools`

## 4. Ruling: the rows are not repeated pool edits

The 71,381 SetFeeProtocol rows correspond to 71,381 different pools. No pool has more than one event in the frozen snapshot.

This rules out two earlier interpretations:

- the table is not showing the same group of pools being changed repeatedly;
- the row count is not caused by event-key or pool-join duplication.

The observed shape is consistent with one-time, batch-like coverage across many pools. It does not, by itself, prove the governance or operational reason for that coverage.

## 4A. External governance context

The on-chain result above and the governance attribution below are different evidence layers.

The frozen on-chain shape proves only that 71,381 distinct pools each emitted one SetFeeProtocol event, while 189 created pools emitted none. It does not identify the policy decision or caller intent from row counts alone.

Externally verified public governance records provide the missing context:

- [UNIfication, Proposal #93](https://vote.uniswapfoundation.org/proposals/93) was executed on December 27, 2025. It activated protocol fees for selected Ethereum mainnet v3 pools. Its published fee schedule assigned one-quarter of LP fees to the protocol for the 0.01% and 0.05% tiers, and one-sixth for the 0.30% and 1% tiers.
- [Query 03-01F](https://dune.com/queries/8122281) freezes the first SetFeeProtocol event at `2025-12-27 20:36:11 UTC`, within the UNIfication execution window. This temporal match is consistent with the initial selected-pool rollout; the timestamp alone does not establish the governance cause.
- [Protocol Fee Expansion: Vote 1, Proposal #94](https://vote.uniswapfoundation.org/proposals/94), executed on March 6, 2026, replaced the curated mainnet adapter with `V3OpenFeeAdapter`. The public proposal states that the tier-based adapter extends the default protocol fee to all initialized v3 pools while retaining pool-specific overrides.

The governance explanation therefore comes from the public proposal records, not from the event count. The one-event-per-pool shape is independently observed on-chain and is consistent with the staged move from selected pools under UNIfication to all initialized pools under Proposal #94.

## 5. Why zero appears more than once

There are two different sources of zero, and they must not be combined.

### 5.1 Synthetic initial zero states

The model creates one `initial_settings` row for every pool at its creation order:

- `feeprotocol0 = 0`
- `feeprotocol1 = 0`

These rows are modeling anchors. They are not decoded SetFeeProtocol events and do not claim that an on-chain caller executed `setFeeProtocol(0, 0)` at pool creation.

The anchors are necessary because the Uniswap V3 pool initializes `feeProtocol` to zero. They give every trade a valid state before the first decoded setting event. They also provide the complete state history for the 189 pools with no SetFeeProtocol event.

### 5.2 Zero values inside decoded events

A decoded event can contain zero on either token side because zero is a valid argument to `setFeeProtocol`. The contract emits SetFeeProtocol after a valid call and has no condition requiring `old != new`.

Therefore, a zero-valued or unchanged call can produce a real event. However, query 03-01F proves only the event distribution by pool. It does not classify every event as `0→0`, `0→nonzero`, `nonzero→0`, or `nonzero→nonzero`.

The defensible conclusion is:

- repeated zero values across the dataset do not mean repeated settings on the same pool;
- synthetic initial zeros are not raw events;
- the contract permits a zero-valued no-op event;
- the caller's reason for making such a call is not established by the current queries.

Proving intent would require a separate transaction-level analysis of callers, transaction grouping, calldata, execution contracts, and any linked governance action. That work is outside this model and must not be inferred from the row shape.

## 6. State-interval construction

The model reconstructs protocol state in four steps:

1. Create one synthetic zero state at each pool's creation order.
2. Add decoded SetFeeProtocol events with their new token-side divisors.
3. Use `LEAD` within each pool to find the next state point.
4. Join each trade to the state interval containing its `(block_number, evt_index)`.

The lower interval boundary is exclusive:

- the trade block is greater than the setting block; or
- the blocks are equal and the trade event index is greater.

The upper interval boundary is also exclusive:

- there is no next setting; or
- the trade is strictly before the next setting in `block_number + evt_index` order.

This prevents two events in one block from being ordered only by timestamp.

## 7. Revenue consequence

The active divisor is selected by the sold-token side:

- token0 sold → `feeprotocol0`
- token1 sold → `feeprotocol1`

Protocol revenue is recognized only when the selected divisor is between 4 and 10:

`revenue_usd = fees_usd / fee_divisor`

A zero divisor means the protocol share is off for that token side, so protocol revenue is zero and the full fee remains supply-side.

## 8. Optimization consequence

The baseline admitted the full PoolCreated and SetFeeProtocol histories before joining them to the validation-window trades.

The optimized path first derives `candidate_pools` from the selected trades. In the same-snapshot parity query:

- logical PoolCreated rows fell from 71,616 to 16,092, or `77.5302%`;
- logical SetFeeProtocol rows fell from 71,425 to 16,092, or `77.4701%`.

These are logical rows admitted to the query. They are not scanned-byte or runtime reductions.

[Dune 8127558](https://dune.com/queries/8127558) found zero source-key differences, zero model-key differences, zero field mismatches, and zero row-level or aggregate USD differences between the baseline and optimized paths.

## 9. Evidence boundary

Proven:

- each frozen SetFeeProtocol event key is unique;
- each event belongs to a different pool;
- no frozen pool has multiple events;
- 189 pools have no event;
- the pool partition closes with zero residual;
- initial zero rows are synthetic model states;
- the contract initializes feeProtocol to zero and permits zero-valued calls;
- candidate-pool filtering preserves same-snapshot output parity.

Supported by externally verified public governance records:

- the governance explanation for the batch coverage is supported by UNIfication and Proposal #94; the on-chain row-count shape is consistent with that explanation but does not independently prove it.

Not proven:

- the value-transition distribution of all 71,381 events;
- that every zero-valued event is a no-op;
- that logical row-count reductions equal scanned-byte or runtime reductions.

## 10. Corrections produced by this investigation

`#31`

Runtime `CURRENT_TIMESTAMP` was treated as a reproducible source snapshot.
→ Repeated runs returned changing event counts.
→ Query 03-01F now freezes the structure through block 25,622,409.

`#32`

The SetFeeProtocol rows were interpreted as repeated settings on the same pools.
→ Distinct event-key and pool counts showed 71,381 events across 71,381 pools, with zero multiple-event pools.
→ The ruling was changed to one-time, batch-like coverage shape; governance intent remains unproven.

## 11. Final finding

The apparent repetition came from looking at a large event count without first partitioning it by pool. The frozen data contains one SetFeeProtocol event for each of 71,381 pools, not repeated edits to the same pools. The model's repeated initial zeros are synthetic state anchors, while zero inside a decoded event is contract-valid but does not reveal caller intent.
