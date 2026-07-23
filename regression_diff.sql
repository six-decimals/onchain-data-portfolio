-- Dune query: 8080408 — https://dune.com/queries/8080408/
/*
Purpose:
    Compare the expected repair set from Dune query 8072957
    with an independent reconstruction of the fixed-model policy.

Acceptance:
    1. The base contains 3,105,881 unique (tx_hash, evt_index) rows.
    2. The expected and actual changed sets both contain 142 rows.
    3. Both sets contain exactly the same keys, fixed values, and reason codes.
    4. The remaining 3,105,739 rows are unchanged at six decimal places.
    5. The original 12,314 unpriced rows remain unpriced.
*/

WITH params AS (
    SELECT
        TIMESTAMP '2026-06-14 00:00:00' AS start_time,
        TIMESTAMP '2026-07-14 00:00:00' AS end_time,
        0x80f8143fa056a063aaeecec3323aa3426262ddb2
            AS target_pool
),

base_trades AS (
    SELECT
        d.block_time,
        d.block_number,
        d.tx_hash,
        d.evt_index,
        d.project_contract_address AS pool,
        d.token_sold_address,
        d.token_sold_amount,
        d.amount_usd
    FROM dex.trades d
    CROSS JOIN params p
    WHERE d.blockchain = 'ethereum'
      AND d.project = 'uniswap'
      AND d.version = '3'
      AND d.block_time >= p.start_time
      AND d.block_time < p.end_time
),

base_stats AS (
    SELECT
        COUNT(*) AS base_trade_rows,

        COUNT(
            DISTINCT ROW(tx_hash, evt_index)
        ) AS base_distinct_tx_evt_keys,

        COUNT(*)
        -
        COUNT(
            DISTINCT ROW(tx_hash, evt_index)
        ) AS base_duplicate_key_surplus_rows,

        COUNT_IF(amount_usd IS NULL)
            AS base_unpriced_rows

    FROM base_trades
),

/*
The expected set is the already accepted affected_rows.sql result.
Its public Dune query is 8072957.
*/
expected_affected_raw AS (
    SELECT
        CAST(affected_row_number AS BIGINT)
            AS affected_row_number,
        CAST(block_number AS BIGINT)
            AS block_number,
        tx_hash,
        CAST(evt_index AS BIGINT)
            AS evt_index,
        CAST(
            fixed_fee_base_usd_6 AS DECIMAL(38, 6)
        ) AS fixed_fee_base_usd_6,
        reason_code
    FROM query_8072957
),

expected_stats AS (
    SELECT
        COUNT(*) AS expected_affected_rows,

        COUNT(
            DISTINCT ROW(tx_hash, evt_index)
        ) AS expected_distinct_tx_evt_keys,

        COUNT(*)
        -
        COUNT(
            DISTINCT ROW(tx_hash, evt_index)
        ) AS expected_duplicate_key_surplus_rows,

        COUNT_IF(
            reason_code =
                'FEE_BASE_INPUT_SIDE_REVALUATION'
        ) AS expected_ordinary_reason_rows,

        COUNT_IF(
            reason_code =
                'FEE_BASE_INPUT_SIDE_REVALUATION_GT_100PCT'
        ) AS expected_material_reason_rows,

        COUNT_IF(
            reason_code IS NULL
            OR reason_code NOT IN (
                'FEE_BASE_INPUT_SIDE_REVALUATION',
                'FEE_BASE_INPUT_SIDE_REVALUATION_GT_100PCT'
            )
        ) AS expected_unexpected_reason_rows,

        COUNT_IF(fixed_fee_base_usd_6 IS NULL)
            AS expected_fixed_null_rows,

        MIN(affected_row_number)
            AS min_affected_row_number,

        MAX(affected_row_number)
            AS max_affected_row_number,

        COUNT(DISTINCT affected_row_number)
            AS distinct_affected_row_numbers

    FROM expected_affected_raw
),

expected_affected AS (
    SELECT
        block_number,
        tx_hash,
        evt_index,
        fixed_fee_base_usd_6,
        reason_code
    FROM (
        SELECT
            e.*,

            ROW_NUMBER() OVER (
                PARTITION BY
                    tx_hash,
                    evt_index
                ORDER BY
                    block_number,
                    evt_index,
                    tx_hash
            ) AS key_row_number

        FROM expected_affected_raw e
    )
    WHERE key_row_number = 1
),

