# API reference

Base URL: `http://localhost:4000/api/v1`
All bodies are JSON. All errors use the envelope:

```json
{ "error": { "code": "unauthorized", "message": "Incorrect email/phone or password." } }
```

Validation failures add `details`, an array of `{ "field", "message" }`.

Protected routes require `Authorization: Bearer <access_token>`.

---

## `GET /health`

No authentication. Used by tooling and Phase 12 dashboards.

```json
{ "status": "ok", "service": "dee-api", "version": "0.1.0",
  "database": "up", "env": "development", "timestamp": "2026-09-30T10:00:00.000Z" }
```

---

## `POST /auth/signup` → `201`

| Field | Type | Rules |
|---|---|---|
| `full_name` | string | required, 2–120 chars |
| `email` | string | required, valid email, lower-cased and trimmed |
| `phone` | string | optional, **full international number** (`+2348031234567`) |
| `password` | string | required, 8–128 chars |
| `role` | enum | `business` (default) \| `logistics_partner` \| `rider` |

```bash
curl -X POST http://localhost:4000/api/v1/auth/signup \
  -H 'content-type: application/json' \
  -d '{"full_name":"Ada Lovelace","email":"ada@example.com","password":"Str0ngPass!23","phone":"+2348031234567","role":"business"}'
```

```json
{
  "token_type": "Bearer",
  "access_token": "eyJhbGciOi...",
  "expires_in": 900,
  "expires_at": "2026-09-30T10:15:00.000Z",
  "refresh_token": "0Zx1k...",
  "refresh_expires_at": "2026-10-30T10:00:00.000Z",
  "user": { "id": "a055e837-...", "fullName": "Ada Lovelace", "email": "ada@example.com",
            "phone": "+2348031234567", "role": "business",
            "emailVerified": false, "phoneVerified": false,
            "createdAt": "2026-09-30T10:00:00.000Z" }
}
```

Errors: `409 email_taken`, `409 phone_taken`, `422 validation_failed`.

> A local-format number such as `08031234567` is rejected — the country code
> cannot be inferred server-side, so the client must submit the full
> international number.

---

## `POST /auth/login` → `200`

| Field | Type | Rules |
|---|---|---|
| `identifier` | string | required — email **or** phone (`+234…`) |
| `password` | string | required |

Returns the same session shape as `signup`.

Errors: `401 unauthorized` (same message for wrong password and unknown
account), `422 validation_failed`, `429 too_many_requests`.

---

## `POST /auth/request-otp` → `201`

| Field | Type | Rules |
|---|---|---|
| `identifier` | string | required — email or phone |
| `channel` | enum | optional `email` \| `sms` (inferred from the identifier) |
| `purpose` | enum | `login_verification` (default) \| `signup_verification` \| `password_reset` |

```json
{ "status": "success", "challenge_id": "c1f2...", "channel": "sms",
  "purpose": "login_verification", "destination": "*********4567",
  "expires_at": "2026-09-30T10:10:00.000Z",
  "dev_code": "482913" }
```

`dev_code` is present **only** in development — no SMS/email provider is wired
up yet, so the API echoes the code and the app shows it in a "Development mode"
banner. It is forced off when `NODE_ENV=production`.

Errors: `409 account_exists` (signup purpose for an existing identifier),
`429 too_many_requests` (45 s resend cooldown per identifier).

---

## `POST /auth/verify-otp` → `200`

| Field | Type | Rules |
|---|---|---|
| `challenge_id` | string | required |
| `code` | string | required, 4–8 digits |

On success returns a session (same shape as `login`) and marks the channel as
verified (`emailVerified` / `phoneVerified`). A login-by-OTP against an unknown
identifier returns `401` — it never creates an account.

Errors: `400` incorrect/expired/already-used code, `404` unknown challenge,
`429` after 5 wrong attempts.

---

## `POST /auth/refresh` → `200`

| Field | Type | Rules |
|---|---|---|
| `refresh_token` | string | required |

Rotates the token: the presented token is revoked and a new pair is issued.
Presenting an already-revoked token revokes every session for that user.

---

## `POST /auth/logout` → `200`

| Field | Type | Rules |
|---|---|---|
| `refresh_token` | string | optional — revoked if present |

Always returns `200`, so signing out works even with an expired token.

---

## `POST /auth/logout-all` 🔒 → `200`

Revokes every active session for the authenticated user.

---

## `GET /auth/me` 🔒 → `200`

