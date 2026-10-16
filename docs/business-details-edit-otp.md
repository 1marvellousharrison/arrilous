# Business details: an owner-confirmed edit gate

Status: agreed, in progress.

## The problem

The Profile tab is the shop's own front desk. Today the owner reaches the
business-details editor from a storefront icon in the app bar, and the editor
opens straight away. Changing the shop's name, contact and location is the same
kind of act as changing the password: it is the identity a customer and a rider
trust, and it should not be something anyone can do at will from an unlocked
phone.

We also want the wallet to sit at a more exposed point than a row halfway down
the profile list.

## What we decided

### App bar (owner only)

* Every non-Profile tab: `[ wallet ] [ settings ]`. The wallet icon takes the
  slot the storefront icon used to hold; the storefront leaves these tabs.
* The Profile tab: `[ storefront ]`. The storefront moves here, taking the slot
  the settings gear used to hold. Settings is already a row in the profile
  list, so the gear is dropped there.
* Icons do not change shape. Staff keep their current bar for now (a separate
  staff conversation is still open).

### Editing business details needs an owner confirmation, by OTP

* The gate applies **only when editing a profile that already exists**. The
  very first setup (`POST /business`, and the first location write) stays
  gate-free, so a brand-new owner is never blocked from finishing setup.
* After the owner passes the gate, the whole editing session (the profile write
  and the location write) is authorised by one short-lived token, so the owner
  proves who they are once, not once per field.

### Delivery channel: email

Cheapest first, and already the identifier every owner has.

| Channel | Cost in Nigeria (2026) | Setup | Verdict |
| --- | --- | --- | --- |
| Email | ~free to a fraction of a kobo (provider free tiers, then pennies per 1k) | An API key | **Primary** |
| WhatsApp (Meta Authentication) | ~US$0.006 per message | Meta business verification + WABA + template approval + a BSP | Later fallback |
| SMS | ~US$0.03–0.05 per message — the most expensive in Nigeria | A gateway account | Last resort |

Email wins on cost by a wide margin and needs the least infrastructure. The
plumbing is kept channel-agnostic so WhatsApp can be added as a fallback later
without touching the routes.

## The shape

### Server

New table `business_edit_otps` (a dedicated table rather than reusing
`otp_challenges`, so the auth OTP flow is untouched):

```
id, business_id, user_id, code_hash, attempts, max_attempts,
expires_at, consumed_at, created_at
```

Endpoints (owner only, business already exists):

* `POST /api/v1/business/edit-otp` — creates a challenge, emails the 6-digit
  code to the owner's account email, answers with `challenge_id`, masked
  `destination`, `expires_at` and (non-prod only) `dev_code`. Respects the same
  resend cooldown as the auth OTP.
* `POST /api/v1/business/edit-otp/verify` — checks the code and answers with a
  short-lived `edit_token` (HS256 JWT, `aud = dee-business-edit`, default
  15 minutes) plus `expires_at`.

Writes are gated:

* `PATCH /api/v1/business` — always requires a valid `x-business-edit-token`
  (a business only exists here after setup, so this is always an edit).
* `PUT /api/v1/business/location` — requires the header **only when a location
  already exists**; the first write during setup is exempt.

The token is verified server-side (signature, audience, expiry, and that the
subject owns the business). A missing or stale token answers `403` with a code
the app uses to re-run the gate.

### App

* `BusinessSetupFlow` gains an optional `editToken`, forwarded on the profile
  and location writes (`x-business-edit-token`).
* `BusinessRepository` gains `requestEditOtp()` / `verifyEditOtp()` and threads
  the token through `updateProfile` / `saveLocation`.
* A new `BusinessEditGate` screen requests the code, shows the masked
  destination, takes the 6 digits, and returns the token to the caller.
* The shell's "open business details" (used by the storefront icon, the
  missing-details prompt, and the pre-sale gate) runs the gate first whenever
  the owner already has a profile, then opens the editor with the token.

## Not in this change

* Real email delivery needs a provider key (`RESEND_API_KEY`, `OTP_EMAIL_FROM`).
  Without one, non-prod still echoes `dev_code`; prod fails loudly rather than
  pretending the code was sent.
* WhatsApp/SMS fallback.
* The open staff-bar question.