/*
Reconstruct the target-pool input-side valuation directly from
dex.trades and prices.usd.

The fee base is the sold-token amount multiplied by the sold-token
minute price.
*/
target_priced_rows AS (
    SELECT
        b.block_time,
        b.block_number,
        b.tx_hash,
        b.evt_index,

        CAST(
            ROUND(
                CAST(
                    b.amount_usd
                    AS DECIMAL(38, 18)
                ),
                6
            )
            AS DECIMAL(38, 6)
        ) AS legacy_fee_base_usd_6,

        CASE
            WHEN b.token_sold_amount IS NOT NULL
             AND price.price IS NOT NULL
            THEN
                CAST(
                    ROUND(
                        CAST(
                            CAST(
                                b.token_sold_amount
                                AS DECIMAL(30, 12)
                            )
                            *
                            CAST(
                                price.price
                                AS DECIMAL(24, 18)
                            )
                            AS DECIMAL(38, 18)
                        ),
                        6
                    )
                    AS DECIMAL(38, 6)
                )
            ELSE NULL
        END AS fixed_fee_base_usd_6

    FROM base_trades b
    CROSS JOIN params p

    LEFT JOIN prices.usd price
        ON price.blockchain = 'ethereum'
       AND price.contract_address =
            b.token_sold_address
       AND price.minute =
            DATE_TRUNC('minute', b.block_time)

    WHERE b.pool = p.target_pool
),

target_stats AS (
    SELECT
        COUNT(*) AS target_price_join_rows,

        COUNT(
            DISTINCT ROW(tx_hash, evt_index)
        ) AS target_distinct_tx_evt_keys,

        COUNT(*)
        -
        COUNT(
            DISTINCT ROW(tx_hash, evt_index)
        ) AS target_duplicate_key_surplus_rows,

        COUNT_IF(fixed_fee_base_usd_6 IS NOT NULL)
            AS target_input_priced_rows

    FROM target_priced_rows
),

/*
The actual policy changes a row only when the legacy and input-side
fee bases differ at the required six-decimal reporting precision.
*/
actual_changed_raw AS (
    SELECT
        block_number,
        tx_hash,
        evt_index,
        legacy_fee_base_usd_6,
        fixed_fee_base_usd_6,

        CASE
            WHEN fixed_fee_base_usd_6 <>
                    CAST(0 AS DECIMAL(38, 6))
             AND ABS(
                    legacy_fee_base_usd_6
                    -
                    fixed_fee_base_usd_6
                 )
                 >
                 ABS(fixed_fee_base_usd_6)
            THEN
                'FEE_BASE_INPUT_SIDE_REVALUATION_GT_100PCT'
            ELSE
                'FEE_BASE_INPUT_SIDE_REVALUATION'
        END AS reason_code

    FROM target_priced_rows
    WHERE legacy_fee_base_usd_6 IS NOT NULL
      AND fixed_fee_base_usd_6 IS NOT NULL
      AND legacy_fee_base_usd_6
            <> fixed_fee_base_usd_6
),

actual_stats AS (
    SELECT
        COUNT(*) AS actual_changed_rows,

        COUNT(
            DISTINCT ROW(tx_hash, evt_index)
        ) AS actual_distinct_tx_evt_keys,

        COUNT(*)
        -
        COUNT(
            DISTINCT ROW(tx_hash, evt_index)
        ) AS actual_duplicate_key_surplus_rows,

        COUNT_IF(
            reason_code =
                'FEE_BASE_INPUT_SIDE_REVALUATION'
        ) AS actual_ordinary_reason_rows,

        COUNT_IF(
            reason_code =
                'FEE_BASE_INPUT_SIDE_REVALUATION_GT_100PCT'
        ) AS actual_material_reason_rows,

        COUNT_IF(
            reason_code IS NULL
            OR reason_code NOT IN (
                'FEE_BASE_INPUT_SIDE_REVALUATION',
                'FEE_BASE_INPUT_SIDE_REVALUATION_GT_100PCT'
            )
        ) AS actual_unexpected_reason_rows,

        COUNT_IF(fixed_fee_base_usd_6 IS NULL)
            AS actual_fixed_null_rows

    FROM actual_changed_raw
),

actual_changed AS (
    SELECT
        block_number,
        tx_hash,
        evt_index,
        legacy_fee_base_usd_6,
        fixed_fee_base_usd_6,
        reason_code
    FROM (
        SELECT
            a.*,

            ROW_NUMBER() OVER (
                PARTITION BY
                    tx_hash,
                    evt_index
                ORDER BY
                    block_number,
                    evt_index,
                    tx_hash
            ) AS key_row_number

        FROM actual_changed_raw a
    )
    WHERE key_row_number = 1
),

