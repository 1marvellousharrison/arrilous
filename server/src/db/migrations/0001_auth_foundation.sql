-- 0001_auth_foundation.sql
-- Authentication foundation. Every later phase (business, location, products,
-- customers, transactions) references users(id) and must NOT redefine it.

CREATE TABLE users (
  id                TEXT PRIMARY KEY,
  full_name         TEXT NOT NULL,
  email             TEXT NOT NULL UNIQUE,
  phone             TEXT UNIQUE,
  password_hash     TEXT NOT NULL,
  role              TEXT NOT NULL DEFAULT 'business',
  status            TEXT NOT NULL DEFAULT 'active',
  email_verified_at TEXT,
  phone_verified_at TEXT,
  last_login_at     TEXT,
  created_at        TEXT NOT NULL DEFAULT now_iso(),
  updated_at        TEXT NOT NULL DEFAULT now_iso(),

  CHECK (role IN ('business', 'logistics_partner', 'rider')),
  CHECK (status IN ('active', 'suspended')),
  CHECK (length(trim(full_name)) > 0),
  CHECK (length(trim(email)) > 0),
  CHECK (length(password_hash) > 0)
);

-- Opaque refresh tokens (only the SHA-256 hash is stored, so a database leak
-- cannot be replayed as a valid session).
CREATE TABLE refresh_tokens (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  user_agent TEXT,
  ip_address TEXT,
  expires_at TEXT NOT NULL,
  revoked_at TEXT,
  created_at TEXT NOT NULL DEFAULT now_iso()
);

CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens(expires_at);

-- One-time codes for phone/email verification and password reset.
CREATE TABLE otp_challenges (
  id           TEXT PRIMARY KEY,
  identifier   TEXT NOT NULL,
  channel      TEXT NOT NULL,
  purpose      TEXT NOT NULL,
  code_hash    TEXT NOT NULL,
  attempts     INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 5,
  user_id      TEXT REFERENCES users(id) ON DELETE CASCADE,
  expires_at   TEXT NOT NULL,
  consumed_at  TEXT,
  created_at   TEXT NOT NULL DEFAULT now_iso(),

  CHECK (channel IN ('email', 'sms')),
  CHECK (purpose IN ('signup_verification', 'login_verification', 'password_reset'))
);

CREATE INDEX idx_otp_identifier ON otp_challenges(identifier, purpose);
CREATE INDEX idx_otp_expires ON otp_challenges(expires_at);
