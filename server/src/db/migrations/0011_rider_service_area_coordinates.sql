-- Spec 19 — riders define service areas the same way organizations do, and the
-- matcher needs their coordinates to rank riders by distance from the business.
ALTER TABLE rider_service_areas ADD COLUMN latitude REAL;
ALTER TABLE rider_service_areas ADD COLUMN longitude REAL;
ALTER TABLE rider_service_areas ADD COLUMN radius_km REAL;
