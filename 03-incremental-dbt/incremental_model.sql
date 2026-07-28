-- Dune query: https://dune.com/queries/8127229
-- File: incremental_model.sql
-- Scope:
--   Ethereum Uniswap V3 trade-level fees and protocol revenue.
-- Decisions:
--   B8=2: three UTC-date overlap, full refresh after logic changes,
--         and explicit date-bounded historical backfills.
--   B9=3: shared DECIMAL arithmetic with a Uniswap V3 override.
--   B3-02=1: validate by same-snapshot row parity, not historical totals.
--   B3-03=2: delete and reinsert complete block_date partitions.
-- Full refresh:
--   dbt run --select incremental_model --full-refresh
-- Targeted backfill:
--   dbt run --select incremental_model --vars
--   '{"backfill_start_date":"YYYY-MM-DD",
--     "backfill_end_date":"YYYY-MM-DD"}'
-- Backfill dates are UTC, start-inclusive, and end-exclusive.
-- block_date is the partition replacement key.
-- Row uniqueness remains (tx_hash, evt_index).
-- Frozen expected result from Dune query 8127229:
--   Query run: 2026-07-27 16:45:58.655 UTC.
--   Observed row counts, not future gates: full 3,105,887;
--   incremental 284,882; retained 2,821,005; simulated 3,105,887.
--   Full, incremental, and simulated duplicate surplus rows: 0.
--   Incremental dates: 2026-07-11 through 2026-07-13.
--   Full-only keys, simulated-only keys, and field mismatches: 0.
--   Fees, revenue, and supply-side row-difference sums: 0.000000.
--   Full and simulated accounting residuals: 0.000000.
--   same_snapshot_incremental_parity_pass: true.
--   Row counts and USD totals are observations, not acceptance anchors.

{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='block_date'
    )
}}

{% set model_start_date = var('model_start_date', '2021-05-04') %}
{% set model_end_date = var('model_end_date', none) %}
{% set backfill_start_date = var('backfill_start_date', none) %}
{% set backfill_end_date = var('backfill_end_date', none) %}

{% if backfill_start_date is none
      and backfill_end_date is not none %}
    {{
        exceptions.raise_compiler_error(
            "backfill_start_date is required when backfill_end_date is set"
        )
    }}
{% elif backfill_start_date is not none
        and backfill_end_date is none %}
    {{
        exceptions.raise_compiler_error(
            "backfill_end_date is required when backfill_start_date is set"
        )
    }}
{% endif %}

WITH trades AS (
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
    WHERE d.blockchain = 'ethereum'
      AND d.project = 'uniswap'
      AND d.version = '3'
      AND d.block_date >= DATE '{{ model_start_date }}'

    {% if model_end_date is not none %}
      AND d.block_date < DATE '{{ model_end_date }}'
    {% else %}
      AND d.block_date < CURRENT_DATE
    {% endif %}

    {% if is_incremental() %}
        {% if backfill_start_date is not none %}
      AND d.block_date >= DATE '{{ backfill_start_date }}'
      AND d.block_date < DATE '{{ backfill_end_date }}'
        {% else %}
      AND d.block_date >= (
            SELECT
                COALESCE(
                    DATE_ADD(
                        'day',
                        -2,
                        MAX(existing.block_date)
                    ),
                    DATE '{{ model_start_date }}'
                )
            FROM {{ this }} existing
        )
        {% endif %}
    {% endif %}
),

candidate_pools AS (
    SELECT DISTINCT
        pool
    FROM trades
),

pools AS (
    SELECT
        p.pool,
        p.token0,
        p.token1,
        p.fee AS fee_tier,
        p.evt_block_number AS created_block_number,
        p.evt_index AS created_evt_index
    FROM uniswap_v3_ethereum.uniswapv3factory_evt_poolcreated p
    INNER JOIN candidate_pools c
        ON p.pool = c.pool
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
            -- Diagnostic-only DOUBLE path for the reason-code threshold.
            -- Formal USD outputs remain DECIMAL(38, 18).
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

        {{
            uniswap_v3_fee_divisor(
                't.token_sold_address',
                'f.token0',
                'f.token1',
                'f.feeprotocol0',
                'f.feeprotocol1'
            )
        }} AS fee_divisor

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

        {{
            fee_usd_from_ppm(
                'fee_base_usd',
                'fee_tier'
            )
        }} AS fees_usd

    FROM trades_with_settings
),

revenue_metrics AS (
    SELECT
        *,

        {{
            protocol_revenue_usd_from_divisor(
                'fees_usd',
                'fee_divisor'
            )
        }} AS revenue_usd

    FROM fee_metrics
),

final AS (
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

    FROM revenue_metrics
)

SELECT *
FROM final;
