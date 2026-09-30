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
