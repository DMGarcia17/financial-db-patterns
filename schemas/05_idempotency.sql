-- ============================================================
-- SCHEMA: transactions
-- Idempotency layer for card transaction processing
--
-- Problem this solves:
-- A POS terminal may retry the same request multiple times due
-- to network timeouts. Without idempotency, each retry would
-- create a duplicate transaction. This module implements the
-- two-phase commit pattern:
--   1. Request a token before processing
--   2. Submit transaction with that token
--   3. Retries with the same token return the original result
-- ============================================================

SET search_path TO transactions;

-- Transaction token (requested by POS before submitting)
CREATE TABLE transaction_token (
    token               UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    card_id             INT             NOT NULL REFERENCES cards.card(id),
    expected_amount     DECIMAL(12,2),  -- optional: lock token to a specific amount
    requested_at        TIMESTAMP       NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMP       NOT NULL DEFAULT NOW() + INTERVAL '10 minutes',
    used                BOOLEAN         NOT NULL DEFAULT FALSE,
    used_at             TIMESTAMP,
    -- Stored result for idempotent replay
    result_approved     BOOLEAN,
    result_code         VARCHAR(10),
    result_reason       TEXT,
    result_transaction_id INT           REFERENCES card_transaction(id)
);

-- ============================================================
-- FUNCTION: request a transaction token
-- Called by POS before submitting a transaction
-- ============================================================

CREATE OR REPLACE FUNCTION fn_request_token(
    p_card_id           INT,
    p_expected_amount   DECIMAL(12,2) DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_token UUID;
BEGIN
    -- Validate card exists and is active
    IF NOT EXISTS (
        SELECT 1 FROM cards.card
        WHERE id = p_card_id AND status = 'ACT'
    ) THEN
        RAISE EXCEPTION 'Card % is not active or does not exist', p_card_id;
    END IF;

    INSERT INTO transactions.transaction_token (
        card_id,
        expected_amount
    ) VALUES (
        p_card_id,
        p_expected_amount
    )
    RETURNING token INTO v_token;

    RETURN v_token;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- FUNCTION: validate and consume token
-- Returns the stored result if already used (idempotent replay)
-- Returns NULL if token is valid and ready to use
-- Raises exception if token is invalid or expired
-- ============================================================

CREATE OR REPLACE FUNCTION fn_consume_token(
    p_token             UUID,
    p_card_id           INT,
    p_amount            DECIMAL(12,2)
)
RETURNS TABLE (
    is_replay           BOOLEAN,
    result_approved     BOOLEAN,
    result_code         VARCHAR(10),
    result_reason       TEXT,
    result_transaction_id INT
) AS $$
DECLARE
    v_token RECORD;
BEGIN
    SELECT * INTO v_token
    FROM transactions.transaction_token
    WHERE token = p_token;

    -- Token not found
    IF NOT FOUND THEN
        RAISE EXCEPTION 'INVALID_TOKEN: Token % does not exist', p_token;
    END IF;

    -- Token belongs to different card
    IF v_token.card_id != p_card_id THEN
        RAISE EXCEPTION 'TOKEN_MISMATCH: Token does not belong to card %', p_card_id;
    END IF;

    -- Token expired
    IF v_token.expires_at < NOW() AND NOT v_token.used THEN
        RAISE EXCEPTION 'TOKEN_EXPIRED: Token % expired at %', p_token, v_token.expires_at;
    END IF;

    -- Amount mismatch (if token was locked to a specific amount)
    IF v_token.expected_amount IS NOT NULL AND v_token.expected_amount != p_amount THEN
        RAISE EXCEPTION 'AMOUNT_MISMATCH: Token was locked to amount %, got %',
            v_token.expected_amount, p_amount;
    END IF;

    -- Already used — idempotent replay
    IF v_token.used THEN
        RETURN QUERY SELECT
            TRUE,
            v_token.result_approved,
            v_token.result_code,
            v_token.result_reason,
            v_token.result_transaction_id;
        RETURN;
    END IF;

    -- Token is valid and unused
    RETURN QUERY SELECT FALSE, NULL::BOOLEAN, NULL::VARCHAR(10), NULL::TEXT, NULL::INT;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- FUNCTION: mark token as used and store result
-- Called after fn_authorize_transaction completes
-- ============================================================

CREATE OR REPLACE FUNCTION fn_mark_token_used(
    p_token                 UUID,
    p_approved              BOOLEAN,
    p_result_code           VARCHAR(10),
    p_result_reason         TEXT,
    p_result_transaction_id INT DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    UPDATE transactions.transaction_token SET
        used                    = TRUE,
        used_at                 = NOW(),
        result_approved         = p_approved,
        result_code             = p_result_code,
        result_reason           = p_result_reason,
        result_transaction_id   = p_result_transaction_id
    WHERE token = p_token;
END;
$$ LANGUAGE plpgsql;