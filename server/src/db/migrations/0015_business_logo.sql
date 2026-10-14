-- 0015_business_logo.sql
-- An optional logo for the business profile. It is stored as a small image
-- data URL (the client downscales before sending), so the wordmark a customer
-- sees can be the owner's own mark. Null means "no logo": the app falls back to
-- the first letter of the business name.

ALTER TABLE businesses ADD COLUMN logo_url TEXT;
