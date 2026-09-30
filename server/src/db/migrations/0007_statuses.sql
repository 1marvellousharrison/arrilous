-- 0007_statuses.sql
-- Phase 7 — Four independent statuses instead of one giant status column.
--
-- They are deliberately separate axes: a transaction can be "confirmed,
-- paid, awaiting delivery, open" at the same time, and collapsing them into one
-- column is what forces the "payment implies delivery" bug.
--
--   order_status      pending | confirmed | cancelled
--   payment_status    unpaid | payment_pending | paid | failed | refunded
--   delivery_status   not_required | pending | accepted | picked_up |
--                     in_transit | delivered | failed
--   completion_status open | completed
--
-- Defaults are the "just created" state. completion_status stays 'open' when
-- payment is marked paid: payment must NEVER auto-complete a transaction.
--
-- delivery_required drives whether delivery_status starts at 'not_required' or
-- 'pending'; delivery_address is captured now so Phase 9's UI has somewhere to
-- put it.

ALTER TABLE transactions ADD COLUMN order_status TEXT NOT NULL DEFAULT 'pending'
  CHECK (order_status IN ('pending', 'confirmed', 'cancelled'));

ALTER TABLE transactions ADD COLUMN payment_status TEXT NOT NULL DEFAULT 'unpaid'
  CHECK (payment_status IN ('unpaid', 'payment_pending', 'paid', 'failed', 'refunded'));

ALTER TABLE transactions ADD COLUMN delivery_status TEXT NOT NULL DEFAULT 'not_required'
  CHECK (delivery_status IN ('not_required', 'pending', 'accepted', 'picked_up',
                             'in_transit', 'delivered', 'failed'));

ALTER TABLE transactions ADD COLUMN completion_status TEXT NOT NULL DEFAULT 'open'
  CHECK (completion_status IN ('open', 'completed'));

ALTER TABLE transactions ADD COLUMN delivery_required INTEGER NOT NULL DEFAULT 0
  CHECK (delivery_required IN (0, 1));

ALTER TABLE transactions ADD COLUMN delivery_address TEXT;

CREATE INDEX idx_transactions_payment ON transactions(business_id, payment_status);
CREATE INDEX idx_transactions_delivery ON transactions(business_id, delivery_status);
CREATE INDEX idx_transactions_order ON transactions(business_id, order_status);
