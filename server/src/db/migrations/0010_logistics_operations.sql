-- Operational records deliberately extend the logistics network rather than
-- duplicating transaction or status history data.
CREATE TABLE logistics_notifications (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  delivery_request_id TEXT REFERENCES delivery_requests(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  read_at TEXT,
  created_at TEXT NOT NULL DEFAULT now_iso()
);
CREATE INDEX idx_logistics_notifications_user ON logistics_notifications(user_id, read_at, created_at DESC);

CREATE TABLE delivery_request_events (
  id TEXT PRIMARY KEY,
  delivery_request_id TEXT NOT NULL REFERENCES delivery_requests(id) ON DELETE CASCADE,
  actor_user_id TEXT NOT NULL REFERENCES users(id),
  event_type TEXT NOT NULL,
  note TEXT,
  created_at TEXT NOT NULL DEFAULT now_iso()
);
CREATE INDEX idx_delivery_request_events_request ON delivery_request_events(delivery_request_id, created_at);

CREATE TABLE delivery_confirmation_otps (
  id TEXT PRIMARY KEY,
  delivery_request_id TEXT NOT NULL UNIQUE REFERENCES delivery_requests(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  verified_at TEXT,
  created_at TEXT NOT NULL DEFAULT now_iso()
);

ALTER TABLE logistics_riders ADD COLUMN current_latitude REAL;
ALTER TABLE logistics_riders ADD COLUMN current_longitude REAL;
ALTER TABLE logistics_riders ADD COLUMN updated_location_at TEXT;