```json
{ "user": { "id": "...", "fullName": "...", "email": "...", "role": "business",
            "emailVerified": true, "phoneVerified": false, "createdAt": "..." },
  "active_sessions": 2,
  "sessions": [ { "id": "...", "user_agent": "...", "ip_address": "::1",
                  "expires_at": "...", "created_at": "..." } ] }
```

This is the session every later phase builds on. **Never** read a user id from a
request body — use `requireAuth` and the token's `sub`.

---

## `POST /auth/request-password-reset` → `201`

Body `{ "identifier": "…" }` (optional `channel`). Returns the same shape as
`request-otp` with `purpose: "password_reset"`. Unknown identifiers get a bare
`{ "status": "success" }` with **no** `challenge_id`, so accounts cannot be
discovered. 45 s cooldown.

The app's `AuthRepository.requestPasswordReset` returns `null` for that
no-challenge case, and `ResetPasswordScreen` shows a neutral "if an account
exists…" notice instead of a code entry.

---

## `POST /auth/reset-password` → `200`

| Field | Type | Rules |
|---|---|---|
| `challenge_id` | string | required |
| `code` | string | required, 4–8 digits |
| `new_password` | string | required, 8–128 chars |

On success the password is replaced and **all existing sessions are revoked**.

---

---

## Phases 1-7: business, catalog, customers, transactions

All endpoints below are under `/api/v1`, require `Authorization: Bearer <token>`,
and resolve the business from the **token** — never from an id in the body. A
`business` role is required; `rider` and `logistics_partner` get 403.

An owner with no business gets **404** with a "finish setup" message, because
setup is a next step rather than an authorisation failure.

### Money fields

Every money field ends in `_kobo` and is an integer. On input:

| Sent | Read as |
|---|---|
| number | already kobo (`price_kobo: 1500000`) |
| string | naira (`price_kobo: "15000.50"`) |

A fractional number is rejected (422) because it means naira was sent to a kobo
field.

### Phase 1 — business

| Method | Route | Notes |
|---|---|---|
| `GET` | `/business` | `{ business: null }` before setup |
| `POST` | `/business` | 201; 409 `business_exists` if the owner already has one |
| `PATCH` | `/business` | partial; sends only the fields provided |

`POST` body: `business_name` (required), `business_category`,
`business_description`, `phone`, `email`.

### Phase 2 — location

| Method | Route | Notes |
|---|---|---|
| `GET` | `/business/location` | `{ location: null }` until set |
| `PUT` | `/business/location` | upsert; replaces the existing row |

A staff member may read `GET /business` and `GET /business/location` so their
shell can show the shop's name, logo and pickup address. Every write above stays
owner-only, and `POST /business` still returns `403` for a staff session.

Body: `address` (required), `area`, `city`, `state`, `country`, `latitude`,
`longitude`. `area` is the neighbourhood the shop sits in, kept beside the
street because the delivery partner and rider work from city/area/state — the
app requires `area`, `city` and `state` at setup even though the API accepts
them without it. Latitude and longitude must be sent **together** (422
otherwise). One location per business.

### Phase 3 — products

| Method | Route | Notes |
|---|---|---|
| `GET` | `/products` | `?search=&category=&include_archived=` |
| `GET` | `/products/categories` | distinct active categories |
| `POST` | `/products` | 201; 409 `sku_taken` on a duplicate SKU |
| `GET` | `/products/:id` | |
| `PATCH` | `/products/:id` | partial |
| `POST` | `/products/:id/restock` | body `{ "quantity": 12 }` — **adds** units to the current stock |
| `POST` | `/products/:id/archive` | hides it, keeps transaction history |
| `POST` | `/products/:id/restore` | |
| `DELETE` | `/products/:id` | **400** if used in any transaction — archive instead |

Archived products are hidden unless `include_archived=true`. SKUs are unique per
business, not globally.

`/restock` takes the number of units that arrived, not a new total, and runs
`stock_quantity = stock_quantity + ?` in one statement. Two people restocking at
the same time therefore both land instead of one overwriting the other, and the
owner never has to remember the previous count. `quantity` must be a whole
number of at least 1 (422 otherwise). A successful restock re-syncs the
low-stock alert, so the warning disappears as soon as the shelf is healthy.

#### Digital products

A product is `kind: "physical"` (the default) or `kind: "digital"`. A digital
listing has unlimited stock — `stock_quantity` is always `0`, `/restock` returns
**400**, and it never raises a low-stock alert. It sells an access asset:

