-- Dune query: https://dune.com/queries/8126792/
-- File: fee_logic_macro.sql
-- Decision B9=3:
--   Reuse the DECIMAL fee and revenue arithmetic.
--   Keep the Uniswap V3 token-side selector protocol-specific.
--   Keep state-interval joins inside each model.
-- Decision B3-02=1:
--   Validate this macro by same-snapshot row parity.
--   Historical USD totals from query 8075341 are not acceptance anchors.
-- Frozen expected result from the same-snapshot validation:
--   Full-window divisor, fees, and revenue mismatch rows = 0.
--   Three-day-overlap divisor, fees, and revenue mismatch rows = 0.
--   Fees difference, revenue difference, and accounting residual = 0.000000.

{% macro fee_usd_from_ppm(fee_base_usd, fee_tier_ppm) -%}
    CASE
        WHEN {{ fee_base_usd }} IS NOT NULL
            THEN CAST(
                (
                    CAST(
                        {{ fee_base_usd }}
                        AS DECIMAL(38, 18)
                    )
                    /
                    CAST(1000000 AS DECIMAL(7, 0))
                )
                *
                CAST(
                    {{ fee_tier_ppm }}
                    AS DECIMAL(6, 0)
                )
                AS DECIMAL(38, 18)
            )
        ELSE CAST(0 AS DECIMAL(38, 18))
    END
{%- endmacro %}

{% macro protocol_revenue_usd_from_divisor(
    fees_usd,
    fee_divisor
) -%}
    CASE
        WHEN {{ fee_divisor }} BETWEEN 4 AND 10
            THEN CAST(
                CAST(
                    {{ fees_usd }}
                    AS DECIMAL(38, 18)
                )
                /
                CAST(
                    {{ fee_divisor }}
                    AS DECIMAL(2, 0)
                )
                AS DECIMAL(38, 18)
            )
        ELSE CAST(0 AS DECIMAL(38, 18))
    END
{%- endmacro %}

{% macro uniswap_v3_fee_divisor(
    token_sold_address,
    token0_address,
    token1_address,
    feeprotocol0,
    feeprotocol1
) -%}
    CASE
        WHEN {{ token_sold_address }} = {{ token0_address }}
            THEN CAST({{ feeprotocol0 }} AS INTEGER)
        WHEN {{ token_sold_address }} = {{ token1_address }}
            THEN CAST({{ feeprotocol1 }} AS INTEGER)
        ELSE NULL
    END
{%- endmacro %}
