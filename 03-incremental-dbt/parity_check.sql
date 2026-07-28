-- Dune query: PENDING — save after validation as 03-05-baseline-incremental-parity
-- File: parity_check.sql
-- Purpose:
--   Compare the repaired baseline path with the optimized full-refresh path
--   inside one Dune statement and therefore one source snapshot.
-- Scope:
--   Ethereum Uniswap V3, UTC [2026-06-14, 2026-07-14).
-- Decisions:
--   B3-02=1: same-snapshot row parity is the acceptance anchor.
--   B9=3: the optimized path uses the macro-equivalent DECIMAL formulas.
-- Frozen expected result:
--   Baseline and optimized source/model null-key rows = 0.
--   Baseline and optimized source duplicate-key surplus rows = 0.
--   Source baseline-only, optimized-only, and key-count mismatch keys = 0.
--   Baseline and optimized model duplicate-key surplus rows = 0.
--   Model baseline-only, optimized-only, and field-mismatch keys = 0.
--   Baseline and optimized repaired-null rows = 0.
--   Fees, revenue, and supply-side row-difference sums = 0.000000.
--   Fees, revenue, and supply-side aggregate differences = 0.000000.
--   Baseline and optimized accounting residuals = 0.000000.
--   same_snapshot_baseline_incremental_parity_pass = true.
-- Row counts and USD totals are observations, not acceptance anchors.

WITH params AS (
    SELECT
        CURRENT_TIMESTAMP AS query_run_utc,
        TIMESTAMP '2026-06-14 00:00:00'
            AS start_time,
        TIMESTAMP '2026-07-14 00:00:00'
            AS end_time,
        DATE '2026-06-14' AS start_date,
        DATE '2026-07-14' AS end_date
),

