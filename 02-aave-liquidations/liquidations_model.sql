/*
Purpose:
  Build the unpriced Aave V3 Ethereum event-level liquidation model from
  decoded Pool LiquidationCall events for the frozen UTC window.

Raw source:
  aave_v3_ethereum.Pool_evt_LiquidationCall

Token metadata source:
  tokens.erc20

Expected output:
  308 rows and 17 columns.
  One row must represent one LiquidationCall event keyed by
  tx_hash + evt_index.

Paste back:
  Paste the displayed total row count and rows 1-5.
  A screenshot is acceptable if copying all 17 columns is inconvenient.
  If the query fails, paste the complete error and execution ID.
*/

WITH token_metadata_ranked AS (
    SELECT
        contract_address,
        symbol,
        decimals,
        ROW_NUMBER() OVER (
            PARTITION BY contract_address
            ORDER BY _updated_at DESC NULLS LAST
        ) AS metadata_rank
    FROM tokens.erc20
    WHERE blockchain = 'ethereum'
),

token_metadata AS (
    SELECT
        contract_address,
        symbol,
        decimals
    FROM token_metadata_ranked
    WHERE metadata_rank = 1
),

raw_liquidations AS (
    SELECT
        evt_block_time,
        evt_block_number,
        evt_tx_hash,
        evt_index,
        liquidator,
        user,
        collateralasset,
        debtasset,
        liquidatedcollateralamount,
        debttocover,
        receiveatoken
    FROM aave_v3_ethereum.Pool_evt_LiquidationCall
    WHERE evt_block_date >= DATE '2026-06-14'
      AND evt_block_date <  DATE '2026-07-14'
      AND evt_block_time >= TIMESTAMP '2026-06-14 00:00:00'
      AND evt_block_time <  TIMESTAMP '2026-07-14 00:00:00'
)

SELECT
    r.evt_block_time AS block_time,
    r.evt_block_number AS block_number,
    r.evt_tx_hash AS tx_hash,
    r.evt_index,
    r.liquidator,
    r.user AS borrower,
    r.collateralasset AS collateral_asset,
    r.debtasset AS debt_asset,
    collateral_metadata.symbol AS collateral_symbol,
    debt_metadata.symbol AS debt_symbol,
    collateral_metadata.decimals AS collateral_decimals,
    debt_metadata.decimals AS debt_decimals,
    r.liquidatedcollateralamount AS collateral_amount_raw,
    r.debttocover AS debt_amount_raw,
    CASE
        WHEN collateral_metadata.decimals IS NULL THEN NULL
        ELSE CAST(r.liquidatedcollateralamount AS DOUBLE)
             / POWER(10.0, collateral_metadata.decimals)
    END AS collateral_amount,
    CASE
        WHEN debt_metadata.decimals IS NULL THEN NULL
        ELSE CAST(r.debttocover AS DOUBLE)
             / POWER(10.0, debt_metadata.decimals)
    END AS debt_amount,
    r.receiveatoken AS receive_atoken
FROM raw_liquidations r
LEFT JOIN token_metadata collateral_metadata
    ON r.collateralasset = collateral_metadata.contract_address
LEFT JOIN token_metadata debt_metadata
    ON r.debtasset = debt_metadata.contract_address
ORDER BY
    block_time,
    tx_hash,
    evt_index;
