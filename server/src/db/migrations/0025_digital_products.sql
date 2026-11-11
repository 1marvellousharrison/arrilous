-- 0025_digital_products.sql
-- Digital products sell a download/access asset instead of a physical item:
--
--   * products.kind separates a digital listing from the shelf. It defaults to
--     'physical', so every existing row keeps its current behaviour.
--   * A digital product can carry an owner-pasted link, an uploaded file, or
--     both. The file bytes live in digital_files because no object store is
--     configured; the table is small, immutable and scoped to the business.
--   * A sale snapshots the link/instructions/file id onto transaction_items, so
--     editing or replacing a product later never changes what a past buyer paid
--     for. The snapshot is the delivery record.
--   * transactions.public_token is the unguessable handle for the buyer's public
--     download page. It is only minted for a sale that contains digital lines,
--     and the public route only serves assets while payment_status = 'paid'.

CREATE TABLE digital_files (
  id          TEXT PRIMARY KEY,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  file_name   TEXT NOT NULL,
  mime_type   TEXT NOT NULL,
  size_bytes  INTEGER NOT NULL,
  data_base64 TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT now_iso(),

  CHECK (length(trim(file_name)) BETWEEN 1 AND 200),
  CHECK (length(trim(mime_type)) BETWEEN 1 AND 160),
  CHECK (size_bytes >= 0),
  CHECK (length(data_base64) > 0)
);

CREATE INDEX idx_digital_files_business ON digital_files(business_id);

ALTER TABLE products
  ADD COLUMN kind                 TEXT NOT NULL DEFAULT 'physical',
  ADD COLUMN digital_url          TEXT,
  ADD COLUMN digital_instructions TEXT,
  ADD COLUMN digital_file_id      TEXT REFERENCES digital_files(id) ON DELETE SET NULL;

ALTER TABLE products
  ADD CONSTRAINT products_kind_check CHECK (kind IN ('physical', 'digital'));

CREATE INDEX idx_products_kind ON products(business_id, kind);

ALTER TABLE transactions
  ADD COLUMN public_token          TEXT,
  ADD COLUMN digital_delivery_email TEXT,
  ADD COLUMN digital_delivered_at   TEXT;

CREATE UNIQUE INDEX idx_transactions_public_token
  ON transactions(public_token);

ALTER TABLE transaction_items
  ADD COLUMN is_digital           INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN digital_url          TEXT,
  ADD COLUMN digital_instructions TEXT,
  ADD COLUMN digital_file_id      TEXT REFERENCES digital_files(id) ON DELETE SET NULL;