/*
A full outer join exposes both failure directions:
expected-but-missing and actual-but-unexpected.
*/
changed_set_diff AS (
    SELECT
        e.tx_hash AS expected_tx_hash,
        e.evt_index AS expected_evt_index,
        e.fixed_fee_base_usd_6
            AS expected_fixed_fee_base_usd_6,
        e.reason_code AS expected_reason_code,

        a.tx_hash AS actual_tx_hash,
        a.evt_index AS actual_evt_index,
        a.fixed_fee_base_usd_6
            AS actual_fixed_fee_base_usd_6,
        a.reason_code AS actual_reason_code

    FROM expected_affected e

    FULL OUTER JOIN actual_changed a
        ON e.tx_hash = a.tx_hash
       AND e.evt_index = a.evt_index
),

changed_set_diff_stats AS (
    SELECT
        COUNT_IF(
            expected_tx_hash IS NOT NULL
            AND actual_tx_hash IS NOT NULL
        ) AS matched_changed_rows,

        COUNT_IF(
            expected_tx_hash IS NOT NULL
            AND actual_tx_hash IS NULL
        ) AS missing_expected_rows,

        COUNT_IF(
            expected_tx_hash IS NULL
            AND actual_tx_hash IS NOT NULL
        ) AS unexpected_actual_changed_rows,

        COUNT_IF(
            expected_tx_hash IS NOT NULL
            AND actual_tx_hash IS NOT NULL
            AND expected_fixed_fee_base_usd_6
                IS DISTINCT FROM
                actual_fixed_fee_base_usd_6
        ) AS fixed_value_mismatch_rows,

        COUNT_IF(
            expected_tx_hash IS NOT NULL
            AND actual_tx_hash IS NOT NULL
            AND expected_reason_code
                IS DISTINCT FROM
                actual_reason_code
        ) AS reason_code_mismatch_rows

    FROM changed_set_diff
),

base_values AS (
    SELECT
        b.tx_hash,
        b.evt_index,

        CAST(
            ROUND(
                CAST(
                    b.amount_usd
                    AS DECIMAL(38, 18)
                ),
                6
            )
            AS DECIMAL(38, 6)
        ) AS before_fee_base_usd_6

    FROM base_trades b
),

model_row_diff AS (
    SELECT
        b.tx_hash,
        b.evt_index,
        b.before_fee_base_usd_6,

        CASE
            WHEN a.tx_hash IS NOT NULL
                THEN a.fixed_fee_base_usd_6
            ELSE b.before_fee_base_usd_6
        END AS after_fee_base_usd_6,

        e.tx_hash IS NOT NULL
            AS is_expected_affected

    FROM base_values b

    LEFT JOIN actual_changed a
        ON b.tx_hash = a.tx_hash
       AND b.evt_index = a.evt_index

    LEFT JOIN expected_affected e
        ON b.tx_hash = e.tx_hash
       AND b.evt_index = e.evt_index
),

model_row_diff_stats AS (
    SELECT
        COUNT(*) AS model_rows,

        COUNT_IF(
            before_fee_base_usd_6
                IS DISTINCT FROM
                after_fee_base_usd_6
        ) AS model_changed_rows,

        COUNT_IF(
            is_expected_affected
            AND before_fee_base_usd_6
                IS DISTINCT FROM
                after_fee_base_usd_6
        ) AS changed_expected_rows,

        COUNT_IF(
            is_expected_affected
            AND before_fee_base_usd_6
                IS NOT DISTINCT FROM
                after_fee_base_usd_6
        ) AS expected_rows_not_changed,

        COUNT_IF(
            NOT is_expected_affected
            AND before_fee_base_usd_6
                IS DISTINCT FROM
                after_fee_base_usd_6
        ) AS changed_unaffected_rows,

        COUNT_IF(
            NOT is_expected_affected
            AND before_fee_base_usd_6
                IS NOT DISTINCT FROM
                after_fee_base_usd_6
        ) AS unchanged_unaffected_rows,

        COUNT_IF(before_fee_base_usd_6 IS NULL)
            AS before_null_rows,

        COUNT_IF(after_fee_base_usd_6 IS NULL)
            AS after_null_rows,

        COUNT_IF(
            before_fee_base_usd_6 IS NOT NULL
            AND after_fee_base_usd_6 IS NULL
        ) AS newly_null_rows,

        COUNT_IF(
            before_fee_base_usd_6 IS NULL
            AND after_fee_base_usd_6 IS NOT NULL
        ) AS unexpectedly_filled_null_rows

    FROM model_row_diff
)

