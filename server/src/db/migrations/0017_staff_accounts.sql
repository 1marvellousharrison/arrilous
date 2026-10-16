-- 0017_staff_accounts.sql
-- Staff accounts: a restricted, subordinate role that a Main (owner) business
-- pulls into itself. See docs/staff-accounts.md.
--
-- The shape:
--   * a staff login is a users row with role='staff', linked to a business
--     through a staff_members row (the link is the source of truth for who the
--     Main's staff are — owner_user_id only ever identifies the owner);
--   * staff sign in with a permanent staff code (business_code + '-' + seq) plus
--     a password they set themselves; the owner never sees that password;
--   * every sale records who made it, and a sale that is marked paid credits the
--     owner's wallet through a new `sale` ledger kind.

-- 1. users — allow the staff role. Self-signup still cannot choose it: the API's
--    ROLES list is left untouched, so this only opens the door for staff_members.
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check
  CHECK (role IN ('business', 'logistics_partner', 'rider', 'staff'));

-- A staff account is created from a code alone, so it has no email of its own.
-- The length>0 CHECK tolerates NULL (an unknown result passes a CHECK), and the
-- UNIQUE index allows many NULLs, so this is safe to relax.
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;

-- 2. businesses — a stable, globally-unique prefix used to build staff codes.
--    Snapshotted once, never derived from the live (mutable) name.
ALTER TABLE businesses ADD COLUMN business_code TEXT;
ALTER TABLE businesses ADD CONSTRAINT businesses_business_code_key
  UNIQUE (business_code);

-- 3. staff_members — the link between a staff login and the business it serves.
CREATE TABLE staff_members (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  business_id  TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  staff_code   TEXT NOT NULL UNIQUE,                 -- the permanent login ID
  status       TEXT NOT NULL DEFAULT 'invited',      -- invited | active | disabled
  permissions  TEXT,                                 -- role/limits, reserved
  created_by   TEXT REFERENCES users(id) ON DELETE SET NULL,
  activated_at TEXT,
  created_at   TEXT NOT NULL DEFAULT now_iso(),
  updated_at   TEXT NOT NULL DEFAULT now_iso(),

  CHECK (status IN ('invited', 'active', 'disabled'))
);
CREATE INDEX idx_staff_members_business ON staff_members(business_id);

-- 4. transactions — record who recorded the sale (owner or staff), so a staff's
--    own list can be scoped and the owner can see the staff on each row.
ALTER TABLE transactions
  ADD COLUMN created_by_user_id TEXT REFERENCES users(id) ON DELETE SET NULL;
CREATE INDEX idx_transactions_created_by
  ON transactions(business_id, created_by_user_id);

-- 5. wallet_transactions — a sale credit is a third kind alongside funding and
--    payout. Its own channel keeps the ledger honest about where money came from.
ALTER TABLE wallet_transactions
  DROP CONSTRAINT IF EXISTS wallet_transactions_kind_check;
ALTER TABLE wallet_transactions ADD CONSTRAINT wallet_transactions_kind_check
  CHECK (kind IN ('funding', 'payout', 'sale'));
ALTER TABLE wallet_transactions
  DROP CONSTRAINT IF EXISTS wallet_transactions_channel_check;
ALTER TABLE wallet_transactions ADD CONSTRAINT wallet_transactions_channel_check
  CHECK (channel IN ('virtual_account', 'card', 'payout', 'sale'));

-- 6. transaction_status_history — a staff may add a note to a sale without
--    moving any status. That note is a timeline entry with no axis, so the type
--    gains 'note' and new_value must be allowed to be empty for it.
ALTER TABLE transaction_status_history
  DROP CONSTRAINT IF EXISTS transaction_status_history_status_type_check;
ALTER TABLE transaction_status_history
  ADD CONSTRAINT transaction_status_history_status_type_check
  CHECK (status_type IN ('order', 'payment', 'delivery', 'completion', 'note'));
ALTER TABLE transaction_status_history ALTER COLUMN new_value DROP NOT NULL;
