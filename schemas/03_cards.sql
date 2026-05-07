-- ============================================================
-- SCHEMA: cards
-- Card issuers, BIN, accounts, cards and blocks
-- ============================================================

CREATE SCHEMA IF NOT EXISTS cards;
SET search_path TO cards;

-- Card issuers (Visa, Mastercard, etc.)
CREATE TABLE card_issuer (
    id              SERIAL          PRIMARY KEY,
    name            VARCHAR(100)    NOT NULL,
    country         CHAR(3)         NOT NULL DEFAULT 'SLV',
    status          CHAR(3)         NOT NULL DEFAULT 'ACT' REFERENCES catalogs.status(code),
    created_by      VARCHAR(50)     NOT NULL,
    created_at      TIMESTAMP       NOT NULL DEFAULT NOW()
);

-- BIN (Bank Identification Number)
-- First 6 digits of a card number identify issuer and card type
CREATE TABLE card_bin (
    bin             CHAR(6)         PRIMARY KEY,
    issuer_id       INT             NOT NULL REFERENCES card_issuer(id),
    card_type       CHAR(3)         NOT NULL REFERENCES catalogs.card_type(code),
    description     VARCHAR(100),
    active          BOOLEAN         NOT NULL DEFAULT TRUE
);

-- Account (links a person to a financial product)
CREATE TABLE account (
    id              SERIAL          PRIMARY KEY,
    account_number  VARCHAR(20)     NOT NULL UNIQUE,
    person_id       INT             NOT NULL REFERENCES party.person(id),
    account_type    CHAR(3)         NOT NULL REFERENCES catalogs.account_type(code),
    currency        CHAR(3)         NOT NULL DEFAULT 'USD',
    credit_limit    DECIMAL(12,2),  -- only for credit accounts
    status          CHAR(3)         NOT NULL DEFAULT 'ACT' REFERENCES catalogs.status(code),
    created_by      VARCHAR(50)     NOT NULL,
    created_at      TIMESTAMP       NOT NULL DEFAULT NOW(),
    updated_by      VARCHAR(50),
    updated_at      TIMESTAMP,
    deactivated_by  VARCHAR(50),
    deactivated_at  TIMESTAMP,
    deactivation_reason TEXT
);

-- Account history
CREATE TABLE account_history (
    id              SERIAL          PRIMARY KEY,
    account_id      INT             NOT NULL,
    account_number  VARCHAR(20)     NOT NULL,
    person_id       INT             NOT NULL,
    account_type    CHAR(3)         NOT NULL,
    currency        CHAR(3)         NOT NULL,
    credit_limit    DECIMAL(12,2),
    status          CHAR(3)         NOT NULL,
    created_by      VARCHAR(50)     NOT NULL,
    created_at      TIMESTAMP       NOT NULL,
    updated_by      VARCHAR(50),
    updated_at      TIMESTAMP,
    deactivated_by  VARCHAR(50),
    deactivated_at  TIMESTAMP,
    deactivation_reason TEXT,
    -- History metadata
    recorded_at     TIMESTAMP       NOT NULL DEFAULT NOW(),
    recorded_by     VARCHAR(50)     NOT NULL DEFAULT 'SYSTEM',
    operation       CHAR(1)         NOT NULL CHECK (operation IN ('U', 'D'))
);

-- Card request (before approval)
CREATE TABLE card_request (
    id              SERIAL          PRIMARY KEY,
    account_id      INT             NOT NULL REFERENCES account(id),
    card_type       CHAR(3)         NOT NULL REFERENCES catalogs.card_type(code),
    is_additional   BOOLEAN         NOT NULL DEFAULT FALSE,
    requested_by    VARCHAR(50)     NOT NULL,
    requested_at    TIMESTAMP       NOT NULL DEFAULT NOW(),
    reviewed_by     VARCHAR(50),
    reviewed_at     TIMESTAMP,
    status          CHAR(3)         NOT NULL DEFAULT 'ACT' REFERENCES catalogs.status(code),
    rejection_reason TEXT
);

-- Card (issued after approval)
CREATE TABLE card (
    id              SERIAL          PRIMARY KEY,
    account_id      INT             NOT NULL REFERENCES account(id),
    request_id      INT             NOT NULL REFERENCES card_request(id),
    bin             CHAR(6)         NOT NULL REFERENCES card_bin(bin),
    card_number     VARCHAR(19)     NOT NULL UNIQUE, -- masked: 4111-****-****-1111
    cardholder_name VARCHAR(100)    NOT NULL,
    expiry_month    CHAR(2)         NOT NULL,
    expiry_year     CHAR(4)         NOT NULL,
    is_additional   BOOLEAN         NOT NULL DEFAULT FALSE,
    status          CHAR(3)         NOT NULL DEFAULT 'ACT' REFERENCES catalogs.status(code),
    created_by      VARCHAR(50)     NOT NULL,
    created_at      TIMESTAMP       NOT NULL DEFAULT NOW(),
    updated_by      VARCHAR(50),
    updated_at      TIMESTAMP
);

