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

## Not yet required

No WhatsApp, payment or logistics provider keys are read by the app yet. Those
variables will be introduced in the phases that add the corresponding
integrations (see `future-integrations.md`).