SELECT
    bs.base_trade_rows,
    bs.base_distinct_tx_evt_keys,
    bs.base_duplicate_key_surplus_rows,
    bs.base_unpriced_rows,

    ts.target_price_join_rows,
    ts.target_distinct_tx_evt_keys,
    ts.target_duplicate_key_surplus_rows,
    ts.target_input_priced_rows,

    es.expected_affected_rows,
    es.expected_distinct_tx_evt_keys,
    es.expected_duplicate_key_surplus_rows,
    es.expected_ordinary_reason_rows,
    es.expected_material_reason_rows,
    es.expected_unexpected_reason_rows,
    es.expected_fixed_null_rows,
    es.min_affected_row_number,
    es.max_affected_row_number,
    es.distinct_affected_row_numbers,

    acs.actual_changed_rows,
    acs.actual_distinct_tx_evt_keys,
    acs.actual_duplicate_key_surplus_rows,
    acs.actual_ordinary_reason_rows,
    acs.actual_material_reason_rows,
    acs.actual_unexpected_reason_rows,
    acs.actual_fixed_null_rows,

    ds.matched_changed_rows,
    ds.missing_expected_rows,
    ds.unexpected_actual_changed_rows,
    ds.fixed_value_mismatch_rows,
    ds.reason_code_mismatch_rows,

    mrs.model_rows,
    mrs.model_changed_rows,
    mrs.changed_expected_rows,
    mrs.expected_rows_not_changed,
    mrs.changed_unaffected_rows,
    mrs.unchanged_unaffected_rows,
    mrs.before_null_rows,
    mrs.after_null_rows,
    mrs.newly_null_rows,
    mrs.unexpectedly_filled_null_rows,

    (
        bs.base_trade_rows = 3105881
        AND bs.base_distinct_tx_evt_keys = 3105881
        AND bs.base_duplicate_key_surplus_rows = 0
        AND bs.base_unpriced_rows = 12314

        AND ts.target_price_join_rows = 256
        AND ts.target_distinct_tx_evt_keys = 256
        AND ts.target_duplicate_key_surplus_rows = 0
        AND ts.target_input_priced_rows = 256

        AND es.expected_affected_rows = 142
        AND es.expected_distinct_tx_evt_keys = 142
        AND es.expected_duplicate_key_surplus_rows = 0
        AND es.expected_ordinary_reason_rows = 140
        AND es.expected_material_reason_rows = 2
        AND es.expected_unexpected_reason_rows = 0
        AND es.expected_fixed_null_rows = 0
        AND es.min_affected_row_number = 1
        AND es.max_affected_row_number = 142
        AND es.distinct_affected_row_numbers = 142

        AND acs.actual_changed_rows = 142
        AND acs.actual_distinct_tx_evt_keys = 142
        AND acs.actual_duplicate_key_surplus_rows = 0
        AND acs.actual_ordinary_reason_rows = 140
        AND acs.actual_material_reason_rows = 2
        AND acs.actual_unexpected_reason_rows = 0
        AND acs.actual_fixed_null_rows = 0

        AND ds.matched_changed_rows = 142
        AND ds.missing_expected_rows = 0
        AND ds.unexpected_actual_changed_rows = 0
        AND ds.fixed_value_mismatch_rows = 0
        AND ds.reason_code_mismatch_rows = 0

        AND mrs.model_rows = 3105881
        AND mrs.model_changed_rows = 142
        AND mrs.changed_expected_rows = 142
        AND mrs.expected_rows_not_changed = 0
        AND mrs.changed_unaffected_rows = 0
        AND mrs.unchanged_unaffected_rows = 3105739
        AND mrs.before_null_rows = 12314
        AND mrs.after_null_rows = 12314
        AND mrs.newly_null_rows = 0
        AND mrs.unexpectedly_filled_null_rows = 0
    ) AS all_checks_pass

FROM base_stats bs
CROSS JOIN target_stats ts
CROSS JOIN expected_stats es
CROSS JOIN actual_stats acs
CROSS JOIN changed_set_diff_stats ds
CROSS JOIN model_row_diff_stats mrs;
