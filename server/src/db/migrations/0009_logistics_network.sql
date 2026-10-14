-- Logistics extension. Delivery-specific state references the existing
-- transaction instead of copying its financial or customer records.
CREATE TABLE logistics_organizations (
  id TEXT PRIMARY KEY,
  owner_user_id TEXT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  description TEXT,
  is_available INTEGER NOT NULL DEFAULT 0 CHECK (is_available IN (0, 1)),
  availability_started_at TEXT,
  availability_expires_at TEXT,
  created_at TEXT NOT NULL DEFAULT now_iso(),
  updated_at TEXT NOT NULL DEFAULT now_iso()
);

CREATE TABLE logistics_service_areas (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES logistics_organizations(id) ON DELETE CASCADE,
  city TEXT NOT NULL,
  area TEXT,
  state TEXT,
  country TEXT,
  latitude REAL,
  longitude REAL,
  radius_km REAL,
  created_at TEXT NOT NULL DEFAULT now_iso()
);
CREATE INDEX idx_logistics_areas_org ON logistics_service_areas(organization_id);

CREATE TABLE logistics_pricing (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES logistics_organizations(id) ON DELETE CASCADE,
  destination TEXT NOT NULL,
  price_kobo INTEGER NOT NULL CHECK (price_kobo >= 0),
  vehicle_type TEXT,
  created_at TEXT NOT NULL DEFAULT now_iso(),
  updated_at TEXT NOT NULL DEFAULT now_iso(),
  UNIQUE(organization_id, destination, vehicle_type)
);

CREATE TABLE logistics_vehicles (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES logistics_organizations(id) ON DELETE CASCADE,
  vehicle_type TEXT NOT NULL CHECK (vehicle_type IN ('motorcycle', 'tricycle', 'car', 'van', 'pickup', 'truck', 'other')),
  total_quantity INTEGER NOT NULL CHECK (total_quantity >= 0),
  available_quantity INTEGER NOT NULL CHECK (available_quantity >= 0 AND available_quantity <= total_quantity),
  capacity_category TEXT NOT NULL CHECK (capacity_category IN ('small', 'medium', 'large', 'very_large')),
  starting_price_kobo INTEGER NOT NULL DEFAULT 0 CHECK (starting_price_kobo >= 0),
  active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
  description TEXT,
  created_at TEXT NOT NULL DEFAULT now_iso(),
  updated_at TEXT NOT NULL DEFAULT now_iso()
);
CREATE INDEX idx_logistics_vehicles_org ON logistics_vehicles(organization_id, active);

CREATE TABLE logistics_riders (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  organization_id TEXT REFERENCES logistics_organizations(id) ON DELETE SET NULL,
  is_available INTEGER NOT NULL DEFAULT 0 CHECK (is_available IN (0, 1)),
  availability_started_at TEXT,
  availability_expires_at TEXT,
  created_at TEXT NOT NULL DEFAULT now_iso(),
  updated_at TEXT NOT NULL DEFAULT now_iso()
);
CREATE INDEX idx_logistics_riders_org ON logistics_riders(organization_id);

CREATE TABLE rider_service_areas (
  id TEXT PRIMARY KEY,
  rider_id TEXT NOT NULL REFERENCES logistics_riders(id) ON DELETE CASCADE,
  city TEXT NOT NULL,
  area TEXT,
  state TEXT,
  country TEXT,
  created_at TEXT NOT NULL DEFAULT now_iso()
);

CREATE TABLE rider_delivery_modes (
  id TEXT PRIMARY KEY,
  rider_id TEXT NOT NULL REFERENCES logistics_riders(id) ON DELETE CASCADE,
  mode TEXT NOT NULL CHECK (mode IN ('motorcycle', 'car', 'bicycle', 'other')),
  capacity_category TEXT NOT NULL CHECK (capacity_category IN ('small', 'medium', 'large', 'very_large')),
  rate_kobo INTEGER NOT NULL DEFAULT 0 CHECK (rate_kobo >= 0),
  is_primary INTEGER NOT NULL DEFAULT 0 CHECK (is_primary IN (0, 1)),
  active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT now_iso()
);

CREATE TABLE delivery_requests (
  id TEXT PRIMARY KEY,
  transaction_id TEXT NOT NULL UNIQUE REFERENCES transactions(id) ON DELETE CASCADE,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  organization_id TEXT REFERENCES logistics_organizations(id) ON DELETE SET NULL,
  rider_id TEXT REFERENCES logistics_riders(id) ON DELETE SET NULL,
  pickup_address TEXT NOT NULL,
  pickup_city TEXT,
  destination_address TEXT NOT NULL,
  destination_city TEXT,
  package_description TEXT,
  package_size TEXT CHECK (package_size IN ('small', 'medium', 'large', 'very_large')),
  preferred_mode TEXT,
  published_price_kobo INTEGER,
  quoted_price_kobo INTEGER,
  accepted_price_kobo INTEGER,
  status TEXT NOT NULL DEFAULT 'requested' CHECK (status IN ('requested', 'quoted', 'accepted', 'assigned', 'picked_up', 'in_transit', 'delivered', 'failed', 'declined', 'cancelled')),
  failure_reason TEXT,
  created_at TEXT NOT NULL DEFAULT now_iso(),
  updated_at TEXT NOT NULL DEFAULT now_iso(),
  CHECK (organization_id IS NOT NULL OR rider_id IS NOT NULL)
);
CREATE INDEX idx_delivery_requests_business ON delivery_requests(business_id, status);
CREATE INDEX idx_delivery_requests_org ON delivery_requests(organization_id, status);
CREATE INDEX idx_delivery_requests_rider ON delivery_requests(rider_id, status);

CREATE TABLE delivery_assignments (
  id TEXT PRIMARY KEY,
  delivery_request_id TEXT NOT NULL UNIQUE REFERENCES delivery_requests(id) ON DELETE CASCADE,
  rider_id TEXT REFERENCES logistics_riders(id) ON DELETE SET NULL,
  vehicle_id TEXT REFERENCES logistics_vehicles(id) ON DELETE SET NULL,
  assigned_by_user_id TEXT NOT NULL REFERENCES users(id),
  assigned_at TEXT NOT NULL DEFAULT now_iso(),
  released_at TEXT
);

CREATE TABLE delivery_confirmations (
  id TEXT PRIMARY KEY,
  delivery_request_id TEXT NOT NULL UNIQUE REFERENCES delivery_requests(id) ON DELETE CASCADE,
  confirmed_by_user_id TEXT NOT NULL REFERENCES users(id),
  method TEXT NOT NULL CHECK (method IN ('otp', 'signature', 'photo', 'manual')),
  proof_note TEXT,
  confirmed_at TEXT NOT NULL DEFAULT now_iso()
);