baseline_source_trades AS (
    SELECT
        d.block_date,
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

optimized_source_trades AS (
    SELECT
        d.block_date,
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
      AND d.block_date >= p.start_date
      AND d.block_date < p.end_date
),

baseline_source_key_counts AS (
    SELECT
        tx_hash,
        evt_index,
        COUNT(*) AS row_count
    FROM baseline_source_trades
    GROUP BY
        tx_hash,
        evt_index
),

optimized_source_key_counts AS (
    SELECT
        tx_hash,
        evt_index,
        COUNT(*) AS row_count
    FROM optimized_source_trades
    GROUP BY
        tx_hash,
        evt_index
),

baseline_source_stats AS (
    SELECT
        COUNT(*) AS baseline_source_rows,
        COUNT_IF(
            tx_hash IS NULL
            OR evt_index IS NULL
        ) AS baseline_source_null_key_rows,
        COUNT_IF(amount_usd IS NULL)
            AS baseline_source_unpriced_rows
    FROM baseline_source_trades
),

optimized_source_stats AS (
    SELECT
        COUNT(*) AS optimized_source_rows,
        COUNT_IF(
            tx_hash IS NULL
            OR evt_index IS NULL
        ) AS optimized_source_null_key_rows,
        COUNT_IF(amount_usd IS NULL)
            AS optimized_source_unpriced_rows
    FROM optimized_source_trades
),

baseline_source_key_stats AS (
    SELECT
        COUNT(*) AS baseline_source_distinct_keys,
        COALESCE(
            SUM(row_count - 1),
            CAST(0 AS BIGINT)
        ) AS baseline_source_duplicate_key_surplus_rows
    FROM baseline_source_key_counts
),

optimized_source_key_stats AS (
    SELECT
        COUNT(*) AS optimized_source_distinct_keys,
        COALESCE(
            SUM(row_count - 1),
            CAST(0 AS BIGINT)
        ) AS optimized_source_duplicate_key_surplus_rows
    FROM optimized_source_key_counts
),

source_key_reconciliation AS (
    SELECT
        COUNT_IF(
            b.tx_hash IS NOT NULL
            AND o.tx_hash IS NULL
        ) AS source_baseline_only_keys,

        COUNT_IF(
            b.tx_hash IS NULL
            AND o.tx_hash IS NOT NULL
        ) AS source_optimized_only_keys,

        COUNT_IF(
            b.tx_hash IS NOT NULL
            AND o.tx_hash IS NOT NULL
            AND b.row_count <> o.row_count
        ) AS source_row_count_mismatch_keys

    FROM baseline_source_key_counts b
    FULL OUTER JOIN optimized_source_key_counts o
        ON b.tx_hash = o.tx_hash
        AND b.evt_index = o.evt_index
),

optimized_candidate_pools AS (
    SELECT DISTINCT
        pool
    FROM optimized_source_trades
),

baseline_pools AS (
    SELECT
        'BASELINE' AS model_path,
        p.pool,
        p.token0,
        p.token1,
        p.fee AS fee_tier,
        p.evt_block_number AS created_block_number,
        p.evt_index AS created_evt_index
    FROM uniswap_v3_ethereum.uniswapv3factory_evt_poolcreated p
),

optimized_pools AS (
    SELECT
        'OPTIMIZED_FULL_REFRESH' AS model_path,
        p.pool,
        p.token0,
        p.token1,
        p.fee AS fee_tier,
        p.evt_block_number AS created_block_number,
        p.evt_index AS created_evt_index
    FROM uniswap_v3_ethereum.uniswapv3factory_evt_poolcreated p
    INNER JOIN optimized_candidate_pools c
        ON p.pool = c.pool
),

model_pools AS (
    SELECT *
    FROM baseline_pools

    UNION ALL

    SELECT *
    FROM optimized_pools
),

pool_scan_stats AS (
    SELECT
        COUNT_IF(model_path = 'BASELINE')
            AS baseline_pool_rows,
        COUNT_IF(model_path = 'OPTIMIZED_FULL_REFRESH')
            AS optimized_pool_rows
    FROM model_pools
),

initial_settings AS (
    SELECT
        model_path,
        pool,
        token0,
        token1,
        fee_tier,
        created_block_number AS setting_block_number,
        created_evt_index AS setting_evt_index,
        CAST(0 AS INTEGER) AS feeprotocol0,
        CAST(0 AS INTEGER) AS feeprotocol1
    FROM model_pools
),

setting_events AS (
    SELECT
        p.model_path,
        p.pool,
        p.token0,
        p.token1,
        p.fee_tier,
        s.evt_block_number AS setting_block_number,
        s.evt_index AS setting_evt_index,
        CAST(s.feeprotocol0new AS INTEGER) AS feeprotocol0,
        CAST(s.feeprotocol1new AS INTEGER) AS feeprotocol1
    FROM uniswap_v3_ethereum.uniswapv3pool_evt_setfeeprotocol s
    INNER JOIN model_pools p
        ON s.contract_address = p.pool
),

setting_scan_stats AS (
    SELECT
        COUNT_IF(model_path = 'BASELINE')
            AS baseline_setting_event_rows,
        COUNT_IF(model_path = 'OPTIMIZED_FULL_REFRESH')
            AS optimized_setting_event_rows
    FROM setting_events
),

all_setting_points AS (
    SELECT *
    FROM initial_settings

    UNION ALL

    SELECT *
    FROM setting_events
),

fee_intervals AS (
    SELECT
        model_path,
        pool,
        token0,
        token1,
        fee_tier,
        setting_block_number,
        setting_evt_index,
        feeprotocol0,
        feeprotocol1,

        LEAD(setting_block_number) OVER (
            PARTITION BY
                model_path,
                pool
            ORDER BY
                setting_block_number,
                setting_evt_index
        ) AS next_setting_block_number,

        LEAD(setting_evt_index) OVER (
            PARTITION BY
                model_path,
                pool
            ORDER BY
                setting_block_number,
                setting_evt_index
        ) AS next_setting_evt_index

    FROM all_setting_points
),

path_trades AS (
    SELECT
        'BASELINE' AS model_path,
        block_date,
        block_time,
        block_number,
        tx_hash,
        evt_index,
        pool,
        token_sold_address,
        token_sold_amount,
        amount_usd
    FROM baseline_source_trades

    UNION ALL

    SELECT
        'OPTIMIZED_FULL_REFRESH' AS model_path,
        block_date,
        block_time,
        block_number,
        tx_hash,
        evt_index,
        pool,
        token_sold_address,
        token_sold_amount,
        amount_usd
    FROM optimized_source_trades
),

target_input_priced AS (
    SELECT
        t.model_path,
        t.block_time,
        t.block_number,
        t.tx_hash,
        t.evt_index,
        t.pool,
        t.token_sold_address,
        t.token_sold_amount,

        CAST(t.amount_usd AS DECIMAL(38, 18))
            AS legacy_fee_base_usd,

        price.price AS input_token_price_usd,

        CASE
            WHEN t.token_sold_amount IS NOT NULL
             AND price.price IS NOT NULL
                THEN CAST(
                    CAST(t.token_sold_amount AS DECIMAL(30, 12))
                    *
                    CAST(price.price AS DECIMAL(24, 18))
                    AS DECIMAL(38, 18)
                )
            ELSE NULL
        END AS fixed_fee_base_usd

    FROM path_trades t
    LEFT JOIN prices.usd price
        ON price.blockchain = 'ethereum'
        AND price.contract_address = t.token_sold_address
        AND price.minute = DATE_TRUNC('minute', t.block_time)

    WHERE t.pool =
        0x80f8143fa056a063aaeecec3323aa3426262ddb2
      AND t.block_time >=
        TIMESTAMP '2026-06-14 00:00:00'
      AND t.block_time <
        TIMESTAMP '2026-07-14 00:00:00'
),

target_compared AS (
    SELECT
        *,

        CAST(
            ROUND(legacy_fee_base_usd, 6)
            AS DECIMAL(38, 6)
        ) AS legacy_fee_base_usd_6,

        CAST(
            ROUND(fixed_fee_base_usd, 6)
            AS DECIMAL(38, 6)
        ) AS fixed_fee_base_usd_6,

        CASE
            -- Diagnostic-only DOUBLE path for reason-code classification.
            WHEN fixed_fee_base_usd > CAST(0 AS DECIMAL(38, 18))
             AND legacy_fee_base_usd IS NOT NULL
                THEN ABS(
                    CAST(legacy_fee_base_usd AS DOUBLE)
                    -
                    CAST(fixed_fee_base_usd AS DOUBLE)
                )
                / CAST(fixed_fee_base_usd AS DOUBLE)
                * 100.0
            ELSE NULL
        END AS absolute_difference_pct

    FROM target_input_priced
),

affected_fee_bases AS (
    SELECT
        model_path,
        block_number,
        tx_hash,
        evt_index,
        pool,
        fixed_fee_base_usd,

        CASE
            WHEN absolute_difference_pct > 100.0
                THEN 'FEE_BASE_INPUT_SIDE_REVALUATION_GT_100PCT'
            ELSE 'FEE_BASE_INPUT_SIDE_REVALUATION'
        END AS reason_code

    FROM target_compared
    WHERE fixed_fee_base_usd IS NOT NULL
      AND legacy_fee_base_usd_6
          IS DISTINCT FROM fixed_fee_base_usd_6
),

joined_trades AS (
    SELECT
        t.model_path,
        t.block_date,
        t.block_time,
        t.block_number,
        t.tx_hash,
        t.evt_index,
        t.pool,
        t.token_sold_address,

        CAST(t.amount_usd AS DECIMAL(38, 18))
            AS source_amount_usd,

        COALESCE(
            a.fixed_fee_base_usd,
            CAST(t.amount_usd AS DECIMAL(38, 18))
        ) AS fee_base_usd,

        a.tx_hash IS NOT NULL
            AS is_repaired,

        a.reason_code,
        f.fee_tier,
        f.token0,
        f.token1,
        f.feeprotocol0,
        f.feeprotocol1

    FROM path_trades t
    INNER JOIN fee_intervals f
        ON t.model_path = f.model_path
        AND t.pool = f.pool

        AND (
            t.block_number > f.setting_block_number
            OR (
                t.block_number = f.setting_block_number
                AND t.evt_index > f.setting_evt_index
            )
        )

        AND (
            f.next_setting_block_number IS NULL
            OR t.block_number < f.next_setting_block_number
            OR (
                t.block_number = f.next_setting_block_number
                AND t.evt_index < f.next_setting_evt_index
            )
        )

    LEFT JOIN affected_fee_bases a
        ON t.model_path = a.model_path
        AND t.block_number = a.block_number
        AND t.tx_hash = a.tx_hash
        AND t.evt_index = a.evt_index
        AND t.pool = a.pool
),

baseline_prepared AS (
    SELECT
        *,

        CASE
            WHEN token_sold_address = token0
                THEN feeprotocol0
            WHEN token_sold_address = token1
                THEN feeprotocol1
            ELSE NULL
        END AS fee_divisor

    FROM joined_trades
    WHERE model_path = 'BASELINE'
),

optimized_prepared AS (
    SELECT
        *,

        CASE
            WHEN token_sold_address = token0
                THEN CAST(feeprotocol0 AS INTEGER)
            WHEN token_sold_address = token1
                THEN CAST(feeprotocol1 AS INTEGER)
            ELSE NULL
        END AS fee_divisor

    FROM joined_trades
    WHERE model_path = 'OPTIMIZED_FULL_REFRESH'
),

baseline_fee_metrics AS (
    SELECT
        *,

        CASE
            WHEN fee_base_usd IS NOT NULL
                THEN CAST(
                    (
                        fee_base_usd
                        /
                        CAST(1000000 AS DECIMAL(7, 0))
                    )
                    *
                    CAST(fee_tier AS DECIMAL(6, 0))
                    AS DECIMAL(38, 18)
                )
            ELSE CAST(0 AS DECIMAL(38, 18))
        END AS fees_usd

    FROM baseline_prepared
),

optimized_fee_metrics AS (
    SELECT
        *,

        CASE
            WHEN fee_base_usd IS NOT NULL
                THEN CAST(
                    (
                        CAST(fee_base_usd AS DECIMAL(38, 18))
                        /
                        CAST(1000000 AS DECIMAL(7, 0))
                    )
                    *
                    CAST(fee_tier AS DECIMAL(6, 0))
                    AS DECIMAL(38, 18)
                )
            ELSE CAST(0 AS DECIMAL(38, 18))
        END AS fees_usd

    FROM optimized_prepared
),

baseline_revenue_metrics AS (
    SELECT
        *,

        CASE
            WHEN fee_divisor BETWEEN 4 AND 10
                THEN CAST(
                    fees_usd
                    /
                    CAST(fee_divisor AS DECIMAL(2, 0))
                    AS DECIMAL(38, 18)
                )
            ELSE CAST(0 AS DECIMAL(38, 18))
        END AS revenue_usd

    FROM baseline_fee_metrics
),

optimized_revenue_metrics AS (
    SELECT
        *,

        CASE
            WHEN fee_divisor BETWEEN 4 AND 10
                THEN CAST(
                    CAST(fees_usd AS DECIMAL(38, 18))
                    /
                    CAST(fee_divisor AS DECIMAL(2, 0))
                    AS DECIMAL(38, 18)
                )
            ELSE CAST(0 AS DECIMAL(38, 18))
        END AS revenue_usd

    FROM optimized_fee_metrics
),

baseline_model_rows AS (
    SELECT
        'ethereum' AS blockchain,
        'uniswap' AS project,
        '3' AS version,
        block_date,
        block_time,
        block_number,
        tx_hash,
        evt_index,
        pool,
        token_sold_address,
        source_amount_usd,
        fee_base_usd,
        is_repaired,
        reason_code,
        fee_tier,
        fee_divisor,
        fees_usd,
        revenue_usd,

        CAST(
            fees_usd - revenue_usd
            AS DECIMAL(38, 18)
        ) AS supply_side_fees_usd

    FROM baseline_revenue_metrics
),

optimized_model_rows AS (
    SELECT
        'ethereum' AS blockchain,
        'uniswap' AS project,
        '3' AS version,
        block_date,
        block_time,
        block_number,
        tx_hash,
        evt_index,
        pool,
        token_sold_address,
        source_amount_usd,
        fee_base_usd,
        is_repaired,
        reason_code,
        fee_tier,
        fee_divisor,
        fees_usd,
        revenue_usd,

        CAST(
            fees_usd - revenue_usd
            AS DECIMAL(38, 18)
        ) AS supply_side_fees_usd

    FROM optimized_revenue_metrics
),

baseline_model_key_counts AS (
    SELECT
        tx_hash,
        evt_index,
        COUNT(*) AS row_count
    FROM baseline_model_rows
    GROUP BY
        tx_hash,
        evt_index
),

optimized_model_key_counts AS (
    SELECT
        tx_hash,
        evt_index,
        COUNT(*) AS row_count
    FROM optimized_model_rows
    GROUP BY
        tx_hash,
        evt_index
),

baseline_model_key_stats AS (
    SELECT
        COUNT(*) AS baseline_model_distinct_keys,
        COALESCE(
            SUM(row_count - 1),
            CAST(0 AS BIGINT)
        ) AS baseline_model_duplicate_key_surplus_rows
    FROM baseline_model_key_counts
),

optimized_model_key_stats AS (
    SELECT
        COUNT(*) AS optimized_model_distinct_keys,
        COALESCE(
            SUM(row_count - 1),
            CAST(0 AS BIGINT)
        ) AS optimized_model_duplicate_key_surplus_rows
    FROM optimized_model_key_counts
),

baseline_model_stats AS (
    SELECT
        COUNT(*) AS baseline_model_rows,
        COUNT_IF(
            tx_hash IS NULL
            OR evt_index IS NULL
        ) AS baseline_model_null_key_rows,
        COUNT_IF(is_repaired)
            AS baseline_repaired_rows,
        COUNT_IF(
            reason_code = 'FEE_BASE_INPUT_SIDE_REVALUATION'
        ) AS baseline_ordinary_repaired_rows,
        COUNT_IF(
            reason_code =
                'FEE_BASE_INPUT_SIDE_REVALUATION_GT_100PCT'
        ) AS baseline_material_repaired_rows,
        COUNT_IF(fee_base_usd IS NULL)
            AS baseline_unpriced_fee_base_rows,
        COUNT_IF(
            is_repaired
            AND fee_base_usd IS NULL
        ) AS baseline_repaired_null_rows,

        CAST(
            ROUND(SUM(fees_usd), 6)
            AS DECIMAL(38, 6)
        ) AS baseline_fees_usd,

        CAST(
            ROUND(SUM(revenue_usd), 6)
            AS DECIMAL(38, 6)
        ) AS baseline_revenue_usd,

        CAST(
            ROUND(SUM(supply_side_fees_usd), 6)
            AS DECIMAL(38, 6)
        ) AS baseline_supply_side_fees_usd,

        CAST(
            ROUND(
                SUM(fees_usd)
                -
                SUM(revenue_usd)
                -
                SUM(supply_side_fees_usd),
                6
            )
            AS DECIMAL(38, 6)
        ) AS baseline_accounting_residual_usd

    FROM baseline_model_rows
),

optimized_model_stats AS (
    SELECT
        COUNT(*) AS optimized_model_rows,
        COUNT_IF(
            tx_hash IS NULL
            OR evt_index IS NULL
        ) AS optimized_model_null_key_rows,
        COUNT_IF(is_repaired)
            AS optimized_repaired_rows,
        COUNT_IF(
            reason_code = 'FEE_BASE_INPUT_SIDE_REVALUATION'
        ) AS optimized_ordinary_repaired_rows,
        COUNT_IF(
            reason_code =
                'FEE_BASE_INPUT_SIDE_REVALUATION_GT_100PCT'
        ) AS optimized_material_repaired_rows,
        COUNT_IF(fee_base_usd IS NULL)
            AS optimized_unpriced_fee_base_rows,
        COUNT_IF(
            is_repaired
            AND fee_base_usd IS NULL
        ) AS optimized_repaired_null_rows,

        CAST(
            ROUND(SUM(fees_usd), 6)
            AS DECIMAL(38, 6)
        ) AS optimized_fees_usd,

        CAST(
            ROUND(SUM(revenue_usd), 6)
            AS DECIMAL(38, 6)
        ) AS optimized_revenue_usd,

        CAST(
            ROUND(SUM(supply_side_fees_usd), 6)
            AS DECIMAL(38, 6)
        ) AS optimized_supply_side_fees_usd,

        CAST(
            ROUND(
                SUM(fees_usd)
                -
                SUM(revenue_usd)
                -
                SUM(supply_side_fees_usd),
                6
            )
            AS DECIMAL(38, 6)
        ) AS optimized_accounting_residual_usd

    FROM optimized_model_rows
),

row_reconciliation AS (
    SELECT
        COUNT_IF(
            b.tx_hash IS NOT NULL
            AND o.tx_hash IS NULL
        ) AS model_baseline_only_keys,

        COUNT_IF(
            b.tx_hash IS NULL
            AND o.tx_hash IS NOT NULL
        ) AS model_optimized_only_keys,

        COUNT_IF(
            b.tx_hash IS NOT NULL
            AND o.tx_hash IS NOT NULL
        ) AS model_matched_keys,

        COUNT_IF(
            b.tx_hash IS NOT NULL
            AND o.tx_hash IS NOT NULL
            AND (
                b.blockchain IS DISTINCT FROM o.blockchain
                OR b.project IS DISTINCT FROM o.project
                OR b.version IS DISTINCT FROM o.version
                OR b.block_date IS DISTINCT FROM o.block_date
                OR b.block_time IS DISTINCT FROM o.block_time
                OR b.block_number IS DISTINCT FROM o.block_number
                OR b.pool IS DISTINCT FROM o.pool
                OR b.token_sold_address
                    IS DISTINCT FROM o.token_sold_address
                OR b.source_amount_usd
                    IS DISTINCT FROM o.source_amount_usd
                OR b.fee_base_usd
                    IS DISTINCT FROM o.fee_base_usd
                OR b.is_repaired IS DISTINCT FROM o.is_repaired
                OR b.reason_code IS DISTINCT FROM o.reason_code
                OR b.fee_tier IS DISTINCT FROM o.fee_tier
                OR b.fee_divisor IS DISTINCT FROM o.fee_divisor
                OR b.fees_usd IS DISTINCT FROM o.fees_usd
                OR b.revenue_usd IS DISTINCT FROM o.revenue_usd
                OR b.supply_side_fees_usd
                    IS DISTINCT FROM o.supply_side_fees_usd
            )
        ) AS model_field_mismatch_keys,

        CAST(
            ROUND(
                SUM(
                    COALESCE(
                        b.fees_usd,
                        CAST(0 AS DECIMAL(38, 18))
                    )
                    -
                    COALESCE(
                        o.fees_usd,
                        CAST(0 AS DECIMAL(38, 18))
                    )
                ),
                6
            )
            AS DECIMAL(38, 6)
        ) AS fees_row_difference_sum_usd,

        CAST(
            ROUND(
                SUM(
                    COALESCE(
                        b.revenue_usd,
                        CAST(0 AS DECIMAL(38, 18))
                    )
                    -
                    COALESCE(
                        o.revenue_usd,
                        CAST(0 AS DECIMAL(38, 18))
                    )
                ),
                6
            )
            AS DECIMAL(38, 6)
        ) AS revenue_row_difference_sum_usd,

        CAST(
            ROUND(
                SUM(
                    COALESCE(
                        b.supply_side_fees_usd,
                        CAST(0 AS DECIMAL(38, 18))
                    )
                    -
                    COALESCE(
                        o.supply_side_fees_usd,
                        CAST(0 AS DECIMAL(38, 18))
                    )
                ),
                6
            )
            AS DECIMAL(38, 6)
        ) AS supply_side_row_difference_sum_usd

    FROM baseline_model_rows b
    FULL OUTER JOIN optimized_model_rows o
        ON b.tx_hash = o.tx_hash
        AND b.evt_index = o.evt_index
),

aggregate_differences AS (
    SELECT
        CAST(
            ROUND(
                b.baseline_fees_usd
                -
                o.optimized_fees_usd,
                6
            )
            AS DECIMAL(38, 6)
        ) AS fees_aggregate_difference_usd,

        CAST(
            ROUND(
                b.baseline_revenue_usd
                -
                o.optimized_revenue_usd,
                6
            )
            AS DECIMAL(38, 6)
        ) AS revenue_aggregate_difference_usd,

        CAST(
            ROUND(
                b.baseline_supply_side_fees_usd
                -
                o.optimized_supply_side_fees_usd,
                6
            )
            AS DECIMAL(38, 6)
        ) AS supply_side_aggregate_difference_usd

    FROM baseline_model_stats b
    CROSS JOIN optimized_model_stats o
)

SELECT
    p.query_run_utc,
    bs.baseline_source_rows,
    bs.baseline_source_null_key_rows,
    bsk.baseline_source_distinct_keys,
    bsk.baseline_source_duplicate_key_surplus_rows,
    bs.baseline_source_unpriced_rows,
    os.optimized_source_rows,
    os.optimized_source_null_key_rows,
    osk.optimized_source_distinct_keys,
    osk.optimized_source_duplicate_key_surplus_rows,
    os.optimized_source_unpriced_rows,
    sr.source_baseline_only_keys,
    sr.source_optimized_only_keys,
    sr.source_row_count_mismatch_keys,
    ps.baseline_pool_rows,
    ps.optimized_pool_rows,
    ss.baseline_setting_event_rows,
    ss.optimized_setting_event_rows,
    bm.baseline_model_rows,
    bm.baseline_model_null_key_rows,
    bmk.baseline_model_distinct_keys,
    bmk.baseline_model_duplicate_key_surplus_rows,
    om.optimized_model_rows,
    om.optimized_model_null_key_rows,
    omk.optimized_model_distinct_keys,
    omk.optimized_model_duplicate_key_surplus_rows,
    rr.model_baseline_only_keys,
    rr.model_optimized_only_keys,
    rr.model_matched_keys,
    rr.model_field_mismatch_keys,
    bm.baseline_repaired_rows,
    om.optimized_repaired_rows,
    bm.baseline_ordinary_repaired_rows,
    om.optimized_ordinary_repaired_rows,
    bm.baseline_material_repaired_rows,
    om.optimized_material_repaired_rows,
    bm.baseline_unpriced_fee_base_rows,
    om.optimized_unpriced_fee_base_rows,
    bm.baseline_repaired_null_rows,
    om.optimized_repaired_null_rows,
    bm.baseline_fees_usd,
    om.optimized_fees_usd,
    bm.baseline_revenue_usd,
    om.optimized_revenue_usd,
    bm.baseline_supply_side_fees_usd,
    om.optimized_supply_side_fees_usd,
    rr.fees_row_difference_sum_usd,
    rr.revenue_row_difference_sum_usd,
    rr.supply_side_row_difference_sum_usd,
    ad.fees_aggregate_difference_usd,
    ad.revenue_aggregate_difference_usd,
    ad.supply_side_aggregate_difference_usd,
    bm.baseline_accounting_residual_usd,
    om.optimized_accounting_residual_usd,

    (
        bs.baseline_source_rows > 0
        AND os.optimized_source_rows > 0
        AND bs.baseline_source_null_key_rows = 0
        AND os.optimized_source_null_key_rows = 0
        AND bsk.baseline_source_distinct_keys =
            bs.baseline_source_rows
        AND bsk.baseline_source_duplicate_key_surplus_rows = 0
        AND osk.optimized_source_distinct_keys =
            os.optimized_source_rows
        AND osk.optimized_source_duplicate_key_surplus_rows = 0
        AND bs.baseline_source_rows = os.optimized_source_rows
        AND bs.baseline_source_unpriced_rows =
            os.optimized_source_unpriced_rows
        AND sr.source_baseline_only_keys = 0
        AND sr.source_optimized_only_keys = 0
        AND sr.source_row_count_mismatch_keys = 0
        AND bm.baseline_model_rows = bs.baseline_source_rows
        AND om.optimized_model_rows = os.optimized_source_rows
        AND bm.baseline_model_null_key_rows = 0
        AND om.optimized_model_null_key_rows = 0
        AND bmk.baseline_model_distinct_keys =
            bm.baseline_model_rows
        AND bmk.baseline_model_duplicate_key_surplus_rows = 0
        AND omk.optimized_model_distinct_keys =
            om.optimized_model_rows
        AND omk.optimized_model_duplicate_key_surplus_rows = 0
        AND rr.model_baseline_only_keys = 0
        AND rr.model_optimized_only_keys = 0
        AND rr.model_matched_keys = bm.baseline_model_rows
        AND rr.model_field_mismatch_keys = 0
        AND bm.baseline_repaired_rows =
            om.optimized_repaired_rows
        AND bm.baseline_ordinary_repaired_rows =
            om.optimized_ordinary_repaired_rows
        AND bm.baseline_material_repaired_rows =
            om.optimized_material_repaired_rows
        AND bm.baseline_unpriced_fee_base_rows =
            om.optimized_unpriced_fee_base_rows
        AND bm.baseline_repaired_null_rows = 0
        AND om.optimized_repaired_null_rows = 0
        AND rr.fees_row_difference_sum_usd =
            CAST(0.000000 AS DECIMAL(38, 6))
        AND rr.revenue_row_difference_sum_usd =
            CAST(0.000000 AS DECIMAL(38, 6))
        AND rr.supply_side_row_difference_sum_usd =
            CAST(0.000000 AS DECIMAL(38, 6))
        AND ad.fees_aggregate_difference_usd =
            CAST(0.000000 AS DECIMAL(38, 6))
        AND ad.revenue_aggregate_difference_usd =
            CAST(0.000000 AS DECIMAL(38, 6))
        AND ad.supply_side_aggregate_difference_usd =
            CAST(0.000000 AS DECIMAL(38, 6))
        AND bm.baseline_accounting_residual_usd =
            CAST(0.000000 AS DECIMAL(38, 6))
        AND om.optimized_accounting_residual_usd =
            CAST(0.000000 AS DECIMAL(38, 6))
    ) AS same_snapshot_baseline_incremental_parity_pass

FROM params p
CROSS JOIN baseline_source_stats bs
CROSS JOIN optimized_source_stats os
CROSS JOIN baseline_source_key_stats bsk
CROSS JOIN optimized_source_key_stats osk
CROSS JOIN source_key_reconciliation sr
CROSS JOIN pool_scan_stats ps
CROSS JOIN setting_scan_stats ss
CROSS JOIN baseline_model_stats bm
CROSS JOIN optimized_model_stats om
CROSS JOIN baseline_model_key_stats bmk
CROSS JOIN optimized_model_key_stats omk
CROSS JOIN row_reconciliation rr
CROSS JOIN aggregate_differences ad;