| Field | Notes |
|---|---|
| `digital_url` | optional `http(s)` download/access link |
| `digital_instructions` | optional text shown to the buyer |
| `digital_file` | optional upload `{ file_name, mime_type, data_base64 }`, max **6 MB** decoded |
| `clear_digital_file` | PATCH-only flag that removes the current upload |

A digital product must have a link, a file, or both (422 otherwise). The upload
is stored in `digital_files` and the product row points at it. Switching a product
back to `physical` clears its link, instructions and file, pruning the upload once
no sale snapshot needs it. Products return `kind`, `digitalUrl`,
`digitalInstructions`, `digitalFileName` and `hasDigitalFile`.

### Phase 4 — customers

| Method | Route | Notes |
|---|---|---|
| `GET` | `/customers` | `?search=` over name, phone and email |
| `POST` | `/customers` | 201 |
| `GET` | `/customers/:id` | plus `transactionCount`, `totalSpentKobo`, last 50 transactions |
| `PATCH` | `/customers/:id` | partial |

Body: `name` (required), `phone`, `email`, `address`, `notes`. A customer record
is **not** an account — it has no password, role or session.

**A staff has a private customer book.** `GET /customers` and `GET /customers/:id`
return only the customers that staff registered (`created_by_user_id`) or served
(they recorded at least one sale for that customer). The same rule scopes the
`transactionCount`/`totalSpentKobo` figures and the transaction list on the
detail route, so a staff never sees the owner's customer history. Reaching for
someone else's customer returns `404`, not `403`. A staff may still create a
customer, and may attach only a customer inside their own book to a sale; the
owner continues to see the whole book.

### Phase 5-6 — transactions

| Method | Route | Notes |
|---|---|---|
| `POST` | `/transactions` | 201; numbers the sale `TXN-<year>-<00001>` |
| `GET` | `/transactions` | `?search=&attention=&order_status=&payment_status=&delivery_status=&completion_status=&customer_id=&source=&limit=&offset=` |
| `GET` | `/transactions/:id` | with `items` and the customer |

Body: `items[]` (1-200, each with `product_id` **or** `name` + `unit_price_kobo`,
plus `quantity`), optional `customer_id`, `source` (`manual`|`whatsapp`),
`discount_kobo`, `delivery_fee_kobo`, `delivery_required`, `delivery_address`,
`notes`.

Server-computed, never accepted from the client:

- `subtotal_kobo` = sum of `unit_price_kobo * quantity`
- `total_kobo` = subtotal − discount + delivery fee
- a discount larger than the subtotal is **400**

A line referencing a catalog product takes its **name and price from the
catalog**; a payload that tries to set `unit_price_kobo` on it is ignored. Items
store a price snapshot, so a later catalog price change never rewrites history.
Ad-hoc lines (no `product_id`) keep the caller's own name and price.

A digital line snapshots the product's link, instructions and file id on the sale
itself, so editing or replacing the product later cannot change what a past buyer
receives. When **every** line is digital, delivery is forced off: `deliveryRequired`
is `false`, `deliveryAddress` is `null`, and `deliveryStatus` is `not_required`.
A mixed cart requires delivery only because of the physical lines.

### Digital delivery

| Method | Route | Notes |
|---|---|---|
| `POST` | `/transactions/:id/deliver` | emails a **paid** digital sale; body `{ "email": "buyer@example.com" }` optional |

The deliver route is scoped to the sale exactly like the detail route (owner, or
staff for a sale they recorded). It refuses an unpaid sale and a sale with no
digital lines. The response carries `emailSent`, the address used, the buyer's
`publicUrl` and a message. When no mail provider is configured it is honest:
`emailSent: false`, plus the link the owner can share instead.

The buyer's page is unauthenticated and tokenised:

| Method | Route | Notes |
|---|---|---|
| `GET` | `/public/sales/:token` | HTML sale page; until `paymentStatus = paid` it shows a payment notice and **never leaks the asset** |
| `GET` | `/public/sales/:token/items/:itemId/file` | streams the uploaded file; **404** unless the token's sale is paid |

A public token is minted only for a sale that contains digital lines, and detail
responses return it as `publicUrl`. Set `PUBLIC_BASE_URL` (the API base, e.g.
`https://api.example.com/api/v1`) to control that link; otherwise it is derived
from the request host.

### Phase 7 — statuses

Four independent axes, stored as four columns:

