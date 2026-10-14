-- Spec 6 — a delivery provider is reachable and specific, like a business:
-- a phone number and a description of what they carry are expected at setup.
ALTER TABLE logistics_organizations ADD COLUMN category TEXT;
ALTER TABLE logistics_riders ADD COLUMN phone TEXT;
ALTER TABLE logistics_riders ADD COLUMN category TEXT;
ALTER TABLE logistics_riders ADD COLUMN description TEXT;