-- Business details for logistics — the delivery partner needs the pickup
-- location as the owner types it (city, area, state), so the area the shop
-- sits in is stored beside the street address.
ALTER TABLE business_locations ADD COLUMN area TEXT;
