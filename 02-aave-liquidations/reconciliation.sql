-- Dune query: https://dune.com/queries/8092306/
/*
Purpose:
  Build the priced Aave V3 Ethereum liquidation model under rulings
  B05=1, B06=1, B07=1, and B08=1, then reconcile both liquidation legs
  against the main-market rows in lending.borrow and lending.supply.

Reconciliation key:
  tx_hash + evt_index

Scope:
  Ethereum only.
  Fixed UTC window: [2026-06-14 00:00:00, 2026-07-14 00:00:00).
  Spellbook rows are explicitly restricted to project='aave' and version='3'.
  Aave Lido, EtherFi, and Horizon rows are excluded per B04 scope ruling.

Pricing:
  prices.usd at the event's UTC minute.
  Missing prices remain NULL.
  liquidation_amount_usd equals debt_amount_usd.

Sign convention:
  This model stores liquidation magnitudes as positive values.
  Spellbook stores both liquidation legs as negative lending outflows.
  Magnitude comparisons therefore use ABS on Spellbook amounts.

Expected output:
  Exactly 1 row and 56 columns.
  If every event and amount reconciles exactly,
  step6_reconciliation_status will be PASS_EXACT_RECONCILIATION.
  If exact USD differences exist, the row will also identify the largest
  numerical difference on each liquidation leg.

Paste back:
  Paste the complete single result row with all 56 columns.
  If the query fails, paste the complete error and execution ID.
*/

WITH raw_liquidations AS (
    SELECT
        contract_address,
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
),

