-- 0005_transactions.sql
-- Phase 5 — Core transactions.
--
-- A transaction exists before it is paid: money columns default to zero and no
-- status is inferred from them (the four statuses arrive in Phase 7).
--
-- `source` is created now so a WhatsApp-originated transaction can be stored
-- later without a migration, but only 'manual' is writable in this phase.
--
-- customer_id is nullable so a walk-in sale can be recorded before the
-- customer record exists.
--
-- All money columns are integer kobo and are computed server-side in Phase 6.
-- Any total sent by a client is ignored on write.

CREATE TABLE transactions (
  id                 TEXT PRIMARY KEY,
  business_id        TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  customer_id        TEXT REFERENCES customers(id) ON DELETE SET NULL,
  transaction_number TEXT NOT NULL,
  source             TEXT NOT NULL DEFAULT 'manual',
  subtotal_kobo      INTEGER NOT NULL DEFAULT 0,
  discount_kobo      INTEGER NOT NULL DEFAULT 0,
  delivery_fee_kobo  INTEGER NOT NULL DEFAULT 0,
  total_kobo         INTEGER NOT NULL DEFAULT 0,
  notes              TEXT,
  created_at         TEXT NOT NULL DEFAULT now_iso(),
  updated_at         TEXT NOT NULL DEFAULT now_iso(),

  UNIQUE (business_id, transaction_number),
  CHECK (source IN ('manual', 'whatsapp')),
  CHECK (subtotal_kobo >= 0),
  CHECK (discount_kobo >= 0),
  CHECK (delivery_fee_kobo >= 0),
  CHECK (total_kobo >= 0)
);

CREATE INDEX idx_transactions_business ON transactions(business_id, created_at);
CREATE INDEX idx_transactions_customer ON transactions(customer_id);
