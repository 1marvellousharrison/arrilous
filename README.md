# Business Hub — Small Business Management App

Mobile-first business operations app: **customer conversation → order → product
availability → payment → delivery → delivery confirmation → completed
transaction**.

Product/UI spec: [`business_management_app_ui_spec.md`](business_management_app_ui_spec.md)
Build order: [`phase_build_prompt.md`](phase_build_prompt.md)

## Current status

| Phase | Scope | Status |
|---|---|---|
| 0 | Inspect existing project | Done — no prior app/backend existed |
| A | **Authentication foundation** (signup/login/OTP/sessions) | **Done — awaiting approval** |
| 1 | Business profile | Not started |
| 2 | Business location | Not started |
| 3–18 | Products → docs | Not started |

WhatsApp AI, payment gateways and logistics integrations are **deliberately not
built yet** (see `docs/future-integrations.md`).

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
│  │  │  └─ migrations/*.sql   forward-only, applied in filename order
│  │  ├─ lib/                  password (scrypt), jwt, validators, errors, normalise
│  │  ├─ middleware/           requireAuth, rateLimit, error envelope
│  │  └─ routes/auth.js        all /api/v1/auth endpoints
│  └─ tests/                   node:test suites
├─ app/                        Flutter 3.47 mobile client (Android/iOS/Web)
│  └─ lib/
│     ├─ core/api/              ApiClient, error types, session models
│     ├─ core/state/            AuthRepository, ThemeController
│     ├─ core/theme/            orangered / #ddd / charcoal-dark theme
│     ├─ features/auth/         login, account type, sign-up, OTP verify, password reset
│     ├─ features/settings/     settings incl. light/dark switch
│     └─ features/home/         temporary post-login shell
└─ docs/                       architecture, schema, API, env, integrations
```

## Running it

**1. API**

```bash
cd server
npm install
cp .env.example .env        # then set JWT_SECRET (see docs/environment.md)
npm run migrate             # applies server/src/db/migrations/*.sql
npm run dev                 # http://localhost:4000
```

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
cd server && npm test     # 66 tests — auth, tokens, sessions, OTP, reset, isolation, prod guards
cd app    && flutter test # 45 tests — theme tokens, theme switch, auth repository, auth screens
cd app    && flutter analyze
```

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
