-- ============================================================
-- SCHEMA: transactions
-- Card transactions, reversals and audit
-- ============================================================

CREATE SCHEMA IF NOT EXISTS transactions;
SET search_path TO transactions;

-- Core transaction table
CREATE TABLE card_transaction (
    id                  SERIAL          PRIMARY KEY,
    card_id             INT             NOT NULL REFERENCES cards.card(id),
    account_id          INT             NOT NULL REFERENCES cards.account(id),
    transaction_type    CHAR(3)         NOT NULL REFERENCES catalogs.transaction_type(code),
    origin              CHAR(3)         NOT NULL REFERENCES catalogs.transaction_origin(code),
    amount              DECIMAL(12,2)   NOT NULL CHECK (amount > 0),
    currency            CHAR(3)         NOT NULL DEFAULT 'USD',
    status              CHAR(3)         NOT NULL DEFAULT 'ACT' REFERENCES catalogs.status(code),
    -- Merchant info
    merchant_name       VARCHAR(200),
    merchant_city       VARCHAR(100),
    merchant_country    CHAR(3),
    merchant_category   VARCHAR(10),     -- MCC code
    -- Location
    latitude            DECIMAL(9,6),
    longitude           DECIMAL(9,6),
    -- Authorization
    authorization_code  VARCHAR(20),
    is_international    BOOLEAN         NOT NULL DEFAULT FALSE,
    -- Raw payload from payment processor (ISO 8583 / JSON)
    raw_payload         JSONB,
    -- Audit
    created_by          VARCHAR(50)     NOT NULL DEFAULT 'SYSTEM',
    created_at          TIMESTAMP       NOT NULL DEFAULT NOW()
);

-- Transaction history (immutable log — no updates allowed)
CREATE TABLE card_transaction_history (
    id                  SERIAL          PRIMARY KEY,
    transaction_id      INT             NOT NULL,
    card_id             INT             NOT NULL,
    account_id          INT             NOT NULL,
    transaction_type    CHAR(3)         NOT NULL,
    origin              CHAR(3)         NOT NULL,
    amount              DECIMAL(12,2)   NOT NULL,
    currency            CHAR(3)         NOT NULL,
    status              CHAR(3)         NOT NULL,
    merchant_name       VARCHAR(200),
    merchant_city       VARCHAR(100),
    merchant_country    CHAR(3),
    merchant_category   VARCHAR(10),
    authorization_code  VARCHAR(20),
    is_international    BOOLEAN         NOT NULL,
    raw_payload         JSONB,
    created_by          VARCHAR(50)     NOT NULL,
    created_at          TIMESTAMP       NOT NULL,
    -- History metadata
    recorded_at         TIMESTAMP       NOT NULL DEFAULT NOW(),
    recorded_by         VARCHAR(50)     NOT NULL DEFAULT 'SYSTEM',
    operation           CHAR(1)         NOT NULL CHECK (operation IN ('U', 'D'))
);

-- Reversal (links back to original transaction)
CREATE TABLE transaction_reversal (
    id                      SERIAL          PRIMARY KEY,
    original_transaction_id INT             NOT NULL REFERENCES card_transaction(id),
    reversal_transaction_id INT             NOT NULL REFERENCES card_transaction(id),
    reason                  TEXT            NOT NULL,
    reversed_by             VARCHAR(50)     NOT NULL,
    reversed_at             TIMESTAMP       NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_reversal UNIQUE (original_transaction_id)
);

-- Duplicate detection log
CREATE TABLE duplicate_transaction_log (
    id                      SERIAL          PRIMARY KEY,
    transaction_id          INT             NOT NULL REFERENCES card_transaction(id),
    duplicate_of            INT             NOT NULL REFERENCES card_transaction(id),
    detected_at             TIMESTAMP       NOT NULL DEFAULT NOW(),
    resolved                BOOLEAN         NOT NULL DEFAULT FALSE,
    resolved_by             VARCHAR(50),
    resolved_at             TIMESTAMP
);

-- ============================================================
-- TRIGGER: auto-history on transaction UPDATE or DELETE
-- ============================================================