token_metadata_ranked AS (
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

minute_prices AS (
    SELECT
        minute,
        contract_address,
        decimals,
        price
    FROM prices.usd
    WHERE blockchain = 'ethereum'
      AND minute >= TIMESTAMP '2026-06-14 00:00:00'
      AND minute <  TIMESTAMP '2026-07-14 00:00:00'
),

model_v1 AS (
    SELECT
        r.evt_block_time AS block_time,
        r.evt_block_number AS block_number,
        r.evt_tx_hash AS tx_hash,
        r.evt_index,
        r.contract_address AS project_contract_address,
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
),

model_v2_priced AS (
    SELECT
        m.*,
        debt_price.price AS debt_price_usd,
        collateral_price.price AS collateral_price_usd,
        debt_price.decimals AS debt_price_decimals,
        collateral_price.decimals AS collateral_price_decimals,
        CASE
            WHEN debt_price.price IS NULL THEN NULL
            ELSE CAST(m.debt_amount_raw AS DOUBLE)
                 / POWER(
                     10,
                     COALESCE(
                         debt_price.decimals,
                         m.debt_decimals,
                         18
                     )
                 )
                 * debt_price.price
        END AS debt_amount_usd,
        CASE
            WHEN collateral_price.price IS NULL THEN NULL
            ELSE CAST(m.collateral_amount_raw AS DOUBLE)
                 / POWER(
                     10,
                     COALESCE(
                         collateral_price.decimals,
                         m.collateral_decimals,
                         18
                     )
                 )
                 * collateral_price.price
        END AS collateral_amount_usd,
        CASE
            WHEN debt_price.price IS NULL THEN 'MISSING_PRICE'
            ELSE 'PRICED'
        END AS debt_price_status,
        CASE
            WHEN collateral_price.price IS NULL THEN 'MISSING_PRICE'
            ELSE 'PRICED'
        END AS collateral_price_status
    FROM model_v1 m
    LEFT JOIN minute_prices debt_price
        ON DATE_TRUNC('minute', m.block_time) = debt_price.minute
       AND m.debt_asset = debt_price.contract_address
    LEFT JOIN minute_prices collateral_price
        ON DATE_TRUNC('minute', m.block_time) = collateral_price.minute
       AND m.collateral_asset = collateral_price.contract_address
),

model_v2 AS (
    SELECT
        *,
        debt_amount_usd AS liquidation_amount_usd
    FROM model_v2_priced
),

spellbook_borrow AS (
    SELECT
        block_time,
        block_number,
        project_contract_address,
        tx_hash,
        CAST(evt_index AS BIGINT) AS evt_index,
        token_address,
        borrower,
        repayer,
        liquidator,
        amount,
        amount_raw,
        amount_usd,
        symbol
    FROM lending.borrow
    WHERE blockchain = 'ethereum'
      AND project = 'aave'
      AND version = '3'
      AND transaction_type = 'borrow_liquidation'
      AND block_month >= DATE '2026-06-01'
      AND block_month <  DATE '2026-08-01'
      AND block_time >= TIMESTAMP '2026-06-14 00:00:00 UTC'
      AND block_time <  TIMESTAMP '2026-07-14 00:00:00 UTC'
),

spellbook_supply AS (
    SELECT
        block_time,
        block_number,
        project_contract_address,
        tx_hash,
        CAST(evt_index AS BIGINT) AS evt_index,
        token_address,
        depositor,
        withdrawn_to,
        liquidator,
        amount,
        amount_raw,
        amount_usd,
        symbol
    FROM lending.supply
    WHERE blockchain = 'ethereum'
      AND project = 'aave'
      AND version = '3'
      AND transaction_type = 'deposit_liquidation'
      AND block_month >= DATE '2026-06-01'
      AND block_month <  DATE '2026-08-01'
      AND block_time >= TIMESTAMP '2026-06-14 00:00:00 UTC'
      AND block_time <  TIMESTAMP '2026-07-14 00:00:00 UTC'
),

model_profile AS (
    SELECT
        COUNT(*) AS model_v2_rows,
        COUNT(DISTINCT ROW(tx_hash, evt_index))
            AS model_v2_distinct_event_keys,
        COUNT_IF(debt_amount_usd IS NOT NULL)
            AS model_debt_priced_rows,
        COUNT_IF(collateral_amount_usd IS NOT NULL)
            AS model_collateral_priced_rows,
        COUNT_IF(
            debt_amount_usd IS NOT NULL
            AND collateral_amount_usd IS NOT NULL
        ) AS model_both_legs_priced_rows,
        COUNT_IF(
            debt_amount_usd IS NULL
            OR collateral_amount_usd IS NULL
        ) AS model_any_leg_unpriced_rows,
        SUM(liquidation_amount_usd)
            AS model_primary_liquidation_usd_total,
        SUM(collateral_amount_usd)
            AS model_collateral_usd_total
    FROM model_v2
),

borrow_profile AS (
    SELECT
        COUNT(*) AS spellbook_borrow_rows,
        COUNT(DISTINCT ROW(tx_hash, evt_index))
            AS spellbook_borrow_distinct_event_keys,
        COUNT_IF(amount_usd IS NOT NULL)
            AS spellbook_debt_priced_rows,
        SUM(ABS(amount_usd))
            AS spellbook_debt_usd_abs_total
    FROM spellbook_borrow
),

supply_profile AS (
    SELECT
        COUNT(*) AS spellbook_supply_rows,
        COUNT(DISTINCT ROW(tx_hash, evt_index))
            AS spellbook_supply_distinct_event_keys,
        COUNT_IF(amount_usd IS NOT NULL)
            AS spellbook_collateral_priced_rows,
        SUM(ABS(amount_usd))
            AS spellbook_collateral_usd_abs_total
    FROM spellbook_supply
),

model_keys AS (
    SELECT DISTINCT
        tx_hash,
        evt_index
    FROM model_v2
),

borrow_keys AS (
    SELECT DISTINCT
        tx_hash,
        evt_index
    FROM spellbook_borrow
),

supply_keys AS (
    SELECT DISTINCT
        tx_hash,
        evt_index
    FROM spellbook_supply
),

borrow_key_reconciliation AS (
    SELECT
        COUNT_IF(b.tx_hash IS NULL)
            AS model_without_borrow_keys,
        COUNT_IF(m.tx_hash IS NULL)
            AS borrow_without_model_keys
    FROM model_keys m
    FULL OUTER JOIN borrow_keys b
        ON m.tx_hash = b.tx_hash
       AND m.evt_index = b.evt_index
),

supply_key_reconciliation AS (
    SELECT
        COUNT_IF(s.tx_hash IS NULL)
            AS model_without_supply_keys,
        COUNT_IF(m.tx_hash IS NULL)
            AS supply_without_model_keys
    FROM model_keys m
    FULL OUTER JOIN supply_keys s
        ON m.tx_hash = s.tx_hash
       AND m.evt_index = s.evt_index
),

reconciled AS (
    SELECT
        m.*,

        b.tx_hash AS borrow_match_tx_hash,
        b.block_number AS borrow_block_number,
        b.project_contract_address
            AS borrow_project_contract_address,
        b.token_address AS spellbook_debt_asset,
        b.borrower AS spellbook_borrower,
        b.repayer AS spellbook_repayer,
        b.liquidator AS spellbook_borrow_liquidator,
        b.amount AS spellbook_debt_amount_signed,
        b.amount_raw AS spellbook_debt_amount_raw,
        b.amount_usd AS spellbook_debt_amount_usd_signed,
        b.symbol AS spellbook_debt_symbol,

        s.tx_hash AS supply_match_tx_hash,
        s.block_number AS supply_block_number,
        s.project_contract_address
            AS supply_project_contract_address,
        s.token_address AS spellbook_collateral_asset,
        s.depositor AS spellbook_depositor,
        s.withdrawn_to AS spellbook_withdrawn_to,
        s.liquidator AS spellbook_supply_liquidator,
        s.amount AS spellbook_collateral_amount_signed,
        s.amount_raw AS spellbook_collateral_amount_raw,
        s.amount_usd AS spellbook_collateral_amount_usd_signed,
        s.symbol AS spellbook_collateral_symbol
    FROM model_v2 m
    LEFT JOIN spellbook_borrow b
        ON m.tx_hash = b.tx_hash
       AND m.evt_index = b.evt_index
    LEFT JOIN spellbook_supply s
        ON m.tx_hash = s.tx_hash
       AND m.evt_index = s.evt_index
),

reconciliation_quality AS (
    SELECT
        COUNT_IF(
            borrow_match_tx_hash IS NOT NULL
            AND block_number IS DISTINCT FROM borrow_block_number
        ) AS borrow_block_number_mismatch_rows,

        COUNT_IF(
            supply_match_tx_hash IS NOT NULL
            AND block_number IS DISTINCT FROM supply_block_number
        ) AS supply_block_number_mismatch_rows,

        COUNT_IF(
            borrow_match_tx_hash IS NOT NULL
            AND debt_asset IS DISTINCT FROM spellbook_debt_asset
        ) AS debt_asset_mismatch_rows,

        COUNT_IF(
            supply_match_tx_hash IS NOT NULL
            AND collateral_asset
                IS DISTINCT FROM spellbook_collateral_asset
        ) AS collateral_asset_mismatch_rows,

        COUNT_IF(
            borrow_match_tx_hash IS NOT NULL
            AND borrower IS DISTINCT FROM spellbook_borrower
        ) AS borrow_borrower_mismatch_rows,

        COUNT_IF(
            supply_match_tx_hash IS NOT NULL
            AND borrower IS DISTINCT FROM spellbook_depositor
        ) AS supply_borrower_mismatch_rows,

        COUNT_IF(
            borrow_match_tx_hash IS NOT NULL
            AND (
                liquidator
                    IS DISTINCT FROM spellbook_borrow_liquidator
                OR liquidator IS DISTINCT FROM spellbook_repayer
            )
        ) AS borrow_liquidator_mapping_mismatch_rows,

        COUNT_IF(
            supply_match_tx_hash IS NOT NULL
            AND (
                liquidator
                    IS DISTINCT FROM spellbook_supply_liquidator
                OR liquidator IS DISTINCT FROM spellbook_withdrawn_to
            )
        ) AS supply_liquidator_mapping_mismatch_rows,

        COUNT_IF(
            borrow_match_tx_hash IS NOT NULL
            AND debt_amount_raw
                IS DISTINCT FROM spellbook_debt_amount_raw
        ) AS debt_raw_amount_mismatch_rows,

        COUNT_IF(
            supply_match_tx_hash IS NOT NULL
            AND collateral_amount_raw
                IS DISTINCT FROM spellbook_collateral_amount_raw
        ) AS collateral_raw_amount_mismatch_rows,

        COUNT_IF(
            borrow_match_tx_hash IS NOT NULL
            AND debt_amount
                IS DISTINCT FROM ABS(spellbook_debt_amount_signed)
        ) AS debt_token_amount_exact_mismatch_rows,

        COUNT_IF(
            supply_match_tx_hash IS NOT NULL
            AND collateral_amount
                IS DISTINCT FROM ABS(
                    spellbook_collateral_amount_signed
                )
        ) AS collateral_token_amount_exact_mismatch_rows,

        COUNT_IF(
            borrow_match_tx_hash IS NOT NULL
            AND spellbook_debt_amount_signed >= 0
        ) AS borrow_nonnegative_signed_amount_rows,

        COUNT_IF(
            supply_match_tx_hash IS NOT NULL
            AND spellbook_collateral_amount_signed >= 0
        ) AS supply_nonnegative_signed_amount_rows,

        COUNT_IF(
            borrow_match_tx_hash IS NOT NULL
            AND (
                (debt_amount_usd IS NULL)
                <> (spellbook_debt_amount_usd_signed IS NULL)
            )
        ) AS debt_usd_null_status_mismatch_rows,

        COUNT_IF(
            supply_match_tx_hash IS NOT NULL
            AND (
                (collateral_amount_usd IS NULL)
                <> (spellbook_collateral_amount_usd_signed IS NULL)
            )
        ) AS collateral_usd_null_status_mismatch_rows,

        COUNT_IF(
            borrow_match_tx_hash IS NOT NULL
            AND debt_amount_usd
                IS DISTINCT FROM ABS(
                    spellbook_debt_amount_usd_signed
                )
        ) AS debt_usd_exact_mismatch_rows,

        COUNT_IF(
            supply_match_tx_hash IS NOT NULL
            AND collateral_amount_usd
                IS DISTINCT FROM ABS(
                    spellbook_collateral_amount_usd_signed
                )
        ) AS collateral_usd_exact_mismatch_rows
    FROM reconciled
),

debt_difference_ranked AS (
    SELECT
        ABS(
            debt_amount_usd
            - ABS(spellbook_debt_amount_usd_signed)
        ) AS abs_usd_diff,
        CONCAT('0x', TO_HEX(tx_hash)) AS tx_hash_hex,
        evt_index,
        debt_symbol AS symbol,
        debt_amount_usd AS model_usd,
        ABS(spellbook_debt_amount_usd_signed)
            AS spellbook_usd_abs,
        ROW_NUMBER() OVER (
            ORDER BY
                ABS(
                    debt_amount_usd
                    - ABS(spellbook_debt_amount_usd_signed)
                ) DESC,
                block_time,
                tx_hash,
                evt_index
        ) AS diff_rank
    FROM reconciled
    WHERE borrow_match_tx_hash IS NOT NULL
      AND debt_amount_usd IS NOT NULL
      AND spellbook_debt_amount_usd_signed IS NOT NULL
      AND debt_amount_usd
          IS DISTINCT FROM ABS(
              spellbook_debt_amount_usd_signed
          )
),

collateral_difference_ranked AS (
    SELECT
        ABS(
            collateral_amount_usd
            - ABS(spellbook_collateral_amount_usd_signed)
        ) AS abs_usd_diff,
        CONCAT('0x', TO_HEX(tx_hash)) AS tx_hash_hex,
        evt_index,
        collateral_symbol AS symbol,
        collateral_amount_usd AS model_usd,
        ABS(spellbook_collateral_amount_usd_signed)
            AS spellbook_usd_abs,
        ROW_NUMBER() OVER (
            ORDER BY
                ABS(
                    collateral_amount_usd
                    - ABS(
                        spellbook_collateral_amount_usd_signed
                    )
                ) DESC,
                block_time,
                tx_hash,
                evt_index
        ) AS diff_rank
    FROM reconciled
    WHERE supply_match_tx_hash IS NOT NULL
      AND collateral_amount_usd IS NOT NULL
      AND spellbook_collateral_amount_usd_signed IS NOT NULL
      AND collateral_amount_usd
          IS DISTINCT FROM ABS(
              spellbook_collateral_amount_usd_signed
          )
),

max_debt_difference AS (
    SELECT
        MAX(
            CASE WHEN diff_rank = 1 THEN abs_usd_diff END
        ) AS max_debt_abs_usd_diff,
        MAX(
            CASE WHEN diff_rank = 1 THEN tx_hash_hex END
        ) AS max_debt_diff_tx_hash,
        MAX(
            CASE WHEN diff_rank = 1 THEN evt_index END
        ) AS max_debt_diff_evt_index,
        MAX(
            CASE WHEN diff_rank = 1 THEN symbol END
        ) AS max_debt_diff_symbol,
        MAX(
            CASE WHEN diff_rank = 1 THEN model_usd END
        ) AS max_debt_diff_model_usd,
        MAX(
            CASE WHEN diff_rank = 1 THEN spellbook_usd_abs END
        ) AS max_debt_diff_spellbook_usd_abs
    FROM debt_difference_ranked
),

max_collateral_difference AS (
    SELECT
        MAX(
            CASE WHEN diff_rank = 1 THEN abs_usd_diff END
        ) AS max_collateral_abs_usd_diff,
        MAX(
            CASE WHEN diff_rank = 1 THEN tx_hash_hex END
        ) AS max_collateral_diff_tx_hash,
        MAX(
            CASE WHEN diff_rank = 1 THEN evt_index END
        ) AS max_collateral_diff_evt_index,
        MAX(
            CASE WHEN diff_rank = 1 THEN symbol END
        ) AS max_collateral_diff_symbol,
        MAX(
            CASE WHEN diff_rank = 1 THEN model_usd END
        ) AS max_collateral_diff_model_usd,
        MAX(
            CASE WHEN diff_rank = 1 THEN spellbook_usd_abs END
        ) AS max_collateral_diff_spellbook_usd_abs
    FROM collateral_difference_ranked
)

SELECT
    mp.model_v2_rows,
    mp.model_v2_distinct_event_keys,
    mp.model_v2_rows - mp.model_v2_distinct_event_keys
        AS model_v2_duplicate_key_surplus_rows,

    mp.model_debt_priced_rows,
    mp.model_collateral_priced_rows,
    mp.model_both_legs_priced_rows,
    mp.model_any_leg_unpriced_rows,

    bp.spellbook_borrow_rows,
    bp.spellbook_borrow_distinct_event_keys,
    bp.spellbook_borrow_rows
        - bp.spellbook_borrow_distinct_event_keys
        AS spellbook_borrow_duplicate_key_surplus_rows,
    bp.spellbook_debt_priced_rows,

    sp.spellbook_supply_rows,
    sp.spellbook_supply_distinct_event_keys,
    sp.spellbook_supply_rows
        - sp.spellbook_supply_distinct_event_keys
        AS spellbook_supply_duplicate_key_surplus_rows,
    sp.spellbook_collateral_priced_rows,

    bkr.model_without_borrow_keys,
    bkr.borrow_without_model_keys,
    skr.model_without_supply_keys,
    skr.supply_without_model_keys,

    rq.borrow_block_number_mismatch_rows,
    rq.supply_block_number_mismatch_rows,
    rq.debt_asset_mismatch_rows,
    rq.collateral_asset_mismatch_rows,
    rq.borrow_borrower_mismatch_rows,
    rq.supply_borrower_mismatch_rows,
    rq.borrow_liquidator_mapping_mismatch_rows,
    rq.supply_liquidator_mapping_mismatch_rows,
    rq.debt_raw_amount_mismatch_rows,
    rq.collateral_raw_amount_mismatch_rows,
    rq.debt_token_amount_exact_mismatch_rows,
    rq.collateral_token_amount_exact_mismatch_rows,
    rq.borrow_nonnegative_signed_amount_rows,
    rq.supply_nonnegative_signed_amount_rows,
    rq.debt_usd_null_status_mismatch_rows,
    rq.collateral_usd_null_status_mismatch_rows,
    rq.debt_usd_exact_mismatch_rows,
    rq.collateral_usd_exact_mismatch_rows,

    mp.model_primary_liquidation_usd_total,
    bp.spellbook_debt_usd_abs_total,
    mp.model_primary_liquidation_usd_total
        - bp.spellbook_debt_usd_abs_total
        AS primary_liquidation_usd_total_diff,

    mp.model_collateral_usd_total,
    sp.spellbook_collateral_usd_abs_total,
    mp.model_collateral_usd_total
        - sp.spellbook_collateral_usd_abs_total
        AS collateral_usd_total_diff,

    mdd.max_debt_abs_usd_diff,
    mdd.max_debt_diff_tx_hash,
    mdd.max_debt_diff_evt_index,
    mdd.max_debt_diff_symbol,
    mdd.max_debt_diff_model_usd,
    mdd.max_debt_diff_spellbook_usd_abs,

    mcd.max_collateral_abs_usd_diff,
    mcd.max_collateral_diff_tx_hash,
    mcd.max_collateral_diff_evt_index,
    mcd.max_collateral_diff_symbol,
    mcd.max_collateral_diff_model_usd,
    mcd.max_collateral_diff_spellbook_usd_abs,

    CASE
        WHEN mp.model_v2_rows = 308
         AND mp.model_v2_distinct_event_keys = 308
         AND bp.spellbook_borrow_rows = 308
         AND bp.spellbook_borrow_distinct_event_keys = 308
         AND sp.spellbook_supply_rows = 308
         AND sp.spellbook_supply_distinct_event_keys = 308
         AND bkr.model_without_borrow_keys = 0
         AND bkr.borrow_without_model_keys = 0
         AND skr.model_without_supply_keys = 0
         AND skr.supply_without_model_keys = 0
         AND rq.borrow_block_number_mismatch_rows = 0
         AND rq.supply_block_number_mismatch_rows = 0
         AND rq.debt_asset_mismatch_rows = 0
         AND rq.collateral_asset_mismatch_rows = 0
         AND rq.borrow_borrower_mismatch_rows = 0
         AND rq.supply_borrower_mismatch_rows = 0
         AND rq.borrow_liquidator_mapping_mismatch_rows = 0
         AND rq.supply_liquidator_mapping_mismatch_rows = 0
         AND rq.debt_raw_amount_mismatch_rows = 0
         AND rq.collateral_raw_amount_mismatch_rows = 0
         AND rq.debt_token_amount_exact_mismatch_rows = 0
         AND rq.collateral_token_amount_exact_mismatch_rows = 0
         AND rq.borrow_nonnegative_signed_amount_rows = 0
         AND rq.supply_nonnegative_signed_amount_rows = 0
         AND rq.debt_usd_null_status_mismatch_rows = 0
         AND rq.collateral_usd_null_status_mismatch_rows = 0
         AND rq.debt_usd_exact_mismatch_rows = 0
         AND rq.collateral_usd_exact_mismatch_rows = 0
        THEN 'PASS_EXACT_RECONCILIATION'
        ELSE 'REVIEW_DIFFERENCES'
    END AS step6_reconciliation_status

FROM model_profile mp
CROSS JOIN borrow_profile bp
CROSS JOIN supply_profile sp
CROSS JOIN borrow_key_reconciliation bkr
CROSS JOIN supply_key_reconciliation skr
CROSS JOIN reconciliation_quality rq
CROSS JOIN max_debt_difference mdd
CROSS JOIN max_collateral_difference mcd;
