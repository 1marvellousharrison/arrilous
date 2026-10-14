-- 0003_business_locations.sql
-- Phase 2 — Business location. Stored as coordinates now so logistics matching
-- can reuse it later, but nothing in this phase calls a logistics provider.
--
-- latitude/longitude are nullable because a denied location permission must
-- still let the owner finish setup with a typed address.

CREATE TABLE business_locations (
  id         TEXT PRIMARY KEY,
  business_id TEXT NOT NULL UNIQUE REFERENCES businesses(id) ON DELETE CASCADE,
  address    TEXT NOT NULL,
  city       TEXT,
  state      TEXT,
  country    TEXT,
  latitude   REAL,
  longitude  REAL,
  created_at TEXT NOT NULL DEFAULT now_iso(),
  updated_at TEXT NOT NULL DEFAULT now_iso(),

  CHECK (length(trim(address)) BETWEEN 3 AND 400),
  CHECK (latitude IS NULL OR (latitude BETWEEN -90 AND 90)),
  CHECK (longitude IS NULL OR (longitude BETWEEN -180 AND 180)),
  CHECK ((latitude IS NULL) = (longitude IS NULL))
);
