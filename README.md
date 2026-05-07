# financial-db-patterns

A PostgreSQL schema demonstrating real-world card processing patterns drawn from production experience in banking and pension fund systems in El Salvador. This is not a toy example — the design decisions here reflect problems you actually run into when building financial infrastructure in production.

---

## Why this exists

Most database tutorials for financial systems are either too abstract ("here's a `users` and `transactions` table") or too vendor-specific to be useful outside their context. This project sits in the middle: a complete, runnable schema that covers the real surface area of a card issuance and transaction processing system — the kind of thing a small bank or fintech actually ships.

The patterns here — idempotency tokens, trigger-based history tables, real-time balance via statement checkpoints — are not theoretical. They come from debugging production incidents, passing regulatory audits, and keeping transaction logs clean enough that disputes can be resolved months after the fact.

---

## Schema architecture

The schema is split into four modules with explicit cross-schema foreign keys. Run them in order.

```
┌─────────────────────────────────────────────────────────────┐
│                      catalogs                               │
│  document_type · status · account_type · card_type          │
│  address_type · transaction_origin · transaction_type        │
└───────────────────────────┬─────────────────────────────────┘
                            │ referenced by all modules
          ┌─────────────────┼──────────────────────┐
          ▼                 ▼                       ▼
   ┌─────────────┐   ┌────────────────┐   ┌──────────────────────┐
   │    party    │   │     cards      │   │    transactions      │
   │             │──▶│                │──▶│                      │
   │  person     │   │  card_issuer   │   │  card_transaction    │
   │  documents  │   │  card_bin      │   │  transaction_reversal│
   │  contacts   │   │  account       │   │  duplicate_log       │
   │  addresses  │   │  card          │   │  transaction_token   │
   │ beneficiari │   │  card_block    │   │                      │
   └─────────────┘   │  travel_report │   └──────────────────────┘
                     │  statement     │
                     └────────────────┘
```

### Module 1 — `catalogs`

Shared reference tables used across all other schemas. Codes are fixed-width `CHAR(3)` (e.g., `'DUI'`, `'ACT'`, `'PUR'`) for fast joins and readable queries without integer lookups.

| Table | Purpose |
|---|---|
| `document_type` | DUI, Passport, Resident Card, Minor ID |
| `status` | ACT, INA, BLO, CAN, DEC — shared by all entities |
| `account_type` | SAV, CHK, CRD |
| `card_type` | CRD (credit), DEB (debit) |
| `address_type` | RES, WRK, MAI |
| `transaction_origin` | POS, ATM, BRN, WEB, APP |
| `transaction_type` | PUR, WIT, REV, PAY, ADJ |

### Module 2 — `party`

Person master data. The `person` table is intentionally flat and conservative — only data that a bank is actually required to collect. Multiple emails, phones, and addresses are each in their own tables to avoid the "email1/email2/email3" column trap.

Key tables: `person`, `person_document`, `person_email`, `person_phone`, `person_address`, `person_beneficiary`.

Every UPDATE or DELETE on `person` fires a trigger that writes the previous state to `person_history` before the change is applied.

### Module 3 — `cards`

The issuance pipeline from BIN registry to physical card, plus account management and travel authorization.

| Table | Purpose |
|---|---|
| `card_issuer` | Visa, Mastercard, etc. |
| `card_bin` | 6-digit BIN → issuer + card type mapping |
| `account` | Links a person to a financial product with credit limit |
| `card_request` | Pre-approval record with reviewer audit trail |
| `card` | Issued card with masked PAN, BIN reference, expiry |
| `card_block` | Active/inactive blocks with reason and who applied them |
| `account_statement` | Monthly cutoff snapshots used for balance calculation |
| `card_travel_report` | International authorization windows per card |

Trigger-based history on `account` and `card` mirrors the pattern from `party`.

### Module 4 — `transactions`

