# Database schema

Engine: SQLite via the built-in `node:sqlite` driver.
Migrations live in `server/src/db/migrations/` and are applied in filename
order by `npm run migrate`, each inside a transaction and recorded in
`_migrations`. Never edit an applied migration — add a new one.

Connection pragmas: `journal_mode = WAL`, `foreign_keys = ON`,
`busy_timeout = 5000`.

Timestamps are ISO-8601 UTC strings (`strftime('%Y-%m-%dT%H:%M:%fZ','now')`).
Money will be stored as integer minor units (kobo) from Phase 5 onwards — never
as floating point.

---

## `0001_auth_foundation.sql`

### `users`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `full_name` | TEXT | |
| `email` | TEXT | UNIQUE, normalised lowercase |
| `phone` | TEXT | UNIQUE, E.164 (`+234…`); NULL allowed |
| `password_hash` | TEXT | `scrypt$N$r$p$saltHex$hashHex` |
| `role` | TEXT | `business` \| `logistics_partner` \| `rider` |
| `status` | TEXT | `active` \| `suspended` |
| `email_verified_at` | TEXT | NULL until an email OTP is verified |
| `phone_verified_at` | TEXT | NULL until an SMS OTP is verified |
| `last_login_at` | TEXT | |
| `created_at` / `updated_at` | TEXT | |

CHECK constraints enforce the two enums, non-empty name/email, and a non-empty
password hash. `phone` is UNIQUE but nullable — SQLite permits many NULLs, which
is exactly the behaviour needed.

### `refresh_tokens`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | |
| `user_id` | TEXT FK | → `users(id)` `ON DELETE CASCADE` |
| `token_hash` | TEXT | UNIQUE — SHA-256 of the token; the token itself is never stored |
| `user_agent` / `ip_address` | TEXT | best-effort audit trail |
| `expires_at` | TEXT | |
| `revoked_at` | TEXT | NULL while active |
| `created_at` | TEXT | |

Indexed on `user_id` and `expires_at`.

### `otp_challenges`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | the `challenge_id` returned to the client |
| `identifier` | TEXT | normalised email or phone |
| `channel` | TEXT | `email` \| `sms` |
| `purpose` | TEXT | `signup_verification` \| `login_verification` \| `password_reset` |
| `code_hash` | TEXT | SHA-256 of `identifier:code` — codes are never stored in the clear |
| `attempts` / `max_attempts` | INTEGER | lockout after 5 wrong tries |
| `user_id` | TEXT FK | NULL for signup purposes |
| `expires_at` | TEXT | default 10 minutes |
| `consumed_at` | TEXT | set on successful verification, making the code single-use |
| `created_at` | TEXT | |

Indexed on `(identifier, purpose)` and `expires_at`.

---

## `0009_logistics_network.sql` / `0010_logistics_operations.sql` / `0011_rider_service_area_coordinates.sql`

The local logistics network (integrated spec v3). Delivery state references the
existing `transactions` row instead of copying its money or customer data.

### `logistics_organizations`

| Column | Type | Notes |
|---|---|---|
| `owner_user_id` | TEXT FK | UNIQUE → `users(id)` `ON DELETE CASCADE` — one org per partner account |
| `name`, `phone`, `email`, `description` | TEXT | public profile |
| `is_available` | INTEGER | 0/1; the availability switch (spec 39) |
| `availability_started_at` / `availability_expires_at` | TEXT | expiry stops **new matching only** |
| `planned_hours` | REAL | the day's shift length, kept for display — derived from the chosen "work until" closing time at activation |

### `logistics_service_areas`

`organization_id` FK cascade, plus `city`, `area`, `state`, `country`,
`latitude`, `longitude`, `radius_km`. Coverage is matched on `city` (case
insensitive); coordinates feed the haversine ranking in
`GET /logistics/providers`. `rider_service_areas` has the same shape keyed by
`rider_id`, added in `0011`.

### `logistics_pricing`

`organization_id`, `destination` (city), `price_kobo` INTEGER, optional
`vehicle_type`; `UNIQUE(organization_id, destination, vehicle_type)`.

