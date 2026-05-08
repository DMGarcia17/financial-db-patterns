-- ============================================================
-- SEED DATA
-- Fictional but realistic test data for development
-- All persons, cards and transactions are completely fictitious
-- ============================================================

SET search_path TO party, cards, transactions, catalogs;

-- ============================================================
-- PARTY — Persons
-- ============================================================

INSERT INTO party.person (
    first_name, middle_name, first_surname, second_surname,
    birth_date, gender, status, created_by
) VALUES
    ('Carlos',  'Eduardo',  'Morales',  'Rivera',   '1985-03-15', 'M', 'ACT', 'SYSTEM'),
    ('Ana',     'Patricia', 'Gutierrez','Lopez',    '1990-07-22', 'F', 'ACT', 'SYSTEM'),
    ('Roberto', NULL,       'Hernandez','Martinez', '1978-11-08', 'M', 'ACT', 'SYSTEM'),
    ('Maria',   'Jose',     'Flores',   'de Paz',   '1995-01-30', 'F', 'BLO', 'SYSTEM');

-- Documents
INSERT INTO party.person_document (
    person_id, document_type, document_number,
    issue_date, expiry_date, is_primary, created_by
) VALUES
    (1, 'DUI', '01234567-8', '2015-01-10', '2025-01-10', TRUE,  'SYSTEM'),
    (2, 'DUI', '09876543-2', '2018-05-20', '2028-05-20', TRUE,  'SYSTEM'),
    (2, 'PAS', 'A12345678',  '2020-03-15', '2030-03-15', FALSE, 'SYSTEM'),
    (3, 'DUI', '05555555-5', '2010-08-01', '2020-08-01', TRUE,  'SYSTEM'),
    (4, 'DUI', '07777777-7', '2019-11-25', '2029-11-25', TRUE,  'SYSTEM');

-- Emails
INSERT INTO party.person_email (
    person_id, email, is_primary, created_by
) VALUES
    (1, 'carlos.morales@email.com',   TRUE,  'SYSTEM'),
    (2, 'ana.gutierrez@email.com',    TRUE,  'SYSTEM'),
    (2, 'ana.work@company.com',       FALSE, 'SYSTEM'),
    (3, 'roberto.hernandez@email.com',TRUE,  'SYSTEM'),
    (4, 'maria.flores@email.com',     TRUE,  'SYSTEM');

-- Phones
INSERT INTO party.person_phone (
    person_id, country_code, phone_number, is_primary, created_by
) VALUES
    (1, '+503', '7111-1111', TRUE,  'SYSTEM'),
    (2, '+503', '7222-2222', TRUE,  'SYSTEM'),
    (2, '+503', '7222-3333', FALSE, 'SYSTEM'),
    (3, '+503', '7333-3333', TRUE,  'SYSTEM'),
    (4, '+503', '7444-4444', TRUE,  'SYSTEM');

-- Addresses
INSERT INTO party.person_address (
    person_id, address_type, line1, city,
    state_province, is_mailing, created_by
) VALUES
    (1, 'RES', 'Col. Escalon, Calle El Mirador #45',  'San Salvador', 'San Salvador', TRUE,  'SYSTEM'),
    (2, 'RES', 'Res. Santa Elena, Pje. Los Pinos #12','Antiguo Cuscatlan', 'La Libertad', TRUE, 'SYSTEM'),
    (2, 'WRK', 'World Trade Center, Torre 1, Of. 305', 'San Salvador', 'San Salvador', FALSE, 'SYSTEM'),
    (3, 'RES', 'Col. San Benito, Calle Las Magnolias', 'San Salvador', 'San Salvador', TRUE,  'SYSTEM'),
    (4, 'RES', 'Urb. Madre Selva, Calle Principal #8', 'Santa Tecla',  'La Libertad', TRUE,  'SYSTEM');

-- ============================================================
-- CARDS — Issuers, BINs, Accounts, Cards
-- ============================================================

INSERT INTO cards.card_issuer (name, country, created_by) VALUES
    ('Visa International',      'USA', 'SYSTEM'),
    ('Mastercard Worldwide',    'USA', 'SYSTEM');

