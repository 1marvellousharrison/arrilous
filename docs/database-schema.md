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

## Reserved for upcoming phases

These tables are **not** created yet; the shapes below are the contract the
migrations will follow.

| Phase | Table | Key columns |
|---|---|---|
| 1 | `businesses` | `id`, `owner_user_id` → `users`, `business_name`, `business_category`, `business_description`, `phone`, `email`, timestamps |
| 2 | `business_locations` | `business_id`, `address`, `city`, `state`, `country`, `latitude`, `longitude`, timestamps |
| 3 | `products` | `business_id`, `name`, `description`, `category`, `price_minor`, `sku`, `stock_quantity`, `image_ref`, `active` |
| 4 | `customers` | `business_id`, `name`, `phone`, `email`, `address`, `notes` |
| 5 | `transactions` | `business_id`, `customer_id`, `transaction_number`, `source` (`manual`/`whatsapp`), `subtotal_minor`, `discount_minor`, `delivery_fee_minor`, `total_minor`, `notes` + the four status columns from Phase 7 |
| 6 | `transaction_items` | `transaction_id`, `product_id` (nullable), `product_name_snapshot`, `quantity`, `unit_price_minor`, `subtotal_minor` |
| 8 | `transaction_status_history` | `transaction_id`, `business_id`, `changed_by_user_id`, `status_type`, `old_value`, `new_value`, `note`, `created_at` |

`product_name_snapshot` on `transaction_items` is what guarantees historical
receipts keep the name and price that were actually charged when the catalog
changes later.