| Axis | Values |
|---|---|
| `orderStatus` | `pending` → `confirmed` / `cancelled` |
| `paymentStatus` | `unpaid` → `payment_pending` / `paid` / `failed`; `paid` → `refunded` |
| `deliveryStatus` | `not_required` → `pending` → `accepted` → `picked_up` → `in_transit` → `delivered`; `failed` → `pending` |
| `completionStatus` | `open` → `completed` |

| Method | Route |
|---|---|
| `PATCH` | `/transactions/:id/statuses` |

Send any subset of the four keys. Rules that make the axes coherent:

- an illegal transition is **400** (`pending` cannot go back, `delivered` is final)
- completing requires `paymentStatus: paid` **and** either `not_required` or
  `delivered`
- `deliveryStatus` other than `not_required` requires `delivery_required`
- a cancelled transaction can still be moved to `refunded` **from `paid` only**
  (the payment table has no `payment_pending` → `refunded` edge), but its delivery
  and completion are frozen and it can never be completed
- a completed transaction is frozen: cancelling one is refused, because a
  transaction cannot be both cancelled and completed

### Phase 8 — status history

Every status change is appended to `transaction_status_history`; rows are never
updated or deleted, so the trail is an audit rather than a current-state mirror.

| When | Rows written |
|---|---|
| `POST /transactions` | 4 — one per axis, each with `old_value: null` |
| `PATCH /transactions/:id/statuses` | 1 per axis that actually **moved** |
| a rejected change (400) or a no-op | none |

`GET /transactions/:id` returns the trail alongside the transaction:

```jsonc
{
  "transaction": { /* … */ },
  "customer": null,
  "history": [
    {
      "id": "…",
      "transactionId": "…",
      "statusType": "order",
      "oldValue": null,          // null marks a creation entry
      "newValue": "pending",
      "note": "Transaction created",
      "createdAt": "2026-10-01T09:00:00.000Z"
    }
  ]
}
```

Ordered oldest first. `PATCH /transactions/:id/statuses` accepts an optional
`note` (max 500 chars, trimmed; an empty string is dropped) attached to every row
the request writes.

### Phase 11 — history filters

`GET /transactions` accepts, in addition to the status/source filters above:

| Param | Meaning |
|---|---|
| `from` | `YYYY-MM-DD` or full ISO — `created_at >= from 00:00:00 UTC` |
| `to` | `YYYY-MM-DD` or full ISO — `created_at <= to 23:59:59.999 UTC` |

Both bounds are UTC and inclusive, so a `to` of `2026-10-01` includes everything
recorded that evening. `from > to` is **400**, and an unparseable date is **400**.

Filters are applied in SQL rather than in the client, so `limit`/`offset` page a
filtered set instead of a page that is filtered afterwards.

`attention` is the named view behind the dashboard's "Needs attention" rows.
Each value spans more than one status, which a single status filter cannot
express, and cancelled sales are always left out:

| `attention` | Rows |
|---|---|
| `awaiting_payment` | `payment_status` of `unpaid` or `payment_pending` |
| `to_deliver` | `delivery_status` of `pending`, `accepted` or `picked_up` |
| `on_road` | `delivery_status = 'in_transit'` |
| `failures` | `payment_status = 'failed'` or `delivery_status = 'failed'` |

### Phase 12 — dashboard

| Method | Route | Notes |
|---|---|---|
| `GET` | `/dashboard/summary` | money totals, per-state counts, catalog counts, 8 most recent |
| `GET` | `/dashboard/business` | business name, category and location for the business card |

Both require a signed-in user; `/summary` requires a business, `/business`
requires the owner.

```jsonc
{
  "totals": {
    "transactionCount": 12,
    "grossSalesKobo": 4500000,
    "collectedKobo": 3000000,     // payment_status = 'paid'
    "outstandingKobo": 1500000    // unpaid or payment_pending
  },
  "counts": {
    "pendingOrder": 2, "pendingPayment": 1, "awaitingDelivery": 1,
    "inTransit": 0, "completed": 8, "failed": 0, "cancelled": 1
  },
  "catalog": { "activeProducts": 6, "customers": 3 },
  "recent": [ /* newest first, at most 8 */ ],
  "periods": {
    "today":   { "transactionCount": 3, "grossSalesKobo": 4500000, "collectedKobo": 3000000, "outstandingKobo": 1500000 },
    "week":    { /* last 7 days, including today */ },
    "month":   { /* this calendar month */ },
    "allTime": { /* the whole history in scope */ },
    "months": [
      { "key": "2026-09", "transactionCount": 4, "grossSalesKobo": 6000000, "collectedKobo": 6000000, "outstandingKobo": 0 }
    ]
  }
}
```

