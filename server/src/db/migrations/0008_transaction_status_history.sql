-- 0008_transaction_status_history.sql
-- Phase 8 — an append-only audit trail of every status change.
--
-- The four status columns on `transactions` hold the CURRENT value only. That
-- answers "what is this sale now?" but not "how did it get here?" — which is the
-- question an owner actually asks when a customer disputes a payment or a
-- delivery goes missing.
--
-- So every change appends a row here and the columns are never used to
-- reconstruct the past. Nothing in this table is ever updated or deleted:
-- there is deliberately no updated_at, and no route that writes to it other
-- than the status-change handler.
--
--   status_type which axis moved: order | payment | delivery | completion
--   old_value   the value before this change (NULL for the creation entry)
--   new_value   the value after this change
--   note        optional free text from the user making the change
--
-- Creation is recorded too, as four entries with old_value NULL. An owner
-- opening the timeline for a fresh order sees "order set to pending" rather
-- than an empty list that has to be special-cased in the UI.
--
-- business_id is denormalised from the transaction so history stays scoped by
-- the same middleware as everything else, and changed_by_user_id records who
-- moved it — including the automated entry written when the sale is created.

CREATE TABLE transaction_status_history (
  id                 TEXT PRIMARY KEY,
  seq BIGINT GENERATED ALWAYS AS IDENTITY,
  transaction_id     TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
  business_id        TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  changed_by_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  status_type        TEXT NOT NULL
                       CHECK (status_type IN ('order', 'payment', 'delivery', 'completion')),
  old_value          TEXT,
  new_value          TEXT NOT NULL,
  note               TEXT,
  created_at         TEXT NOT NULL
);

-- Phase 10 reads a transaction's timeline in order; Phase 12 reads the recent
-- activity for a business. Both are timeline-ordered scans.
CREATE INDEX idx_status_history_transaction
  ON transaction_status_history(transaction_id, created_at);
CREATE INDEX idx_status_history_business
  ON transaction_status_history(business_id, created_at);