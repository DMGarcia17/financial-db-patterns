-- ============================================================
-- Exercise 02b — Materialized View for Account Balance
--
-- Problem: fn_get_realtime_balance is called twice per account
-- in the risk report query (Exercise 02), and would be called
-- on every query execution for all accounts.
--
-- Solution: Pre-compute balances into a materialized view,
-- refreshed nightly after the statement cutoff batch runs.
-- The collections team works with yesterday's closing data anyway.
--
-- Tradeoff: Data is as fresh as the last REFRESH. For real-time
-- balance (e.g. ATM authorization), always call fn_get_realtime_balance
-- directly — never read from this view.
-- ============================================================

-- Create the materialized view
CREATE MATERIALIZED VIEW cards.mv_account_balance AS
SELECT
    a.id                                                                AS account_id,
    a.account_number,
    a.credit_limit,
    transactions.fn_get_realtime_balance(a.id)                         AS current_balance,
    ROUND(
            transactions.fn_get_realtime_balance(a.id) /
            NULLIF(a.credit_limit, 0) * 100
        , 2)                                                                AS usage_percent,
    a.credit_limit - transactions.fn_get_realtime_balance(a.id)        AS available_credit,
    NOW()                                                               AS computed_at
FROM cards.account a
WHERE a.account_type = 'CRD'
  AND a.status       = 'ACT'
  AND a.credit_limit > 0;

-- Unique index required for CONCURRENTLY refresh
CREATE UNIQUE INDEX ON cards.mv_account_balance(account_id);

-- Index for the most common query pattern — risk reports sorted by usage
CREATE INDEX ON cards.mv_account_balance(usage_percent DESC);

-- ============================================================
-- Refresh strategy
-- ============================================================

-- Standard refresh (blocks reads during refresh — avoid in production)
-- REFRESH MATERIALIZED VIEW cards.mv_account_balance;

-- Production refresh (concurrent — readers are not blocked)
-- Requires the unique index above
-- REFRESH MATERIALIZED VIEW CONCURRENTLY cards.mv_account_balance;

-- With pg_cron installed, schedule nightly at 11pm:
-- SELECT cron.schedule(
--     'refresh-mv-account-balance',
--     '0 23 * * *',
--     'REFRESH MATERIALIZED VIEW CONCURRENTLY cards.mv_account_balance'
-- );

-- ============================================================
-- Exercise 02 rewritten using the materialized view
-- Runs instantly regardless of account count
-- ============================================================

SELECT
    c.cardholder_name,
    mv.account_number,
    mv.credit_limit,
    mv.current_balance,
    mv.available_credit,
    mv.usage_percent,
    CASE
        WHEN mv.usage_percent >= 90 THEN 'HIGH'
        WHEN mv.usage_percent >= 70 THEN 'MEDIUM'
        END                                         AS risk_level,
    mv.computed_at
FROM cards.mv_account_balance mv
         INNER JOIN cards.card c ON mv.account_id = c.account_id
WHERE mv.usage_percent >= 70
  AND c.status = 'ACT'
ORDER BY mv.usage_percent DESC;