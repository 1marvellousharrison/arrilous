-- 0018_business_edit_otps.sql
-- An owner-confirmed edit gate for an existing business profile. A one-time
-- code is emailed to the owner; verifying it mints a short-lived edit token that
-- authorises the profile and location writes of a single editing session.
--
-- A dedicated table, not otp_challenges: the auth OTP flow (signup, login,
-- password reset) keeps its own table and its own CHECK on `purpose`, and this
-- concern never has to widen that. See docs/business-details-edit-otp.md.
CREATE TABLE business_edit_otps (
  id           TEXT PRIMARY KEY,
  business_id  TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_hash    TEXT NOT NULL,
  attempts     INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 5,
  expires_at   TEXT NOT NULL,
  consumed_at  TEXT,
  created_at   TEXT NOT NULL DEFAULT now_iso()
);

CREATE INDEX idx_business_edit_otps_business
  ON business_edit_otps(business_id, created_at);
