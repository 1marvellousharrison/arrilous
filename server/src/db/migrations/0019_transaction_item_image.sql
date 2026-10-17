-- 0019_transaction_item_image.sql
-- A snapshot of the product's picture on the line it was sold as. It is copied
-- from the product at the moment of the sale (ad-hoc lines have none), so a
-- receipt keeps the exact image that was sold even if the product is later
-- edited or archived. Stored as the same small image data URL the client sends.

ALTER TABLE transaction_items ADD COLUMN image_url TEXT;
