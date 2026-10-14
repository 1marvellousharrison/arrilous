-- 0002_businesses.sql
-- Phase 1 — Business profile. One business per authenticated owner; every later
-- phase hangs off business_id, which is always resolved from the access token
-- (never from a request body).

CREATE TABLE businesses (
  id                   TEXT PRIMARY KEY,
  owner_user_id        TEXT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  business_name        TEXT NOT NULL,
  business_category    TEXT,
  business_description TEXT,
  phone                TEXT,
  email                TEXT,
  created_at           TEXT NOT NULL DEFAULT now_iso(),
  updated_at           TEXT NOT NULL DEFAULT now_iso(),

  CHECK (length(trim(business_name)) BETWEEN 2 AND 160)
);

CREATE INDEX idx_businesses_owner ON businesses(owner_user_id);
