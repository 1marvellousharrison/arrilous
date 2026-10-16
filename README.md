# Biziness — Your Business, Simplified

Mobile-first business operations app: **customer conversation → order → product
availability → payment → delivery → delivery confirmation → completed
transaction**.

Product/UI spec: [`business_management_app_ui_spec.md`](business_management_app_ui_spec.md)
Build order: [`phase_build_prompt.md`](phase_build_prompt.md)

## Current status

| Phase | Scope | Status |
|---|---|---|
| 0 | Inspect existing project | Done — no prior app/backend existed |
| A | **Authentication foundation** (signup/login/OTP/sessions) | Done |
| 1 | Business profile | Done — API + Flutter setup step 1 |
| 2 | Business location | Done — API + Flutter step 2, GPS with manual fallback |
| 3 | Product catalog | Done — CRUD, search, category filter, archive |
| 4 | Customers | Done — CRUD, search, spend summary |
| 5 | Transaction core | Done — API/domain only (UI arrives in Phase 9) |
| 6 | Items + server-side totals | Done — prices always come from the catalog |
| 7 | Independent status axes | Done — order/payment/delivery/completion |
| 8 | Transaction status history | Done — append-only `transaction_status_history`, timeline on detail |
| 9 | Manual transaction UI | Done — catalog and one-off lines, charges, delivery, notes |
| 10 | Transaction detail | Done — money, items, customer, timeline, legal status actions |
| 11 | Transaction history screen | Done — search, date range, per-axis filters, server-side paging |
| 12 | Home dashboard | Done — real aggregates from `GET /dashboard/summary` |
| 13 | Security / tenant isolation | Done — ownership resolved from the token, cross-tenant tests in every suite |
| 14 | Future integration architecture | Done — inert `services/` boundaries: WhatsApp, Payment, Logistics, Notification |
| 15 | Business rules & validation | Done — Zod schemas, transition table, cross-axis rules, ownership checks |
| 16 | Testing | Done — 228 server tests, 174 Flutter tests (see below) |
| 17 | Development seed data | Done — `npm run seed` builds the ABC Fashion Store scenarios + a logistics network |
| 18 | Documentation | Done — architecture, schema, API, environment, integrations |
| — | **Integrated spec v3 (logistics)** | Done — org/rider accounts, availability, fleet, pricing, matching, delivery lifecycle, business/partner/rider dashboards, in-app notifications |

WhatsApp AI and payment gateways remain deliberately inactive (see
`docs/future-integrations.md`). The logistics network is **local and live**:
partner and rider accounts, service-area + distance matching, fleet with
assignment/restore, published-quoted-accepted pricing, the full delivery
lifecycle with OTP confirmation, and dashboards for all three roles. Connecting
a third-party fleet (`LOGISTICS_PROVIDER`) remains future work.

Two boundaries worth stating outright rather than leaving to be discovered:

- **Stock is not decremented by a sale.** The spec puts stock checking on the
  owner ("the business owner can verify stock first") and lists automated stock
  as a future feature, so the app refuses to let an owner pick an out-of-stock
  product in the picker but neither the client nor the API adjusts
  `stock_quantity`. Restock remains a product edit.
- **The app never sends a total.** Line prices for catalog products are read back
  from the database by the server, so a stale price in the UI cannot become the
  price of record.

- **Wallet** — balance, virtual account, card funding, and OTP-confirmed payouts.
  Available to business owners and logistics partners/riders.

## Repository layout

```
dee/
├─ server/                     Node 26 + Express 5 + node:sqlite API
│  ├─ src/
│  │  ├─ config.js             env loading + production guards
│  │  ├─ app.js                express app factory (used by server + tests)
│  │  ├─ server.js             process entry point
│  │  ├─ db/
│  │  │  ├─ index.js           connection, pragmas, query helpers, transactions
│  │  │  ├─ migrate.js         `npm run migrate`
│  │  │  ├─ seed.js            `npm run seed` (dev data, refuses production)
│  │  │  └─ migrations/*.sql   forward-only, applied in filename order
│  │  ├─ lib/                  password (scrypt), jwt, validators, errors,
│  │  │                        money (kobo), statuses (Phase 7 rules),
│  │  │                        history (Phase 8 status trail)
│  │  ├─ services/             Phase 14 extension points (inert): whatsapp,
│  │  │                        payments, logistics, notifications + registry
│  │  ├─ middleware/           requireAuth, requireBusiness, requireRole, rateLimit,
│  │  │                        error envelope
│  │  └─ routes/               auth, business, products, customers, transactions,
│  │                           dashboard, logistics (matching + delivery lifecycle)
│  └─ tests/                   node:test suites
├─ app/                        Flutter 3.47 mobile client (Android/iOS/Web)
│  └─ lib/
│     ├─ core/api/              ApiClient (GET/POST/PUT/PATCH/DELETE), error types
│     ├─ core/services/         device location (geolocator, with failure reasons)
│     ├─ core/state/            Auth, Business, Catalog, Customer, Transaction,
│     │                         Dashboard, Logistics repositories
│     ├─ core/theme/            orangered / #ddd / charcoal-dark theme
│     ├─ core/utils/            kobo <-> naira formatting and parsing
│     ├─ features/auth/         login, account type, sign-up, OTP verify, password reset
│     ├─ features/business/     two-step business + location setup
│     ├─ features/products/     catalog list and product form
│     ├─ features/customers/    customer list, form, detail
│     ├─ features/transactions/ new sale, history list, detail + timeline
│     ├─ features/logistics/    business logistics (match + requests) and the
│     │                         partner/rider workspace dashboards
│     ├─ features/settings/     settings incl. light/dark switch
│     └─ features/home/         shell (Home | Sales | Products | Customers) + dashboard
└─ docs/                       architecture, schema, API, env, integrations
```

