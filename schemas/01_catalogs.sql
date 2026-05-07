-- ============================================================
-- SCHEMA: catalogs
-- Shared reference tables used across all modules
-- ============================================================

CREATE SCHEMA IF NOT EXISTS catalogs;
SET search_path TO catalogs;

-- Document types
CREATE TABLE document_type (
    code        CHAR(3)         PRIMARY KEY,  -- 'DUI', 'PAS', 'RES', 'MIN'
    description VARCHAR(50)     NOT NULL,
    active      BOOLEAN         NOT NULL DEFAULT TRUE
);

INSERT INTO document_type VALUES
    ('DUI', 'National Identity Document',   TRUE),
    ('PAS', 'Passport',                     TRUE),
    ('RES', 'Resident Card',                TRUE),
    ('MIN', 'Minor Identity Card',          TRUE);

-- General status catalog (reusable across all modules)
CREATE TABLE status (
    code        CHAR(3)         PRIMARY KEY,  -- 'ACT', 'INA', 'BLO', 'CAN', 'DEC'
    description VARCHAR(50)     NOT NULL,
    active      BOOLEAN         NOT NULL DEFAULT TRUE
);

INSERT INTO status VALUES
    ('ACT', 'Active',       TRUE),
    ('INA', 'Inactive',     TRUE),
    ('BLO', 'Blocked',      TRUE),
    ('CAN', 'Cancelled',    TRUE),
    ('DEC', 'Deceased',     TRUE);

-- Account types
CREATE TABLE account_type (
    code        CHAR(3)         PRIMARY KEY,  -- 'SAV', 'CHK', 'CRD'
    description VARCHAR(50)     NOT NULL,
    active      BOOLEAN         NOT NULL DEFAULT TRUE
);

INSERT INTO account_type VALUES
    ('SAV', 'Savings Account',      TRUE),
    ('CHK', 'Checking Account',     TRUE),
    ('CRD', 'Credit Account',       TRUE);

-- Card types
CREATE TABLE card_type (
    code        CHAR(3)         PRIMARY KEY,  -- 'CRD', 'DEB'
    description VARCHAR(50)     NOT NULL,
    active      BOOLEAN         NOT NULL DEFAULT TRUE
);

INSERT INTO card_type VALUES
    ('CRD', 'Credit Card',  TRUE),
    ('DEB', 'Debit Card',   TRUE);

-- Address types
CREATE TABLE address_type (
    code        CHAR(3)         PRIMARY KEY,  -- 'RES', 'WRK', 'MAI'
    description VARCHAR(50)     NOT NULL,
    active      BOOLEAN         NOT NULL DEFAULT TRUE
);

INSERT INTO address_type VALUES
    ('RES', 'Residence',        TRUE),
    ('WRK', 'Workplace',        TRUE),
    ('MAI', 'Mailing Address',  TRUE);

-- Transaction origins
CREATE TABLE transaction_origin (
    code        CHAR(3)         PRIMARY KEY,  -- 'POS', 'ATM', 'BRN', 'WEB', 'APP'
    description VARCHAR(50)     NOT NULL,
    active      BOOLEAN         NOT NULL DEFAULT TRUE
);

INSERT INTO transaction_origin VALUES
    ('POS', 'Point of Sale',        TRUE),
    ('ATM', 'ATM Withdrawal',       TRUE),
    ('BRN', 'Bank Branch',          TRUE),
    ('WEB', 'Online Purchase',      TRUE),
    ('APP', 'Mobile Application',   TRUE);

-- Transaction types
CREATE TABLE transaction_type (
    code        CHAR(3)         PRIMARY KEY,  -- 'PUR', 'WIT', 'REV', 'PAY', 'ADJ'
    description VARCHAR(50)     NOT NULL,
    active      BOOLEAN         NOT NULL DEFAULT TRUE
);

INSERT INTO transaction_type VALUES
    ('PUR', 'Purchase',     TRUE),
    ('WIT', 'Withdrawal',   TRUE),
    ('REV', 'Reversal',     TRUE),
    ('PAY', 'Payment',      TRUE),
    ('ADJ', 'Adjustment',   TRUE);