`months` lists up to six earlier months that have live sales, newest first, for
the owner's period menu. The current month is not repeated there; it is
`month`. `periods` is returned for owners and staff alike: the owner's windows
cover the whole business, a staff member's cover only the sales they recorded.
`today`, `week` and `month` are bucketed in the caller's own day: the client
sends `?tz_offset_minutes=60` (minutes east of UTC), so a sale at 00:30 in Lagos
is not filed under yesterday. `allTime` stays in the payload for compatibility
even though the app no longer offers it as a window.

A staff member calling `/summary` is scoped to the sales they recorded
(`created_by_user_id`), and the response gains three extra keys:

```jsonc
{
  // ...the same totals/counts/periods/recent as the owner, but staff-scoped...
  // catalog.customers counts only the staff customer book; activeProducts stays shop-wide.
  "staff": {
    "id": "…", "fullName": "Musa Bello", "phone": null,
    "staffCode": "ABC47-03", "status": "active",
    "activatedAt": "2026-01-02T00:00:00.000Z", "salesCount": 12
  },
  "topProducts": [ { "name": "Blue Bag", "quantity": 4, "revenueKobo": 6000000 } ]
}
```

`topProducts` is the five products that staff member sold in the greatest
quantity, excluding cancelled sales.

Two decisions worth knowing before reading a number:

- **A cancelled transaction is excluded from every money total**, because
  counting it as revenue would overstate what was earned. It still has its own
  `counts.cancelled`, so nothing disappears silently. The four actionable counts
  (`pendingPayment`, `awaitingDelivery`, `inTransit`, `failed`) also skip
  cancelled sales, so each "Needs attention" badge matches the list it opens.
- Counts are conditional aggregates over the whole table, not sums of a page, so
  they stay correct however many transactions exist. `catalog` counts only
  products with `active = 1`.
- `logistics` is the delivery workload of the same business: pending requests
  (`requested`/`quoted`), active deliveries (`accepted`/`assigned`/`picked_up`/
  `in_transit`), delivery failures, and how many providers and riders currently
  cover the business's pickup city **and are available** (an expired availability
  window is not counted).

```jsonc
  "logistics": {
    "pendingRequests": 1, "activeDeliveries": 1, "deliveryFailures": 0,
    "nearbyProviders": 1, "nearbyRiders": 1
  }
```

### Staff

Staff accounts (see `docs/staff-accounts.md`) are added by the owner, who never
sets or sees their password: adding one issues a permanent code, and the staff
sets their own password at activation.

| Method | Route | Notes |
|---|---|---|
| `POST` | `/staff` | add a staff and issue their code (`201`); **owner only** |
| `GET` | `/staff` | the business's staff, each with a sales count |
| `GET` | `/staff/:id` | one staff member |
| `PATCH` | `/staff/:id` | rename, re-phone, or disable/re-enable |
| `GET` | `/staff/:id/transactions` | only the sales this staff recorded (newest first, at most 100) |
| `GET` | `/staff/:id/notifications` | the activity this staff member caused (`actor_user_id`), newest first, at most 100 |
| `POST` | `/staff/claim` | public: check an unclaimed code |
| `POST` | `/staff/activate` | public: set the staff password and activate the code |

`GET /staff/:id/notifications` is what the owner's staff page reads beside the
staff member's sales. It is **owner only**: a staff session gets `403`, because a
staff member reads their own inbox through `/notifications`, not through another
person's activity feed.

### Business analysis

| Method | Route | Notes |
|---|---|---|
| `GET` | `/analytics/overview` | `?days=7\|30\|90&tz_offset_minutes=60`; **owner only** (staff get `403`) |

One shaped report covering the whole business for the owner's chosen window.
The client draws the report; the server owns every aggregate, so no figure is a
sum of a paginated list.

