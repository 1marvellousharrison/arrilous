# Environment variables

Server config lives in `server/src/config.js`. Values in the real process
environment always win over `.env`, so CI and hosting can override without code
changes. Copy `server/.env.example` to `server/.env` for local work.

## Secrets

### `JWT_SECRET` — **required in production**

The server refuses to boot when `NODE_ENV=production` and this is missing or
empty. Generate one:

```bash
node -e "console.log(require('node:crypto').randomBytes(48).toString('base64url'))"
```

Rotating it invalidates every issued access token (refresh tokens survive,
because they are opaque and database-backed).

Never commit `.env` — it is already in `server/.gitignore`.

## Runtime

| Variable | Default | Notes |
|---|---|---|
| `NODE_ENV` | `development` | `production` enables the strict secret check and disables the dev OTP echo |
| `HOST` | `0.0.0.0` | |
| `PORT` | `4000` | |
| `CORS_ORIGINS` | `*` outside production, **required in production** | Comma-separated allow-list, e.g. `https://app.example.com`. The server refuses to boot when `NODE_ENV=production` and this is missing, empty, or `*`. |

## Database

| Variable | Default | Notes |
|---|---|---|
| `DATABASE_PATH` | `./data/app.db` | Use `:memory:` for throwaway runs |

## Tokens

| Variable | Default | Notes |
|---|---|---|
| `JWT_ISSUER` | `dee-api` | Checked on every token verification |
| `JWT_AUDIENCE` | `dee-app` | Checked on every token verification |
| `JWT_ACCESS_TTL` | `900` (15 min) | Seconds |
| `JWT_REFRESH_TTL` | `2592000` (30 days) | Seconds |

## One-time codes

| Variable | Default | Notes |
|---|---|---|
| `OTP_TTL` | `600` (10 min) | Seconds a code stays valid |
| `OTP_EXPOSE_IN_RESPONSE` | `true` | Echoes the code so the flow is testable before an SMS provider exists. **Forced off when `NODE_ENV=production`.** |

## Rate limiting

| Variable | Default | Notes |
|---|---|---|
| `RATE_LIMIT_WINDOW_MS` | `900000` (15 min) | |
| `RATE_LIMIT_MAX` | `20` | Default cap for the auth routes |

The limiter's counters are in-memory and therefore per-process. Before running
more than one instance, replace the store in `src/middleware/rateLimit.js` with
a shared one (Redis).

## App build flags

| Flag | Default | Notes |
|---|---|---|
| `--dart-define=API_BASE_URL=…` | `http://localhost:4000/api/v1` | On Android emulators use `http://10.0.2.2:4000/api/v1`; on a physical device use your machine's LAN IP. |

## Device permissions

| Platform | Declaration | Why |
|---|---|---|
| Android | `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION` in `android/app/src/main/AndroidManifest.xml` | Phase 2 setup reads the location once to suggest where the business is |
| iOS | `NSLocationWhenInUseUsageDescription` in `ios/Runner/Info.plist` | iOS denies the prompt without this string, so the location step would silently fall back to nothing |

Neither is required to use the app: the setup flow continues without a location and
the owner can type the address instead. Only the when-in-use string is declared
because the app never asks for background or always-on location. On web, the
browser asks instead and the app degrades the same way.

## Integration boundaries (Phase 14)

The four integration services read only a **provider name** from the
environment; no credential is read or stored until a provider is actually
implemented. Setting one of these flips the matching service to
`configured: true` (see `docs/future-integrations.md`).

| Variable | Default | Notes |
|---|---|---|
| `WHATSAPP_PROVIDER` | unset | e.g. `meta` |
| `PAYMENT_PROVIDER` | unset | e.g. `paystack` |
| `LOGISTICS_PROVIDER` | unset | e.g. `gokada` |
| `NOTIFICATION_PROVIDER` | unset | e.g. `fcm` |

Unset is the normal state: every reserved method throws `501 not_implemented`
regardless, and no external call is made. Credentials for these providers are
read where they are used and must **never** be added to `config.js` or logged.

## Development seed data (Phase 17)

`npm run seed` builds the ABC Fashion Store scenario plus a working logistics
network: the partner organization `SwiftMove Logistics` with coverage, pricing and
fleet, one rider, and a delivery request for each delivery-required transaction.
It refuses to run when `NODE_ENV=production` unless overridden, and re-running
rebuilds the same rows rather than doubling them.

| Variable | Default | Notes |
|---|---|---|
| `SEED_PASSWORD` | `Str0ngPass!23` | Password for the seeded accounts below |
| `SEED_FORCE` | unset | Set to `true` to allow seeding a production database (avoid) |

Seeded accounts (same password for all three):

| Role | Email | What it can see |
|---|---|---|
| `business` | `owner@abcfashion.test` | ABC Fashion Store, catalog, transactions, dashboard, logistics requests |
| `logistics_partner` | `partner@swiftmove.test` | SwiftMove Logistics workspace: fleet, riders, coverage, pricing, requests |
| `rider` | `rider@swiftmove.test` | Rider workspace: availability, delivery modes, active delivery, history |

