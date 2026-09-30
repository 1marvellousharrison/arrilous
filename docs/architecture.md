# Architecture

## Phase 0 finding

No existing application or authentication backend existed anywhere on the
machine. The only prior artefacts were two unrelated prototypes whose auth was
client-side mock code:

- `Desktop/chat/auth.js` — `access_token: 'jwt_mock_' + Date.now()`, no server, no database
- `Desktop/social/src/services/auth.ts` — reads from `data/mockData`
- `Desktop/POT/ecommerce-platform` — empty directory

Per instruction, the signup/login backend was therefore built first, and every
later phase reuses its real user/session IDs. There is no parallel or duplicate
auth system.

## Chosen stack

| Layer | Choice | Why |
|---|---|---|
| API | Node 26 + Express 5 | Already installed; native ESM; first-class async error propagation in Express 5 |
| Database | SQLite via built-in `node:sqlite` | No native build step, no external service; `node:sqlite` is stable on Node 26 |
| Migrations | Versioned `.sql` files applied in filename order | Portable, reviewable, no extra dependency |
| Validation | Zod | Single source of truth for request shape *and* generated field-level error messages |
| Passwords | `node:crypto` scrypt (N=16384, r=8, p=1, 64-byte key) | No native dependency; cost parameters stored with the hash so they can be raised later |
| Tokens | HS256 JWT access tokens + opaque refresh tokens | Access tokens are stateless and verifiable in-process; refresh tokens are single-use and revocable, which a JWT cannot be |
| Tests | `node:test` + `node:test` HTTP assertions | Built in; no test framework to install |
| App | Flutter 3.47 (Android/iOS/Web) | Already installed; `flutter analyze`/`flutter test` give real verification without a device |
| App state | `ChangeNotifier` | Smallest thing that satisfies the session and theme needs |
| Token storage | `flutter_secure_storage`, with a `SharedPreferences` fallback | Tokens are credentials; targets that cannot offer a secure enclave (a web build served over plain HTTP) still keep the session instead of dropping it |

## Request lifecycle

```
client request
   ↓
cors → express.json (100kb cap)
   ↓
rateLimit middleware  (per-IP, per-route, in-memory)
   ↓
route handler
   ├─ zod schema parse  → 422 with per-field details
   ├─ domain logic      → ApiError for every expected failure
   └─ db access via src/db/index.js helpers (run/queryOne/queryAll/transaction)
   ↓
notFoundHandler (404 envelope) → errorHandler (single JSON shape)
```

Express 5 forwards rejected promises from async handlers to the error handler
automatically, so `throw new ApiError(...)` is the only error path a route needs.

## Authentication model

```
POST /auth/signup ─┐
POST /auth/login  ─┼─→ session issued ─→ {
POST /auth/verify-otp ┘     │              access_token  (JWT, 15 min)
                            │              refresh_token (opaque, 30 days)
                            └─→ rows in      users
                                            refresh_tokens (SHA-256 hash only)
```

- **Access token**: HS256 JWT carrying `sub`, `role`, `iss`, `aud`, `iat`, `exp`.
  The algorithm is hard-coded in `lib/jwt.js` and never read from the incoming
  token, so `alg: none` downgrades are rejected. Signature comparison is
  `timingSafeEqual`.
- **Refresh token**: 48 random bytes, base64url. Only its SHA-256 hash is stored,
  so a database dump cannot be replayed as a session.
- **Rotation**: every refresh issues a new token and revokes the old one. If a
  *revoked* token is presented, that is treated as theft and the whole token
  family for that user is revoked.
- **`requireAuth`** re-reads the user row on every protected request, so a
  suspended or deleted account cannot keep using an unexpired token.
- **Account enumeration** is blocked: unknown-account and wrong-password logins
  return the identical message and status, unknown accounts still pay the
  scrypt cost (`fakeVerify`), and `request-password-reset` returns 200 with no
  challenge id for unknown identifiers. The app renders that no-challenge
  response as a neutral "if an account exists…" notice, so the UI cannot be used
  to probe which identifiers are registered.

## Session storage on the device

`AuthRepository` never touches storage directly; it delegates to `SessionStore`
(`app/lib/core/state/auth_repository.dart`), which writes the serialised session
to `flutter_secure_storage` (Android Keystore, iOS Keychain, libsecret, Windows
DPAPI, WebCrypto). If that call is unavailable — most commonly a Flutter web
build served over plain HTTP, which is not a secure context — the store falls
back to `SharedPreferences` for the rest of the process and removes any stale
fallback copy once secure storage succeeds. `AuthRepository` takes an injected
store, so tests exercise the fallback without a platform channel.

## App-side auth screens

| Screen | Purpose |
|---|---|
| `AccountTypeScreen` → `SignUpFlow` | Role picker, then the sign-up form. Email is required for every role, matching the API. |
| `SignUpScreen` | Validation, inline field errors, busy/disabled states. |
| `LoginScreen` | Password sign-in, plus "Forgot password?" and "Sign in with a code instead". |
| `ResetPasswordScreen` | Request a reset code, then set a new password. Pops with `true` so the caller can prompt for a fresh sign-in — the API revokes every session on reset. |
| `VerifyOtpScreen` | Six-box code entry for passwordless sign-in. |

## Roles

`users.role` is one of `business`, `logistics_partner`, `rider` — the three
roles in the spec (sections 3.1–3.3). The column exists now so later phases can
add logistics dashboards and rider flows without a migration that rewrites
existing accounts.

## Data isolation (foundation for Phase 13)

Every table that will hold business data will carry `business_id`, and every
query will be scoped by the `user_id` resolved by `requireAuth`. The auth layer
already establishes the rule that IDs arrive from the token, never from the
request body — `signup` ignores client-supplied `id`/`role`/`status`, and this
is covered by a test.

## Error contract

```json
{ "error": { "code": "validation_failed",
             "message": "Some fields need your attention.",
             "details": [{ "field": "password",
                           "message": "Password must be at least 8 characters." }] } }
```

Codes in use: `validation_failed` (422), `bad_request` (400), `invalid_json`
(400), `unauthorized` (401), `forbidden` (403), `not_found` (404), `conflict`
(409), `too_many_requests` (429), `server_error` (500). The mobile client maps
these to field-level messages via `ApiException.fieldError(field)`.

## Deliberately not built yet

WhatsApp AI, payment providers/webhooks, logistics partner/rider APIs and live
tracking. Extension points are reserved in `docs/future-integrations.md`.
