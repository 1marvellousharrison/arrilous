-- Low-stock alerts need to point at the product they are about, so the same
-- product can be alerted once (not once per read) and the alert can be resolved
-- the moment stock is replenished.
ALTER TABLE notifications
  ADD COLUMN product_id TEXT REFERENCES products(id) ON DELETE CASCADE;

CREATE INDEX idx_notifications_product
  ON notifications(product_id, read_at);

-- At most one *open* low-stock alert per product. A replenished product's
-- alert is marked read, which frees the slot for the next time it runs low.
CREATE UNIQUE INDEX idx_notifications_low_stock_open
  ON notifications(product_id)
  WHERE type = 'low_stock' AND read_at IS NULL;
