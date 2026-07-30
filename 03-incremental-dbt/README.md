Uniswap V3 Incremental Fees and Revenue

This trade-level table serves engineering and product teams. They can run daily incremental updates, bounded historical backfills, row-level audits, and data-quality checks for Ethereum Uniswap V3 fees, protocol revenue, and supply-side fees.

What this measures

Each (tx_hash, evt_index) row stores fee base, fee tier, active token-side divisor, fees, revenue, supply-side fees, and repair reason. Amounts use DECIMAL(38,18). Validation covers UTC [2026-06-14, 2026-07-14). The observed 3,105,887 rows produced fees of 7,437,623.041819 USD, revenue of 1,417,343.393348 USD, supply-side fees of 6,020,279.648471 USD, and a 0.000000 USD accounting residual.

Methodology

incremental_model.sql replaces the latest three complete UTC dates. Logic changes require a full refresh; older issues use bounded backfills. Shared formulas live in fee_logic_macro.sql. Dune 8127229 rebuilt the full table with zero key, field, or USD differences. Dune 8127558 confirmed same-snapshot baseline parity.

Known limitations

Unpriced rows remain visible but add zero USD. Late updates outside the overlap require a backfill. Five Dune Medium runs per model gave full-window/three-date medians of 8/10 seconds: -25.0000% speedup, so the 50.0000% target was not met. Selected trade rows fell 90.8277%; this is not a scanned-byte measurement.

Full evidence: benchmark.csv and optimization_notes.md.
