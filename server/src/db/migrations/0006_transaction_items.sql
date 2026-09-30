-- 0006_transaction_items.sql
-- Phase 6 — Itemised transaction lines.
--
-- product_name_snapshot and unit_price_kobo are immutable copies taken at the
-- moment of sale. Phase 3 explicitly requires history to survive catalog
-- edits: renaming "Black Shirt" to "Black T-Shirt" or changing its price must
-- not rewrite what the customer was actually charged.
--
-- product_id is ON DELETE SET NULL, not CASCADE: deleting a catalog row must
-- never delete a financial record. The snapshot keeps the line readable.

CREATE TABLE transaction_items (
  id                   TEXT PRIMARY KEY,
  transaction_id       TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
  product_id           TEXT REFERENCES products(id) ON DELETE SET NULL,
  product_name_snapshot TEXT NOT NULL,
  quantity             INTEGER NOT NULL,
  unit_price_kobo      INTEGER NOT NULL,
  subtotal_kobo        INTEGER NOT NULL,
  created_at           TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),

  CHECK (quantity > 0),
  CHECK (unit_price_kobo >= 0),
  CHECK (subtotal_kobo >= 0),
  CHECK (subtotal_kobo = quantity * unit_price_kobo)
);

CREATE INDEX idx_transaction_items_transaction ON transaction_items(transaction_id);
CREATE INDEX idx_transaction_items_product ON transaction_items(product_id);
