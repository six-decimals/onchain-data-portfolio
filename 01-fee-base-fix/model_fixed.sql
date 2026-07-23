-- Dune query: 8075341 — https://dune.com/queries/8075341/
-- Purpose:
--   Recalculate Uniswap V3 fees and protocol revenue after replacing
--   the fee-calculation base for 142 affected WETH/AVAIL trades.
-- Scope:
--   Ethereum, Uniswap V3, UTC [2026-06-14, 2026-07-14).

WITH params AS (
    SELECT
        TIMESTAMP '2026-06-14 00:00:00' AS start_time,
        TIMESTAMP '2026-07-14 00:00:00' AS end_time
),

pools AS (
    SELECT
        pool,
        token0,
        token1,
        fee AS fee_tier,
        evt_block_number AS created_block_number,
        evt_index AS created_evt_index
    FROM uniswap_v3_ethereum.uniswapv3factory_evt_poolcreated
),

initial_settings AS (
    SELECT
        pool,
        token0,
        token1,
        fee_tier,
        created_block_number AS setting_block_number,
        created_evt_index AS setting_evt_index,
        CAST(0 AS INTEGER) AS feeprotocol0,
        CAST(0 AS INTEGER) AS feeprotocol1
    FROM pools
),

setting_events AS (
    SELECT
        p.pool,
        p.token0,
        p.token1,
        p.fee_tier,
        s.evt_block_number AS setting_block_number,
        s.evt_index AS setting_evt_index,
        CAST(s.feeprotocol0new AS INTEGER) AS feeprotocol0,
        CAST(s.feeprotocol1new AS INTEGER) AS feeprotocol1
    FROM uniswap_v3_ethereum.uniswapv3pool_evt_setfeeprotocol s
    INNER JOIN pools p
        ON s.contract_address = p.pool
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
        pool,
        token0,
        token1,
        fee_tier,
        setting_block_number,
        setting_evt_index,
        feeprotocol0,
        feeprotocol1,

        LEAD(setting_block_number) OVER (
            PARTITION BY pool
            ORDER BY
                setting_block_number,
                setting_evt_index
        ) AS next_setting_block_number,

        LEAD(setting_evt_index) OVER (
            PARTITION BY pool
            ORDER BY
                setting_block_number,
                setting_evt_index
        ) AS next_setting_evt_index

    FROM all_setting_points
),

trades AS (
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

target_input_priced AS (
    SELECT
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

    FROM trades t
    LEFT JOIN prices.usd price
        ON price.blockchain = 'ethereum'
        AND price.contract_address = t.token_sold_address
        AND price.minute = DATE_TRUNC('minute', t.block_time)

    WHERE t.pool =
        0x80f8143fa056a063aaeecec3323aa3426262ddb2
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

trades_with_settings AS (
    SELECT
        t.block_number,
        t.tx_hash,
        t.evt_index,
        t.pool,

        COALESCE(
            a.fixed_fee_base_usd,
            CAST(t.amount_usd AS DECIMAL(38, 18))
        ) AS fee_base_usd,

        a.tx_hash IS NOT NULL
            AS is_repaired,

        a.reason_code,

        f.fee_tier,

        CASE
            WHEN t.token_sold_address = f.token0
                THEN f.feeprotocol0
            WHEN t.token_sold_address = f.token1
                THEN f.feeprotocol1
            ELSE NULL
        END AS fee_divisor

    FROM trades t

    INNER JOIN fee_intervals f
        ON t.pool = f.pool

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
        ON t.block_number = a.block_number
        AND t.tx_hash = a.tx_hash
        AND t.evt_index = a.evt_index
        AND t.pool = a.pool
),

fee_metrics AS (
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

    FROM trades_with_settings
),

trade_metrics AS (
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

    FROM fee_metrics
)

SELECT
    COUNT(*) AS trade_rows,

    COUNT_IF(is_repaired)
        AS repaired_rows,

    COUNT_IF(
        reason_code = 'FEE_BASE_INPUT_SIDE_REVALUATION'
    ) AS ordinary_repaired_rows,

    COUNT_IF(
        reason_code =
            'FEE_BASE_INPUT_SIDE_REVALUATION_GT_100PCT'
    ) AS material_repaired_rows,

    COUNT_IF(fee_base_usd IS NULL)
        AS unpriced_fee_base_rows,

    COUNT_IF(
        is_repaired
        AND fee_base_usd IS NULL
    ) AS repaired_null_rows,

    CAST(
        ROUND(SUM(fees_usd), 6)
        AS DECIMAL(38, 6)
    ) AS fees_usd,

    CAST(
        ROUND(
            SUM(fees_usd) - SUM(revenue_usd),
            6
        )
        AS DECIMAL(38, 6)
    ) AS supply_side_fees_usd,

    CAST(
        ROUND(SUM(revenue_usd), 6)
        AS DECIMAL(38, 6)
    ) AS revenue_usd,

    CAST(
        ROUND(
            SUM(fees_usd)
            -
            (
                SUM(fees_usd) - SUM(revenue_usd)
            )
            -
            SUM(revenue_usd),
            6
        )
        AS DECIMAL(38, 6)
    ) AS accounting_residual_usd

FROM trade_metrics;