INSERT INTO cards.card_bin (bin, issuer_id, card_type, description) VALUES
    ('411111', 1, 'CRD', 'Visa Credit Classic'),
    ('412345', 1, 'DEB', 'Visa Debit Standard'),
    ('512345', 2, 'CRD', 'Mastercard Credit Gold'),
    ('524000', 2, 'DEB', 'Mastercard Debit Standard');

-- Accounts
INSERT INTO cards.account (
    account_number, person_id, account_type,
    currency, credit_limit, status, created_by
) VALUES
    ('ACC-0001-2024', 1, 'CRD', 'USD', 5000.00,  'ACT', 'SYSTEM'),
    ('ACC-0002-2024', 2, 'CRD', 'USD', 10000.00, 'ACT', 'SYSTEM'),
    ('ACC-0003-2024', 3, 'SAV', 'USD', NULL,      'ACT', 'SYSTEM'),
    ('ACC-0004-2024', 4, 'CRD', 'USD', 3000.00,  'BLO', 'SYSTEM');

-- Card requests
INSERT INTO cards.card_request (
    account_id, card_type, is_additional,
    requested_by, reviewed_by, reviewed_at, status
) VALUES
    (1, 'CRD', FALSE, 'AGENT_01', 'SUPERVISOR_01', NOW() - INTERVAL '30 days', 'ACT'),
    (2, 'CRD', FALSE, 'AGENT_01', 'SUPERVISOR_01', NOW() - INTERVAL '60 days', 'ACT'),
    (2, 'CRD', TRUE,  'AGENT_02', 'SUPERVISOR_01', NOW() - INTERVAL '45 days', 'ACT'),
    (3, 'DEB', FALSE, 'AGENT_02', 'SUPERVISOR_02', NOW() - INTERVAL '90 days', 'ACT'),
    (4, 'CRD', FALSE, 'AGENT_01', 'SUPERVISOR_02', NOW() - INTERVAL '20 days', 'BLO');

-- Cards
INSERT INTO cards.card (
    account_id, request_id, bin,
    card_number, cardholder_name,
    expiry_month, expiry_year,
    is_additional, status, created_by
) VALUES
    (1, 1, '411111', '4111-****-****-1001', 'CARLOS E MORALES',   '12', '2027', FALSE, 'ACT', 'SYSTEM'),
    (2, 2, '512345', '5123-****-****-2001', 'ANA P GUTIERREZ',    '06', '2026', FALSE, 'ACT', 'SYSTEM'),
    (2, 3, '512345', '5123-****-****-2002', 'ANA P GUTIERREZ',    '06', '2026', TRUE,  'ACT', 'SYSTEM'),
    (3, 4, '412345', '4123-****-****-3001', 'ROBERTO HERNANDEZ',  '09', '2028', FALSE, 'ACT', 'SYSTEM'),
    (4, 5, '411111', '4111-****-****-4001', 'MARIA J FLORES',     '03', '2026', FALSE, 'BLO', 'SYSTEM');