## Running it

**1. API**

```bash
cd server
npm install
cp .env.example .env        # then set JWT_SECRET (see docs/environment.md)
npm run migrate             # applies server/src/db/migrations/*.sql
npm run seed                # optional: dev data (never in production) — see below
npm run dev                 # http://localhost:4000
```

`npm run seed` builds three demo accounts, all with the same password:

| Role | Email | Sees |
|---|---|---|
| `business` | `owner@abcfashion.test` | ABC Fashion Store: catalog, sales, dashboard, delivery requests |
| `logistics_partner` | `partner@swiftmove.test` | SwiftMove Logistics: fleet, riders, coverage, pricing, requests |
| `rider` | `rider@swiftmove.test` | Rider workspace: availability, modes, active delivery, history |

Health check: `GET http://localhost:4000/api/v1/health`

**2. App**

```bash
cd app
flutter pub get
flutter run                                        # emulator / device
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:4000/api/v1   # physical device
```

## Tests

```bash
cd server && npm test     # 228 tests
cd app    && flutter test # 174 tests
cd app    && flutter analyze
```

| Suite | Covers |
|---|---|
| `server/tests/auth.test.js`, `session.test.js` | auth, tokens, sessions, OTP, reset, prod guards |
| `server/tests/business.test.js` | Phases 1–2: one business per owner, location upsert, coordinates |
| `server/tests/products.test.js` | Phase 3: kobo parsing, SKU uniqueness, archive, isolation |
| `server/tests/customers.test.js` | Phase 4: validation, search, spend summary, isolation |
| `server/tests/transactions.test.js` | Phases 5–7: totals, snapshots, status rules, cross-tenant |
| `server/tests/status_history.test.js` | Phase 8: trail on create, diffed updates, notes, chronology |
| `server/tests/dashboard.test.js` | Phases 11–12: date filters, aggregates, catalog counts, isolation |
| `server/tests/integrations.test.js` | Phase 14: boundaries exist, are inert, attempt no network call |
| `server/tests/logistics.test.js`, `logistics_operations.test.js` | spec v3: coverage/distance matching, fleet assignment + restore, lifecycle, quotes, OTP, notifications, 403/404/422 contract |
| `server/tests/seed.test.js` | Phase 17: scenario set, logistics network, server-consistent totals, idempotent, prod guard |
| `app/test/money_test.dart` | kobo <-> naira round trip, sub-cent rejection |
| `app/test/business_repositories_test.dart` | repository parsing, query params, no client totals |
| `app/test/business_screens_test.dart` | setup flow, location fallback, form validation |
| `app/test/transaction_repositories_test.dart` | sale posting, filters, paging, detail, legal actions |
| `app/test/transaction_screens_test.dart` | dashboard, history, new sale, detail + timeline |
| `app/test/logistics_screens_test.dart` | spec 6/41/42/43/44: dashboard logistics strip, entry options, both workspaces, provider cards |

## Money is never a float

Every column and JSON field carries a `_kobo` suffix, and the value is an integer.
Two input shapes mean different things on purpose, on both client and server:

| Sent | Read as | Example |
|---|---|---|
| JSON **number** | already kobo | `price_kobo: 1500000` = ₦15,000.00 |
| **string** | naira typed by a human | `price_kobo: "15000.50"` = ₦15,000.50 |

A fractional number in a `_kobo` field is rejected: it means the caller sent
naira where kobo was expected, which would silently cost 100×.

Transaction totals are **never** accepted from a client. `subtotal` and `total`
are recomputed on the server from the item prices, and a line that references a
catalog product takes its name and price from the catalog, not from the payload.

## Design rules applied

| Rule | Value |
|---|---|
| Primary UI colour | `orangered` `#FF4500` |
| Light background | `#DDDDDD` |
| Dark background | `#1E1E22` — dark charcoal, **not** pure black |
| Light/dark switch | Settings → Appearance → "Dark mode" (persisted) |

Docs: [`docs/architecture.md`](docs/architecture.md) ·
[`docs/api.md`](docs/api.md) ·
[`docs/database-schema.md`](docs/database-schema.md) ·
[`docs/environment.md`](docs/environment.md) ·
[`docs/future-integrations.md`](docs/future-integrations.md)
