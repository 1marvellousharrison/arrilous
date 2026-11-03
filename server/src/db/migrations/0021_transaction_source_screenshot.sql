-- 0021_transaction_source_screenshot.sql
-- Screenshot/photo imports create real transactions, so 'screenshot' (and the
-- 'image' alias used by the importer) must be allowed in transactions.source.
-- 0005 only permitted 'manual' and 'whatsapp', which made every AI import fail
-- with a CHECK violation when the owner pressed "Create order".

ALTER TABLE transactions DROP CONSTRAINT IF EXISTS transactions_source_check;

ALTER TABLE transactions
  ADD CONSTRAINT transactions_source_check
  CHECK (source IN ('manual', 'whatsapp', 'screenshot', 'image'));