### `logistics_vehicles`

| Column | Type | Notes |
|---|---|---|
| `vehicle_type` | TEXT | `motorcycle` \| `tricycle` \| `car` \| `van` \| `pickup` \| `truck` \| `other` |
| `total_quantity` / `available_quantity` | INTEGER | `available ≤ total`; assignments decrement `available`, terminal statuses restore it |
| `capacity_category` | TEXT | `small` \| `medium` \| `large` \| `very_large` |
| `starting_price_kobo` | INTEGER | from-price shown on provider cards |

### `logistics_riders`

`user_id` UNIQUE FK, `organization_id` FK `ON DELETE SET NULL`, availability
columns mirroring the organization (including `planned_hours`), and (from
`0010`) current GPS position columns. `rider_delivery_modes` holds `mode`,
`capacity_category`, `rate_kobo`, `is_primary`.

### `delivery_requests`

| Column | Type | Notes |
|---|---|---|
| `transaction_id` | TEXT FK | UNIQUE — one request per transaction |
| `business_id` / `organization_id` / `rider_id` | TEXT FK | CHECK: at least one of org/rider is set |
| `pickup_*` / `destination_*` | TEXT | `destination_city` is derived from the address |
| `package_size` | TEXT | `small` … `very_large` |
| `published_price_kobo` / `quoted_price_kobo` / `accepted_price_kobo` | INTEGER | three moments of the same price |
| `status` | TEXT | `requested` \| `quoted` \| `accepted` \| `assigned` \| `picked_up` \| `in_transit` \| `delivered` \| `failed` \| `declined` \| `cancelled` |
| `failure_reason` | TEXT | kept visible after a failure |

### `delivery_assignments`, `delivery_confirmations`, `delivery_request_events`, `delivery_confirmation_otps`

- `delivery_assignments` — UNIQUE per request, `rider_id`, `vehicle_id`,
  `released_at` (NULL while the vehicle is checked out).
- `delivery_confirmations` — proof of delivery (`otp` \| `signature` \| `photo`
  \| `manual`) with the confirming user.
- `delivery_request_events` — append-only trail: `actor_user_id`, `event_type`,
  `note`.
- `delivery_confirmation_otps` — hashed code, expiry, single use.

### `logistics_notifications`

`user_id` FK cascade, optional `delivery_request_id`, `kind`, `title`, `body`,
`read_at` — the in-app inbox behind the badge (spec 27).

---

## Migration index

| Migration | Tables |
|---|---|
| `0001_auth_foundation` | `users`, `refresh_tokens`, `otp_challenges` |
| `0002_businesses`, `0003_business_locations` | `businesses`, `business_locations` |
| `0004_products`, `0004b_customers` | `products`, `customers` |
| `0005_transactions`, `0006_transaction_items` | `transactions`, `transaction_items` |
| `0007_statuses` | the four status columns on `transactions` (with their CHECKs) |
| `0008_transaction_status_history` | `transaction_status_history` |
| `0009_logistics_network` | `logistics_organizations`, `logistics_service_areas`, `logistics_pricing`, `logistics_vehicles`, `logistics_riders`, `rider_service_areas`, `rider_delivery_modes`, `delivery_requests`, `delivery_assignments`, `delivery_confirmations` |
| `0010_logistics_operations` | `logistics_notifications`, `delivery_request_events`, `delivery_confirmation_otps`, rider GPS columns |
| `0011_rider_service_area_coordinates` | `latitude`/`longitude`/`radius_km` on `rider_service_areas` |
| `0012_profile_details` | `category` on `logistics_organizations`; `phone`, `category`, `description` on `logistics_riders` |
| `0013_planned_hours` | `planned_hours` on `logistics_organizations` and `logistics_riders` — the day's shift, kept for display and re-planning |
| `0014_business_location_area` | `area` on `business_locations` — the pickup location as the owner types it, for the delivery partner |

Every money column is `*_kobo` INTEGER (see the API's money-field contract);
`product_name_snapshot` on `transaction_items` is what guarantees historical
receipts keep the name and price that were actually charged when the catalog
changes later.