-- Card history
CREATE TABLE card_history (
    id              SERIAL          PRIMARY KEY,
    card_id         INT             NOT NULL,
    account_id      INT             NOT NULL,
    card_number     VARCHAR(19)     NOT NULL,
    cardholder_name VARCHAR(100)    NOT NULL,
    expiry_month    CHAR(2)         NOT NULL,
    expiry_year     CHAR(4)         NOT NULL,
    is_additional   BOOLEAN         NOT NULL,
    status          CHAR(3)         NOT NULL,
    created_by      VARCHAR(50)     NOT NULL,
    created_at      TIMESTAMP       NOT NULL,
    updated_by      VARCHAR(50),
    updated_at      TIMESTAMP,
    -- History metadata
    recorded_at     TIMESTAMP       NOT NULL DEFAULT NOW(),
    recorded_by     VARCHAR(50)     NOT NULL DEFAULT 'SYSTEM',
    operation       CHAR(1)         NOT NULL CHECK (operation IN ('U', 'D'))
);

-- Card block (reason and who blocked it)
CREATE TABLE card_block (
    id              SERIAL          PRIMARY KEY,
    card_id         INT             NOT NULL REFERENCES card(id),
    block_reason    TEXT            NOT NULL,
    blocked_by      VARCHAR(50)     NOT NULL,
    blocked_at      TIMESTAMP       NOT NULL DEFAULT NOW(),
    unblocked_by    VARCHAR(50),
    unblocked_at    TIMESTAMP,
    unblock_reason  TEXT,
    active          BOOLEAN         NOT NULL DEFAULT TRUE
);

-- Statement balance (calculated at cutoff, not real-time)
-- Real-time balance = last statement balance + transactions since cutoff
CREATE TABLE account_statement (
    id              SERIAL          PRIMARY KEY,
    account_id      INT             NOT NULL REFERENCES account(id),
    cutoff_date     DATE            NOT NULL,
    opening_balance DECIMAL(12,2)   NOT NULL DEFAULT 0,
    closing_balance DECIMAL(12,2)   NOT NULL DEFAULT 0,
    minimum_payment DECIMAL(12,2),
    payment_due_date DATE,
    generated_by    VARCHAR(50)     NOT NULL DEFAULT 'SYSTEM',
    generated_at    TIMESTAMP       NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_account_cutoff UNIQUE (account_id, cutoff_date)
);

-- Travel report (card authorized for international use)
CREATE TABLE card_travel_report (
    id              SERIAL          PRIMARY KEY,
    card_id         INT             NOT NULL REFERENCES card(id),
    departure_date  DATE            NOT NULL,
    return_date     DATE            NOT NULL,
    countries       TEXT[]          NOT NULL, -- array of country codes
    reported_by     VARCHAR(50)     NOT NULL,
    reported_at     TIMESTAMP       NOT NULL DEFAULT NOW(),
    status          CHAR(3)         NOT NULL DEFAULT 'ACT' REFERENCES catalogs.status(code),
    CONSTRAINT chk_travel_dates CHECK (return_date > departure_date)
);

-- ============================================================
-- TRIGGERS: auto-history on account and card changes
-- ============================================================

CREATE OR REPLACE FUNCTION fn_account_history()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO cards.account_history (
        account_id, account_number, person_id, account_type,
        currency, credit_limit, status,
        created_by, created_at, updated_by, updated_at,
        deactivated_by, deactivated_at, deactivation_reason,
        operation
    ) VALUES (
        OLD.id, OLD.account_number, OLD.person_id, OLD.account_type,
        OLD.currency, OLD.credit_limit, OLD.status,
        OLD.created_by, OLD.created_at, OLD.updated_by, OLD.updated_at,
        OLD.deactivated_by, OLD.deactivated_at, OLD.deactivation_reason,
        TG_OP
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_account_history
BEFORE UPDATE OR DELETE ON cards.account
FOR EACH ROW EXECUTE FUNCTION fn_account_history();

CREATE OR REPLACE FUNCTION fn_card_history()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO cards.card_history (
        card_id, account_id, card_number, cardholder_name,
        expiry_month, expiry_year, is_additional, status,
        created_by, created_at, updated_by, updated_at,
        operation
    ) VALUES (
        OLD.id, OLD.account_id, OLD.card_number, OLD.cardholder_name,
        OLD.expiry_month, OLD.expiry_year, OLD.is_additional, OLD.status,
        OLD.created_by, OLD.created_at, OLD.updated_by, OLD.updated_at,
        TG_OP
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_card_history
BEFORE UPDATE OR DELETE ON cards.card
FOR EACH ROW EXECUTE FUNCTION fn_card_history();