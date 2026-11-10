-- 0024_customer_creator.sql
-- A staff may register a customer before recording their first sale to them.
-- Remembering who added the customer keeps that record visible to its creator,
-- while the owner's wider customer book stays private to the owner and to staff
-- who have actually served the customer.

ALTER TABLE customers
  ADD COLUMN created_by_user_id TEXT REFERENCES users(id) ON DELETE SET NULL;

CREATE INDEX idx_customers_created_by
  ON customers(business_id, created_by_user_id);
