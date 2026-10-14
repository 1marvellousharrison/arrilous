-- 0004b_customers.sql
-- Phase 4 — Customers. These are the business's own records, NOT app accounts:
-- there is deliberately no user_id and no password, and a customer row must
-- never be treated as an authenticated principal.

CREATE TABLE customers (
  id          TEXT PRIMARY KEY,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  phone       TEXT,
  email       TEXT,
  address     TEXT,
  notes       TEXT,
  created_at  TEXT NOT NULL DEFAULT now_iso(),
  updated_at  TEXT NOT NULL DEFAULT now_iso(),

  CHECK (length(trim(name)) BETWEEN 2 AND 160)
);

CREATE INDEX idx_customers_business ON customers(business_id, name);
CREATE INDEX idx_customers_business_phone ON customers(business_id, phone);