```jsonc
{
  "range":  { "days": 30, "start": "…", "end": "…", "tzOffsetMinutes": 60 },
  "totals": { "revenueKobo": 4500000, "orders": 12, "averageOrderKobo": 375000,
              "collectedKobo": 3000000, "outstandingKobo": 1500000 },
  "previous": { /* same shape, the window immediately before this one */ },
  "daily":    [ { "date": "2026-02-01", "revenueKobo": 120000, "orders": 2 } ],
  "weekdays": [ { "weekday": 0, "label": "Sun", "revenueKobo": 0, "orders": 0 } ],
  "hours":    [ { "hour": 0, "revenueKobo": 0, "orders": 0 } ],
  "peakHour": { "hour": 14, "revenueKobo": 900000, "orders": 3 },
  "topProducts": [ { "name": "Blue Bag", "quantity": 4, "revenueKobo": 6000000 } ],
  "paymentMix":  [ { "status": "paid", "count": 8, "amountKobo": 3000000 } ],
  "orderMix":    [ { "status": "pending", "count": 3 } ],
  "deliveryMix": [ { "status": "delivered", "count": 6 } ],
  "customers": { "buyers": 5, "newCustomers": 2, "returning": 3,
                 "walkInOrders": 1, "top": [ { "name": "Ada", "orders": 4, "spentKobo": 900000 } ] },
  "inventory": { "activeProducts": 9, "inventoryValueKobo": 12000000,
                 "lowStock": 2, "outOfStock": 1,
                 "products": [ { "name": "Thread", "stockQuantity": 2, "severity": "warning" } ] },
  "logistics": { "requests": 6, "delivered": 5, "failed": 1, "successRate": 83 },
  "generatedAt": "…"
}
```

Every day in the window appears in `daily`, including quiet days, so the trend
line is continuous. Cancelled sales are excluded from money and order figures
(and still counted in `orderMix`). `successRate` is `null` until a delivery has
finished one way or the other, rather than pretending to be `0%`.

---

## Logistics (integrated spec v3)

All routes are under `/api/v1` with the same bearer auth. Three roles meet here:

| Route group | Who |
|---|---|
| `/logistics/providers`, `/logistics/requests` (POST/PATCH business side) | `business` |
| `/logistics/organization*`, `/logistics/requests/:id/assign`, `/logistics/requests/:id/quote` | `logistics_partner` |
| `/logistics/rider*`, `/logistics/requests/:id/status` | `rider` |

Roles are enforced per route with `requireRole(...)`; the wrong role gets **403**.
`GET /logistics/requests/:id` and `/logistics/requests/:id/events` are the exception:
all three roles can read them **only if they are part of that delivery**, and anyone
else gets **404** rather than a hint that the delivery exists.
A partner with no organization profile gets **404** on `GET /logistics/organization`
(not 500) so the app can show the setup step. Validation failures are **422**,
missing resources **404**, illegal state changes **400**.

### Network, coverage and matching

| Method | Route | Notes |
|---|---|---|
| `GET`/`POST` | `/logistics/organization` | profile; `POST` creates it (`name`, `phone`, `category`, `description` required, `email` optional) |
| `GET`/`POST` | `/logistics/organization/areas` | service areas — `city`, `area`, `state`, `latitude`, `longitude`, `radius_km` |
| `GET`/`POST` | `/logistics/organization/pricing` | published fee per `destination` city (`price_kobo`) |
| `GET`/`POST`/`PATCH` | `/logistics/organization/vehicles[/id]` | fleet: `vehicle_type`, `total_quantity`, `available_quantity`, `capacity_category`, `starting_price_kobo` |
| `GET`/`PATCH` | `/logistics/organization/riders` | roster with active job counts |
| `GET`/`POST` | `/logistics/rider` | rider profile; `POST` creates it (`phone`, `category`, `description` required) |
| `POST` | `/logistics/rider/areas`, `/logistics/rider/modes` | rider coverage and delivery modes |
| `PATCH` | `/logistics/organization/availability`, `/logistics/rider/availability` | `{ "is_available": true, "availability_expires_at": "<today>17:00Z" }` — the exact time of day to work until becomes the closing time (options noon → 7pm, any time allowed). `planned_hours` is an alternative form; the plan is kept/derived as `plannedHours` with `availabilityStartedAt` so the day plan survives reloads. Default is a fixed 8 hours |
| `POST` | `/logistics/organization/availability/extend`, `/logistics/rider/availability/extend` | `{ "minutes": ±30 }` — signed: `+` lengthens the shift, `-` trims it; trimming below the time left closes the shift (0 is rejected) |
| `GET` | `/logistics/providers?destination_city=&package_size=&preferred_mode=` | **business only** |

`GET /logistics/providers` is the matcher (spec 14/15/19). It requires
`destination_city`, and ranks candidates in this order (spec 15):

1. covering the **same state** as the business pickup location,
2. covering the **same town** as the business pickup location,
3. straight-line (haversine) distance from the business's coordinates,

and only returns organizations/riders that:

