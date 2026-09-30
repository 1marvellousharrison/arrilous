-- 0004_products.sql
-- Phase 3 — Product catalog.
--
-- Money is stored as an integer count of kobo (1 naira = 100 kobo) and the
-- column name says so. Floating point money accumulates rounding drift, and
-- every total in Phases 5/6 is derived from these values.
--
-- "active" is the archive flag: archived products stay in the database because
-- historical transaction items reference them, they just disappear from the
-- default catalog listing.

CREATE TABLE products (
  id             TEXT PRIMARY KEY,
  business_id    TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  name           TEXT NOT NULL,
  description    TEXT,
  category       TEXT,
  price_kobo     INTEGER NOT NULL,
  sku            TEXT,
  stock_quantity INTEGER NOT NULL DEFAULT 0,
  image_url      TEXT,
  active         INTEGER NOT NULL DEFAULT 1,
  created_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),

  CHECK (length(trim(name)) BETWEEN 2 AND 160),
  CHECK (price_kobo >= 0),
  CHECK (stock_quantity >= 0),
  CHECK (active IN (0, 1))
);

CREATE UNIQUE INDEX idx_products_business_sku ON products(business_id, sku)
  WHERE sku IS NOT NULL;
CREATE INDEX idx_products_business ON products(business_id, active);
CREATE INDEX idx_products_business_name ON products(business_id, name);
