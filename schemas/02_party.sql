-- ============================================================
-- SCHEMA: party
-- Person master data, documents, contacts and addresses
-- ============================================================

CREATE SCHEMA IF NOT EXISTS party;
SET search_path TO party;

-- Core person table
CREATE TABLE person (
    id                  SERIAL          PRIMARY KEY,
    first_name          VARCHAR(50)     NOT NULL,
    middle_name         VARCHAR(50),
    first_surname       VARCHAR(50)     NOT NULL,
    second_surname      VARCHAR(50),
    married_surname     VARCHAR(50),
    birth_date          DATE            NOT NULL,
    gender              CHAR(1)         NOT NULL CHECK (gender IN ('M', 'F', 'O')),
    status              CHAR(3)         NOT NULL DEFAULT 'ACT' REFERENCES catalogs.status(code),
    created_by          VARCHAR(50)     NOT NULL,
    created_at          TIMESTAMP       NOT NULL DEFAULT NOW(),
    updated_by          VARCHAR(50),
    updated_at          TIMESTAMP,
    deactivated_by      VARCHAR(50),
    deactivated_at      TIMESTAMP,
    deactivation_reason TEXT
);

-- Person history (triggered on every UPDATE or DELETE)
CREATE TABLE person_history (
    id                  SERIAL          PRIMARY KEY,
    person_id           INT             NOT NULL,
    first_name          VARCHAR(50)     NOT NULL,
    middle_name         VARCHAR(50),
    first_surname       VARCHAR(50)     NOT NULL,
    second_surname      VARCHAR(50),
    married_surname     VARCHAR(50),
    birth_date          DATE            NOT NULL,
    gender              CHAR(1)         NOT NULL,
    status              CHAR(3)         NOT NULL,
    created_by          VARCHAR(50)     NOT NULL,
    created_at          TIMESTAMP       NOT NULL,
    updated_by          VARCHAR(50),
    updated_at          TIMESTAMP,
    deactivated_by      VARCHAR(50),
    deactivated_at      TIMESTAMP,
    deactivation_reason TEXT,
    -- History metadata
    recorded_at         TIMESTAMP       NOT NULL DEFAULT NOW(),
    recorded_by         VARCHAR(50)     NOT NULL DEFAULT 'SYSTEM',
    operation           CHAR(1)         NOT NULL CHECK (operation IN ('U', 'D'))
);

-- Identity documents (one per type per person)
CREATE TABLE person_document (
    id                  SERIAL          PRIMARY KEY,
    person_id           INT             NOT NULL REFERENCES person(id),
    document_type       CHAR(3)         NOT NULL REFERENCES catalogs.document_type(code),
    document_number     VARCHAR(30)     NOT NULL,
    issue_date          DATE,
    expiry_date         DATE,
    issuing_country     CHAR(3)         NOT NULL DEFAULT 'SLV',
    is_primary          BOOLEAN         NOT NULL DEFAULT FALSE,
    status              CHAR(3)         NOT NULL DEFAULT 'ACT' REFERENCES catalogs.status(code),
    created_by          VARCHAR(50)     NOT NULL,
    created_at          TIMESTAMP       NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_person_document_type UNIQUE (person_id, document_type)
);

-- Email addresses (multiple per person)
CREATE TABLE person_email (
    id                  SERIAL          PRIMARY KEY,
    person_id           INT             NOT NULL REFERENCES person(id),
    email               VARCHAR(100)    NOT NULL,
    is_primary          BOOLEAN         NOT NULL DEFAULT FALSE,
    status              CHAR(3)         NOT NULL DEFAULT 'ACT' REFERENCES catalogs.status(code),
    created_by          VARCHAR(50)     NOT NULL,
    created_at          TIMESTAMP       NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_person_email UNIQUE (email)
);

-- Phone numbers (multiple per person)
CREATE TABLE person_phone (
    id                  SERIAL          PRIMARY KEY,
    person_id           INT             NOT NULL REFERENCES person(id),
    country_code        CHAR(5)         NOT NULL DEFAULT '+503',
    phone_number        VARCHAR(15)     NOT NULL,
    is_primary          BOOLEAN         NOT NULL DEFAULT FALSE,
    status              CHAR(3)         NOT NULL DEFAULT 'ACT' REFERENCES catalogs.status(code),
    created_by          VARCHAR(50)     NOT NULL,
    created_at          TIMESTAMP       NOT NULL DEFAULT NOW()
);

-- Addresses (multiple per person, one mailing)
CREATE TABLE person_address (
    id                  SERIAL          PRIMARY KEY,
    person_id           INT             NOT NULL REFERENCES person(id),
    address_type        CHAR(3)         NOT NULL REFERENCES catalogs.address_type(code),
    line1               VARCHAR(200)    NOT NULL,
    line2               VARCHAR(200),
    city                VARCHAR(100),
    state_province      VARCHAR(100),
    country             CHAR(3)         NOT NULL DEFAULT 'SLV',
    postal_code         VARCHAR(10),
    is_mailing          BOOLEAN         NOT NULL DEFAULT FALSE,
    status              CHAR(3)         NOT NULL DEFAULT 'ACT' REFERENCES catalogs.status(code),
    created_by          VARCHAR(50)     NOT NULL,
    created_at          TIMESTAMP       NOT NULL DEFAULT NOW(),
    updated_by          VARCHAR(50),
    updated_at          TIMESTAMP
);

-- Beneficiaries
CREATE TABLE person_beneficiary (
    id                  SERIAL          PRIMARY KEY,
    person_id           INT             NOT NULL REFERENCES person(id),
    first_name          VARCHAR(50)     NOT NULL,
    middle_name         VARCHAR(50),
    first_surname       VARCHAR(50)     NOT NULL,
    second_surname      VARCHAR(50),
    relationship        VARCHAR(50)     NOT NULL,
    percentage          DECIMAL(5,2)    NOT NULL CHECK (percentage > 0 AND percentage <= 100),
    status              CHAR(3)         NOT NULL DEFAULT 'ACT' REFERENCES catalogs.status(code),
    created_by          VARCHAR(50)     NOT NULL,
    created_at          TIMESTAMP       NOT NULL DEFAULT NOW()
);

-- ============================================================
-- TRIGGER: auto-history on person UPDATE or DELETE
-- ============================================================

CREATE OR REPLACE FUNCTION fn_person_history()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO party.person_history (
        person_id, first_name, middle_name, first_surname, second_surname,
        married_surname, birth_date, gender, status,
        created_by, created_at, updated_by, updated_at,
        deactivated_by, deactivated_at, deactivation_reason,
        operation
    ) VALUES (
        OLD.id, OLD.first_name, OLD.middle_name, OLD.first_surname, OLD.second_surname,
        OLD.married_surname, OLD.birth_date, OLD.gender, OLD.status,
        OLD.created_by, OLD.created_at, OLD.updated_by, OLD.updated_at,
        OLD.deactivated_by, OLD.deactivated_at, OLD.deactivation_reason,
        TG_OP
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_person_history
BEFORE UPDATE OR DELETE ON party.person
FOR EACH ROW EXECUTE FUNCTION fn_person_history();