1. cover **both** the pickup city and the destination city,
2. are available now (`availability_expires_at` in the future or unset),
3. have at least one free vehicle whose `capacity_category` can carry
   `package_size` (a provider with zero available vehicles is excluded).

The response is `{ "providers": [ … ], "riders": [ … ] }`, each entry carrying
`distanceKm`, `serviceAreas`, `vehicles` and published `pricing` so the client
shows rates without a second request.

### Delivery lifecycle

| Method | Route | Notes |
|---|---|---|
| `POST` | `/logistics/requests` | business requests delivery for a `transaction_id`; destination city is derived from `delivery_address` |
| `GET` | `/logistics/requests` | visible requests for the signed-in role |
| `GET` | `/logistics/requests/:id` | one delivery for its participants (business owner, organization owner, assigned rider) - pickup point (street, `area`, city, state as the owner typed them), destination, `business` (`name`, `ownerName`, `phone` so the shop can be called), customer, rider, organization, totals and the event trail, with names and phone numbers; anyone else gets `404` |
| `GET` | `/logistics/requests/:id/events` | append-only event trail |
| `PATCH` | `/logistics/requests/:id/quote` | partner quotes (`quoted_price_kobo`) |
| `PATCH` | `/logistics/requests/:id/accept-quote` | business accepts a quote |
| `PATCH` | `/logistics/requests/:id/assign` | partner assigns rider + vehicle; implies `accepted` |
| `PATCH` | `/logistics/requests/:id/status` | `requested → accepted → picked_up → in_transit → delivered/failed` |
| `POST` | `/logistics/requests/:id/otp` | proof-of-delivery OTP for the recipient |
| `POST` | `/logistics/requests/:id/confirm` | confirm delivery (payment is a separate axis) |
| `POST` | `/logistics/requests/:id/retry` | business retries a failed/declined/cancelled request |

Rules the routes enforce rather than trusting the caller:

- Assigning a request **restores any previously held vehicles** before checking
  out new ones, and reaching a terminal status (`delivered`, `failed`,
  `declined`, `cancelled`) or retrying releases them — the fleet never leaks.
- Assigning also moves the transaction's `delivery_status` out of `pending`, so
  the transaction axis and the delivery request cannot disagree.
- A re-assignment (`accepted`/`assigned` → `assigned`) is allowed; the status
  guard is widened for that case only.
- Delivery completion never touches payment or order status: `payment ≠
  completion` stays true on both axes.
- Availability expiry affects **only new matching** — requests already assigned
  keep their rider.

### Notifications

| Method | Route | Notes |
|---|---|---|
| `GET` | `/logistics/notifications` | `{ notifications, unreadCount }` for the signed-in user |            
| `GET` | `/logistics/organization/earnings` | `{ earningsKobo, history[] }` - completed deliveries and the money they earned | 
| `GET` | `/logistics/rider/earnings` | `{ earningsKobo, history[] }` - the rider's completed deliveries |
| `POST` | `/logistics/notifications/read-all` | marks every unread delivery alert for this user read (`200`) |
| `PATCH` | `/logistics/notifications/:id/read` | marks one read (`204`) |

Delivery events (requested, quoted, assigned, status changes) write a row here
for each stakeholder, and the in-app inbox reads it — no third-party delivery
channel is involved (see `docs/future-integrations.md`).

### In-app notifications

The general inbox carries app alerts (sales, payment/status updates, restocks,
draft warnings, import failures) alongside delivery activity in the Profile tab.
It is a complete history, not a sampled feed: the page filters it by Today,
7 days, 30 days, this year or all time on the client, and groups rows by day (or
by month for the wider windows).

| Method | Route | Notes |
|---|---|---|
| `GET` | `/notifications` | `{ notifications, unreadCount, counts, lowStock }`; `?limit=` 1-500 (default 500) |
| `PATCH` | `/notifications/:id/read` | marks one read (`200`) |
| `POST` | `/notifications/read-all` | clears **routine** alerts; low-stock and `error` alerts stay unread (`200`) |

**Audience.** `user_id` is the audience scope, not the author:

- `user_id IS NULL` — business-wide news (sales, status changes, restocks);
- `user_id = <id>` — a message for that one user (their own drafts and uploads);
- `actor_user_id` — who caused the event, so the owner can see "by Musa".