-- Block on card 5 (Maria's blocked card)
INSERT INTO cards.card_block (
    card_id, block_reason, blocked_by
) VALUES (5, 'Suspicious activity detected — pending investigation', 'FRAUD_TEAM');

-- Statement for account 1 (last month cutoff)
INSERT INTO cards.account_statement (
    account_id, cutoff_date, opening_balance,
    closing_balance, minimum_payment, payment_due_date, generated_by
) VALUES
    (1, CURRENT_DATE - INTERVAL '30 days', 0.00, 1250.00, 125.00, CURRENT_DATE - INTERVAL '15 days', 'SYSTEM'),
    (2, CURRENT_DATE - INTERVAL '30 days', 0.00, 3400.00, 340.00, CURRENT_DATE - INTERVAL '15 days', 'SYSTEM');

-- Travel report for Ana (card 2, traveling to USA and Mexico)
INSERT INTO cards.card_travel_report (
    card_id, departure_date, return_date,
    countries, reported_by
) VALUES (
    2,
    CURRENT_DATE + INTERVAL '5 days',
    CURRENT_DATE + INTERVAL '15 days',
    ARRAY['USA', 'MEX'],
    'AGENT_01'
);

-- ============================================================
-- TRANSACTIONS
-- ============================================================

INSERT INTO transactions.card_transaction (
    card_id, account_id, transaction_type, origin,
    amount, currency, status,
    merchant_name, merchant_city, merchant_country, merchant_category,
    authorization_code, is_international, raw_payload, created_by
) VALUES
    -- Carlos (card 1) — normal purchases
    (1, 1, 'PUR', 'POS', 45.50,  'USD', 'ACT', 'WALMART SAN SALVADOR',  'San Salvador', 'SLV', '5411', 'AUTH000001', FALSE,
     '{"terminal_id": "T001", "rrn": "RRN000001"}'::jsonb, 'SYSTEM'),

    (1, 1, 'PUR', 'WEB', 120.00, 'USD', 'ACT', 'AMAZON',                'Seattle',      'USA', '5999', 'AUTH000002', TRUE,
     '{"terminal_id": "WEB01", "rrn": "RRN000002", "ip": "192.168.1.1"}'::jsonb, 'SYSTEM'),

    (1, 1, 'PUR', 'POS', 35.75,  'USD', 'ACT', 'DESPENSA FAMILIAR',     'San Salvador', 'SLV', '5411', 'AUTH000003', FALSE,
     '{"terminal_id": "T002", "rrn": "RRN000003"}'::jsonb, 'SYSTEM'),

    (1, 1, 'PAY', 'BRN', 500.00, 'USD', 'ACT', 'BANK BRANCH PAYMENT',   'San Salvador', 'SLV', NULL,   'AUTH000004', FALSE,
     '{"teller_id": "TELLER01", "rrn": "RRN000004"}'::jsonb, 'SYSTEM'),

    -- Ana (card 2) — mix of purchases and a reversal
    (2, 2, 'PUR', 'POS', 250.00, 'USD', 'ACT', 'SIMAN SAN SALVADOR',    'San Salvador', 'SLV', '5651', 'AUTH000005', FALSE,
     '{"terminal_id": "T003", "rrn": "RRN000005"}'::jsonb, 'SYSTEM'),

    (2, 2, 'PUR', 'APP', 89.99,  'USD', 'ACT', 'NETFLIX',               'Los Gatos',    'USA', '7841', 'AUTH000006', TRUE,
     '{"device_id": "APP001", "rrn": "RRN000006"}'::jsonb, 'SYSTEM'),

    (2, 2, 'REV', 'WEB', 250.00, 'USD', 'ACT', 'SIMAN SAN SALVADOR',    'San Salvador', 'SLV', '5651', 'AUTH000007', FALSE,
     '{"terminal_id": "T003", "rrn": "RRN000007", "original_rrn": "RRN000005"}'::jsonb, 'SYSTEM'),

    -- Ana (card 3 — additional card)
    (3, 2, 'PUR', 'POS', 75.00,  'USD', 'ACT', 'POLLO CAMPERO',         'San Salvador', 'SLV', '5812', 'AUTH000008', FALSE,
     '{"terminal_id": "T004", "rrn": "RRN000008"}'::jsonb, 'SYSTEM'),

    -- Roberto (card 4 — debit)
    (4, 3, 'WIT', 'ATM', 200.00, 'USD', 'ACT', 'ATM BANCO AGRICOLA',    'San Salvador', 'SLV', NULL,   'AUTH000009', FALSE,
     '{"atm_id": "ATM001", "rrn": "RRN000009"}'::jsonb, 'SYSTEM'),

    (4, 3, 'PUR', 'POS', 18.50,  'USD', 'ACT', 'METROCENTRO FOOD COURT','San Salvador', 'SLV', '5812', 'AUTH000010', FALSE,
     '{"terminal_id": "T005", "rrn": "RRN000010"}'::jsonb, 'SYSTEM');

-- Link the reversal to its original transaction
INSERT INTO transactions.transaction_reversal (
    original_transaction_id, reversal_transaction_id, reason, reversed_by
) VALUES (5, 7, 'Customer requested refund — item not delivered', 'AGENT_02');