Core transaction processing with authorization logic, reversal linking, duplicate detection, and an idempotency layer for retries.

Key tables: `card_transaction`, `card_transaction_history`, `transaction_reversal`, `duplicate_transaction_log`, `transaction_token`.

Key functions:

- **`fn_get_realtime_balance(account_id)`** — computes current balance as `last_statement.closing_balance + Σ(transactions since cutoff)`. Does not maintain a running balance column.
- **`fn_authorize_transaction(...)`** — validates card status, block status, credit limit, and 5-minute duplicate window before inserting.
- **`fn_request_token(card_id)`** — issues an idempotency token before a transaction is submitted.
- **`fn_consume_token(token, card_id, amount)`** — validates and consumes a token, or replays the stored result if the token was already used.
- **`fn_mark_token_used(...)`** — records the authorization outcome against the token for future replays.

---

## Key design decisions

### Trigger-based history tables, not `updated_at` alone

Every mutable entity (`person`, `account`, `card`, `card_transaction`) has a paired `_history` table. A `BEFORE UPDATE OR DELETE` trigger fires on every change, writing the OLD row with a timestamp, operator, and operation code (`'U'` or `'D'`).

`updated_at` tells you when something changed. The history table tells you what it was before it changed, who changed it, and gives you a full audit trail without external tooling or CDC pipelines. This is what regulators and fraud investigators actually ask for.

The trigger fires **before** the change so the OLD row is captured atomically. A post-update trigger risks missing the data if the transaction rolls back between the main write and the history insert.

### Idempotency via token-based two-phase commit

POS terminals and payment gateways retry on timeout. Without idempotency, a network blip between the terminal and the processor results in a duplicated charge. The pattern here:

1. Terminal calls `fn_request_token(card_id)` — gets a UUID token valid for 10 minutes, optionally locked to a specific amount.
2. Terminal submits the transaction with the token.
3. `fn_consume_token` is called first. If the token was already consumed, it returns the stored result immediately — no second authorization runs.
4. If the token is fresh, the authorization runs and `fn_mark_token_used` records the outcome.

This means the terminal can retry as many times as it wants. The customer gets charged exactly once.

### JSONB `raw_payload` on transactions

Every `card_transaction` stores the full JSON (or ISO 8583-derived JSON) payload from the payment processor in a `JSONB` column. This is not indexed or queried in normal operations — it exists for incident response.

When a dispute comes in three months later and the processor's audit log is inconclusive, `raw_payload` is often the only source of truth. Storing it costs disk; not storing it costs customer trust and legal exposure.

### `TEXT[]` for travel countries

`card_travel_report.countries` is a PostgreSQL array of ISO 3166-1 alpha-3 country codes rather than a join table with one row per country.

The countries in a travel report are always read and written together — no query ever needs "give me all trips that include country X." An array is simpler, cheaper, and honest about the access pattern. A join table would be normalized for queries that don't exist.

### Balance via statement snapshots, not a running column

`fn_get_realtime_balance` does not read a `current_balance` column. It reads the last `account_statement.closing_balance` and sums all active transactions since that cutoff date.

A running balance column drifts. Reversals, adjustments, and concurrent writes can all leave it inconsistent, and reconciling it against the transaction log is expensive. The snapshot + delta approach is slightly more expensive at read time but is always correct by construction.

### Soft deactivation with full audit trail

`person`, `account`, and `card` all carry `deactivated_by`, `deactivated_at`, and `deactivation_reason` columns rather than using hard deletes. In regulated environments, you cannot delete a customer record that was ever party to a transaction. The status catalog (`'CAN'`, `'INA'`) drives business logic; the deactivation columns serve the audit log.

---

## Running locally with Docker

The `docker-compose.yml` spins up PostgreSQL 16 and pgAdmin. The `schemas/` directory is mounted to `/docker-entrypoint-initdb.d`, which PostgreSQL runs automatically on first initialization — in alphabetical order, which is why the files are numbered.