A staff inbox holds only rows where `user_id` is their own; the business-wide
rows (`user_id IS NULL`) belong to the owner. The owner is the business and sees
every row in their inbox, including staff-only draft alerts. Read and read-all
enforce the same scope: a staff member cannot clear another person's message,
and opening their own inbox no longer marks the owner's alerts read. The response gains `actorUserId`/`actorName` on rows that have
an author.

`GET /notifications` also self-heals the shelf: it raises one open alert per low
product and resolves an alert whose product has been restocked, archived or
deleted. The `lowStock` summary (and `counts.lowStock`) stays shop-wide for the
owner and staff alike — it describes the shelf, not a personal message — while
the `low_stock` inbox rows themselves belong to the owner. The response looks
like:

```jsonc
{
  "notifications": [ /* newest first, at most 500 by default */ ],
  "unreadCount": 4,
  "counts": { "unread": 4, "lowStock": 2, "outOfStock": 1, "errors": 1, "warnings": 3 },
  "lowStock": {
    "count": 2,
    "outOfStock": 1,
    "products": [ { "id": "…", "name": "Thread", "stockQuantity": 0, "severity": "error" } ]
  }
}
```

Events currently emitted: `sale_recorded` (manual and screenshot sales, including
staff sales with `actorName`), `sale_status` (payment/order/delivery changes),
`restock`, AI `order_draft` ready/incomplete, and `order_import_failed`. Sale and
status events carry the `transactionId`; restocks carry `productId`; draft alerts
carry `orderImportId`. Tapping a row opens the source record and marks it read.

`counts.lowStock` is counted from the shelf itself, not from unread rows, so the
warning survives a cleared bell and disappears only when the product is healthy.

Opening the inbox counts as reading it, so `read-all` clears routine alerts
without a tap per row. Two kinds deliberately survive: `low_stock` alerts (they
disappear only when the product itself is healthy) and anything with
`severity = 'error'`. An explicit `{ "include_important": true }` clears
everything. Because a still-low product re-raises its alert on the next read,
attending to the stock is the only way to make the warning stay away.

### AI / screenshot import

`GEMINI_API_KEY` stays on the server. Uploads are queued and read in the
background, so the HTTP request never waits for the vision model.

| Method | Route | Notes |
|---|---|---|
| `POST` | `/ai/import` | queues an image (`202`); re-uploading the same image within 15 minutes returns the existing draft (`200`, `deduplicated: true`) |
| `GET` | `/ai/imports` | every draft for the business |
| `GET` | `/ai/imports/:id` | one draft — poll this until `status` leaves `processing` |
| `POST` | `/ai/imports/:id/complete` | confirms the draft and records the sale |
| `DELETE` | `/ai/imports/:id` | deletes a draft that has not become a sale (`204`); a recorded sale is refused (`400`) |
| `GET` | `/ai/chat` | the chat thread, including image and draft messages |
| `GET` | `/ai/customers/match` | finds a saved customer by `name` or `phone` |

**Every AI route is user-scoped.** A staff member sees only the messages,
drafts, and imports they uploaded; reading, deleting or completing another
person's draft returns `404`, not `403`, so the draft's existence is not leaked.
The owner is business-wide and still sees every staff member's drafts. This is
why each staff member has their own AI/Chats tab: a draft is working material,
not shared business news.

Customer matching follows the staff customer book too: `/ai/customers/match`,
the review pre-fill and the customer chosen on an import are restricted to the
customers that staff registered or served. A staff never matches or links an
import to the owner's wider customer book.

Screenshots travel as a base64 `imageDataUrl` in the JSON body. The request body
limit is **12 MB**; a larger upload returns `413 payload_too_large` with a
readable message instead of a generic server error, so the client can tell the
user to retry a smaller image.

Catalog prices and names win over anything the model reads: the server rematches
each line against the catalog before the draft is shown. Phone numbers are
normalized to `+234` E.164, and a provided number that is not a complete
Nigerian mobile is refused with `400` on `customer_phone`.

## Rate limits

Per IP, per route, in-memory (per process — see the note in
`middleware/rateLimit.js`).

| Route | Limit |
|---|---|
| `/auth/signup` | 20 / 15 min |
| `/auth/login` | 20 / 15 min |
| `/auth/request-otp` | 10 / 15 min, plus a 45 s per-identifier cooldown |
| `/auth/verify-otp` | 15 / 15 min, plus 5 attempts per challenge |
| `/auth/request-password-reset`, `/auth/reset-password` | 10 / 15 min |

`RATE_LIMIT_MAX` and `RATE_LIMIT_WINDOW_MS` override the defaults.
