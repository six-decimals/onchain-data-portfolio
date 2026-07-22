-- Dune query: PENDING — affected_rows.sql
-- Purpose:
--   Enumerate every WETH/AVAIL row whose fee-calculation base changes
--   when the metric uses the sold-token USD value.
-- Expected output: exactly 142 unique (tx_hash, evt_index) rows.

WITH params AS (
    SELECT
        TIMESTAMP '2026-06-14 00:00:00' AS start_time,
        TIMESTAMP '2026-07-14 00:00:00' AS end_time
),

pool_metadata AS (
    SELECT
        pool,
        token0,
        token1,
        fee AS fee_tier
    FROM uniswap_v3_ethereum.uniswapv3factory_evt_poolcreated
    WHERE pool = 0x80f8143fa056a063aaeecec3323aa3426262ddb2
),

base_trades AS (
    SELECT
        d.block_time,
        d.block_number,
        d.tx_hash,
        d.evt_index,
        d.project_contract_address AS pool,
        d.token_sold_address,
        d.token_bought_address,
        d.token_sold_symbol,
        d.token_bought_symbol,
        d.token_sold_amount,
        d.token_bought_amount,
        d.amount_usd
    FROM dex.trades d
    CROSS JOIN params p
    WHERE d.blockchain = 'ethereum'
      AND d.project = 'uniswap'
      AND d.version = '3'
      AND d.project_contract_address =
          0x80f8143fa056a063aaeecec3323aa3426262ddb2
      AND d.block_time >= p.start_time
      AND d.block_time < p.end_time
),

input_priced AS (
    SELECT
        t.*,
        m.token0,
        m.token1,
        m.fee_tier,
        price.price AS input_token_price_usd
    FROM base_trades t
    INNER JOIN pool_metadata m
        ON t.pool = m.pool
    LEFT JOIN prices.usd price
        ON price.blockchain = 'ethereum'
        AND price.contract_address = t.token_sold_address
        AND price.minute = DATE_TRUNC('minute', t.block_time)
),

valued AS (
    SELECT
        *,
        CAST(amount_usd AS DECIMAL(38, 18))
            AS legacy_fee_base_usd,

        CASE
            WHEN token_sold_amount IS NOT NULL
             AND input_token_price_usd IS NOT NULL
                THEN CAST(
                    CAST(token_sold_amount AS DECIMAL(30, 12))
                    *
                    CAST(input_token_price_usd AS DECIMAL(24, 18))
                    AS DECIMAL(38, 18)
                )
            ELSE NULL
        END AS fixed_fee_base_usd
    FROM input_priced
),

compared AS (
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
    FROM valued
),

affected AS (
    SELECT
        *,
        CASE
            WHEN absolute_difference_pct > 100.0
                THEN 'FEE_BASE_INPUT_SIDE_REVALUATION_GT_100PCT'
            ELSE 'FEE_BASE_INPUT_SIDE_REVALUATION'
        END AS reason_code
    FROM compared
    WHERE fixed_fee_base_usd IS NOT NULL
      AND legacy_fee_base_usd_6
          IS DISTINCT FROM fixed_fee_base_usd_6
),

numbered AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            ORDER BY
                block_number,
                evt_index,
                tx_hash
        ) AS affected_row_number,

        COUNT(*) OVER ()
            AS affected_row_count
    FROM affected
)

SELECT
    affected_row_number,
    affected_row_count,
    block_time,
    block_number,
    tx_hash,
    evt_index,
    pool,

    token_sold_symbol,
    token_sold_address,
    CAST(token_sold_amount AS DECIMAL(38, 18))
        AS token_sold_amount,

    token_bought_symbol,
    token_bought_address,
    CAST(token_bought_amount AS DECIMAL(38, 18))
        AS token_bought_amount,

    fee_tier,

    CAST(input_token_price_usd AS DECIMAL(38, 18))
        AS input_token_price_usd,

    legacy_fee_base_usd_6,
    fixed_fee_base_usd_6,

    CAST(
        fixed_fee_base_usd_6 - legacy_fee_base_usd_6
        AS DECIMAL(38, 6)
    ) AS fee_base_delta_usd,

    CAST(
        ROUND(absolute_difference_pct, 4)
        AS DECIMAL(38, 4)
    ) AS absolute_difference_pct,

    reason_code

FROM numbered
ORDER BY
    block_number,
    evt_index,
    tx_hash;