```bash
docker compose up -d
```

| Service | URL | Credentials |
|---|---|---|
| PostgreSQL | `localhost:5433` | `finuser` / `finpass123` |
| pgAdmin | `http://localhost:5050` | `admin@financial.dev` / `admin123` |

Port 5433 (not 5432) avoids conflicts with any local PostgreSQL instance.

**Connect with psql:**

```bash
psql -h localhost -p 5433 -U finuser -d financial_cards
```

**Verify schemas loaded:**

```sql
SELECT schema_name FROM information_schema.schemata
WHERE schema_name IN ('catalogs', 'party', 'cards', 'transactions');
```

**Test the authorization function:**

```sql
-- Request a token
SELECT transactions.fn_request_token(1);

-- Run an authorization (replace token UUID with the one returned above)
SELECT * FROM transactions.fn_authorize_transaction(
    1,                          -- card_id
    50.00,                      -- amount
    'PUR',                      -- transaction_type
    'POS',                      -- origin
    'WALMART SAN SALVADOR',     -- merchant_name
    'AUTH123456',               -- authorization_code
    '{"terminal_id": "T001"}'::jsonb  -- raw_payload
);
```

**Reset the database:**

```bash
docker compose down -v && docker compose up -d
```

The `-v` flag removes the named volume, which forces PostgreSQL to re-run the init scripts on the next startup.

---

## Lessons learned from production

**Audit trails are the product.** In banking, the transaction is not the end of the story — the audit trail is. Every time a history table was skipped or `updated_at` was the only audit trail, the bill eventually came due — a regulatory review, a fraud dispute, a support ticket that couldn't be closed. Build the history tables first.

**Idempotency is not optional in payment systems.** Network retries are not edge cases — they are the normal failure mode of a distributed system. Every endpoint that creates a financial record needs to be safe to call twice. The token pattern here is one approach; the important part is that the decision to implement it is made at schema design time, not after the first duplicate incident.

**JSONB for external payloads, normalized columns for everything you query.** The `raw_payload` column has paid for itself more than once, but it is never in a WHERE clause. Use JSONB to capture what you cannot fully control (external API responses, processor formats that change without notice) and relational columns for everything your application logic depends on.

**Arrays have a place.** PostgreSQL arrays are often dismissed as an anti-pattern, but the travel countries use case is exactly what they are good for: a small, bounded list that has no meaningful existence outside its parent row. The alternative — a `card_travel_country` table — would require a join on every travel validation query for no benefit.

**Balances should be derived, not stored.** Running balance columns go out of sync under concurrent load — reversals, adjustments, and retries all create windows where the column lies. The extra read cost of computing balance from the last statement is worth the guarantee that it is always correct.

**Separate card request from card issuance.** The `card_request → card` flow exists because card issuance in practice involves an approval step — a person, a rule engine, or both. Collapsing this into a single table makes it harder to model rejections, pending approvals, and the audit trail of who approved what. Keep the workflow stages separate.

---

## Schema files

| File | Module | Contents |
|---|---|---|
| [schemas/01_catalogs.sql](schemas/01_catalogs.sql) | catalogs | Reference tables with seed data |
| [schemas/02_party.sql](schemas/02_party.sql) | party | Person, documents, contacts, beneficiaries |
| [schemas/03_cards.sql](schemas/03_cards.sql) | cards | BIN, accounts, cards, blocks, travel, statements |
| [schemas/04_transactions.sql](schemas/04_transactions.sql) | transactions | Authorization, reversal, duplicate detection |
| [schemas/05_idempotency.sql](schemas/05_idempotency.sql) | transactions | Token-based idempotency layer |

---

## Requirements

- Docker and Docker Compose
- PostgreSQL client (optional, for direct `psql` access)
- pgAdmin is included in the Compose stack

No application code required — this is a schema and logic layer only.