CREATE OR REPLACE FUNCTION fn_transaction_history()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO transactions.card_transaction_history (
        transaction_id, card_id, account_id,
        transaction_type, origin, amount, currency, status,
        merchant_name, merchant_city, merchant_country, merchant_category,
        authorization_code, is_international, raw_payload,
        created_by, created_at,
        operation
    ) VALUES (
        OLD.id, OLD.card_id, OLD.account_id,
        OLD.transaction_type, OLD.origin, OLD.amount, OLD.currency, OLD.status,
        OLD.merchant_name, OLD.merchant_city, OLD.merchant_country, OLD.merchant_category,
        OLD.authorization_code, OLD.is_international, OLD.raw_payload,
        OLD.created_by, OLD.created_at,
        TG_OP
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_transaction_history
BEFORE UPDATE OR DELETE ON transactions.card_transaction
FOR EACH ROW EXECUTE FUNCTION fn_transaction_history();

-- ============================================================
-- FUNCTION: calculate real-time balance
-- balance = last statement closing_balance + transactions since cutoff
-- ============================================================

CREATE OR REPLACE FUNCTION fn_get_realtime_balance(p_account_id INT)
RETURNS DECIMAL(12,2) AS $$
DECLARE
    v_last_statement_balance    DECIMAL(12,2) := 0;
    v_last_cutoff_date          DATE;
    v_transactions_since        DECIMAL(12,2) := 0;
BEGIN
    -- Get last statement balance
    SELECT closing_balance, cutoff_date
    INTO v_last_statement_balance, v_last_cutoff_date
    FROM cards.account_statement
    WHERE account_id = p_account_id
    ORDER BY cutoff_date DESC
    LIMIT 1;

    -- If no statement exists yet, balance starts at 0
    IF v_last_cutoff_date IS NULL THEN
        v_last_cutoff_date := '1900-01-01';
        v_last_statement_balance := 0;
    END IF;

    -- Sum transactions since last cutoff
    SELECT COALESCE(SUM(
        CASE
            WHEN t.transaction_type IN ('PUR', 'WIT') THEN t.amount   -- debits
            WHEN t.transaction_type IN ('PAY', 'REV') THEN -t.amount  -- credits
            ELSE 0
        END
    ), 0)
    INTO v_transactions_since
    FROM transactions.card_transaction t
    WHERE t.account_id = p_account_id
      AND t.created_at > v_last_cutoff_date
      AND t.status = 'ACT';

    RETURN v_last_statement_balance + v_transactions_since;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- FUNCTION: authorize transaction
-- Validates limit, block status and duplicate detection
-- ============================================================

CREATE OR REPLACE FUNCTION fn_authorize_transaction(
    p_card_id           INT,
    p_amount            DECIMAL(12,2),
    p_transaction_type  CHAR(3),
    p_origin            CHAR(3),
    p_merchant_name     VARCHAR(200),
    p_authorization_code VARCHAR(20),
    p_raw_payload       JSONB
)
RETURNS TABLE (
    approved        BOOLEAN,
    rejection_code  VARCHAR(10),
    rejection_reason TEXT
) AS $$
DECLARE
    v_card          RECORD;
    v_account       RECORD;
    v_balance       DECIMAL(12,2);
    v_duplicate     INT;
BEGIN
    -- 1. Get card and validate status
    SELECT c.*, cb.card_type
    INTO v_card
    FROM cards.card c
    JOIN cards.card_bin cb ON c.bin = cb.bin
    WHERE c.id = p_card_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'CARD_NF', 'Card not found';
        RETURN;
    END IF;

    IF v_card.status != 'ACT' THEN
        RETURN QUERY SELECT FALSE, 'CARD_INACT', 'Card is not active: ' || v_card.status;
        RETURN;
    END IF;

    -- 2. Check active block
    IF EXISTS (
        SELECT 1 FROM cards.card_block
        WHERE card_id = p_card_id AND active = TRUE
    ) THEN
        RETURN QUERY SELECT FALSE, 'CARD_BLK', 'Card is currently blocked';
        RETURN;
    END IF;

    -- 3. Get account
    SELECT * INTO v_account
    FROM cards.account
    WHERE id = v_card.account_id;

    -- 4. For credit cards: validate limit
    IF v_card.card_type = 'CRD' AND p_transaction_type = 'PUR' THEN
        v_balance := fn_get_realtime_balance(v_account.id);
        IF v_balance + p_amount > v_account.credit_limit THEN
            RETURN QUERY SELECT FALSE, 'INSUF_LIM', 'Insufficient credit limit';
            RETURN;
        END IF;
    END IF;

    -- 5. Duplicate detection (same card, amount, merchant, last 5 minutes)
    SELECT id INTO v_duplicate
    FROM transactions.card_transaction
    WHERE card_id = p_card_id
      AND amount = p_amount
      AND merchant_name = p_merchant_name
      AND authorization_code = p_authorization_code
      AND created_at > NOW() - INTERVAL '5 minutes'
    LIMIT 1;

    IF v_duplicate IS NOT NULL THEN
        RETURN QUERY SELECT FALSE, 'DUPLICATE', 'Duplicate transaction detected';
        RETURN;
    END IF;

    -- 6. All checks passed — insert transaction
    INSERT INTO transactions.card_transaction (
        card_id, account_id, transaction_type, origin,
        amount, currency, status,
        merchant_name, authorization_code,
        is_international, raw_payload,
        created_by
    ) VALUES (
        p_card_id, v_account.id, p_transaction_type, p_origin,
        p_amount, v_account.currency, 'ACT',
        p_merchant_name, p_authorization_code,
        FALSE, p_raw_payload,
        'SYSTEM'
    );

    RETURN QUERY SELECT TRUE, 'APPROVED', 'Transaction authorized successfully';
END;
$$ LANGUAGE plpgsql;