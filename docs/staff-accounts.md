# Staff Accounts (design only)

> **Status: design — not implemented.** This document records the agreed shape of
> staff logins so a later phase can build it without re-deciding. Nothing here
> exists in the codebase yet.

## Scope

How **staff** attach to an existing **Main** business account and log in.

- In scope: one business (the "Main") and the staff who work for it.
- Out of scope: **branches** (a separate, later discussion). This document assumes
  a single Main account with staff under it.

## Terminology

| Term | Meaning |
|---|---|
| **Main** | The existing business account (the owner). Owns the data and the staff. |
| **Staff** | A person who works for a Main. Has their own login **and** no account of their own. |
| **Staff code** | The staff member's permanent login ID, created by the Main. Globally unique. |
| **Activation** | The one-time step where a staff claims their code and sets a password. |

## Core model

- Staff are **not** owners and do not create anything. They are pulled into a Main.
- A staff login is a `users` row with `role = 'staff'`, linked to a business through
  a `staff_members` row.
- The Main resolves its staff from the link table (not from `owner_user_id`, which
  only identifies the owner).
- The Main **never sets or sees** a staff password. It only issues the code; the
  staff sets their own password during activation.

## The staff code (the permanent login ID)

The code is a **forever login** — the staff keeps using it to sign in. It is:

- **Globally unique** (not per-business), because it alone identifies the account
  at login.
- **Claimable once.** "Not being used" at activation means *not already claimed*.
  After it is activated the code stays valid for login, but cannot be claimed
  again by someone else.

### Generation — original proposal

`first 3 letters of the business name` + `3 digits` → e.g. `ABC123`.

### Refinements agreed

| Issue | Decision |
|---|---|
| Same 3-letter prefix for different shops ("ABC Fashion" vs "ABC Electronics") | Uniqueness must be **global**, since the code is the login ID |
| Renaming the business would change every code | Snapshot a **stable `business_code`** once at business creation; derive staff codes from it, never from the live name |
| `ABC` + `000–999` is only 1,000 guesses per business | Use **random** digits (not sequential), regenerate on clash; keep the security rules below |
| Names with < 3 letters, digits, symbols, spaces ("7up Mart", "AB Store", "D'Best") | Normalise: uppercase, strip non-letters; define a rule for short names (pad or reject) |

**Recommended shape:** a stable `business_code` (e.g. `ABC47`) created once, then
each staff = `business_code` + sequence (`ABC47-03`). Readable *and* globally
unique, and the code alone reveals the business.

**Recorded exactly as proposed:** `ABC` + `123` = `ABC123`.

## Onboarding / activation flow

```
MAIN (owner)                                    STAFF
────────────                                    ─────
Settings → Staff → Add
  enter name (+ phone)
  → server generates a globally
    unique staff code
  → staff_members row created,
    status = 'invited'
  hand the code to the staff  ───────────────►  Sign-in page
                                                  tap "I have my code"
                                                        │
                                                        ▼
                                                CODE PAGE
                                                  enter code
                                                  server checks:
                                                    • code exists
                                                    • code is unclaimed
                                                  → resolves business + staff
                                                        │
                                                        ▼
                                                DETAILS PAGE
                                                  confirm name
                                                  set password
                                                  (code NOT re-entered)
                                                        │
                                                        ▼
                                                server: status='active',
                                                password set, code marked claimed
                                                        │
                                                        ▼
                                                RETURN TO SIGN-IN PAGE
                                                  (no auto-login)
                                                        │
                                                        ▼
                                                SIGN IN: code + password
                                                        │
                                                        ▼
                                                DASHBOARD
                                                  the Main's existing data,
                                                  scoped to the staff's role
```

### Notes locked in during discussion

- **No code re-entry.** After the code is verified, it is carried in state; the
  details page asks only for name + password.
- **No auto-login.** Activation ends by returning to the sign-in page; the staff
  then logs in with code + password (proves they know their credentials).
- **"Not being used" = unclaimed**, not single-use. The code remains the login
  after activation.
- **The dashboard is not "created."** The staff is linked to the Main and sees the
  Main's existing products (view-only), can add customers, and sees **only the
  sales they personally recorded**. Nothing empty is provisioned.

## Sign-in

- Staff sign in with **staff code + password**.
- Implication: the existing sign-in field (which today accepts only **email or
  phone**, see `identifierSchema` in `server/src/lib/validators.js`) must gain a
  **third accepted form: the staff code**.
- Owner accounts continue to use email/phone + password, unchanged.

## Staff role and feature set

Staff are a **restricted, subordinate** role, not a second owner. Their app is a
subset of the owner's.

| Area | Owner | Staff |
|---|---|---|
| Home dashboard | full business | **own sales + amounts only** |
| Sales | all sales | **own sales only**; open detail; **add notes only** |
| Products | add / edit / archive | **view-only** — cannot add or change |
| Customers | add / edit / delete | **add only** — no edit or delete |
| Logistics / delivery requests | yes | yes (retained — see assumptions) |
| Wallet & payouts | yes | **hidden** |
| Business details (name / location) | yes | **hidden** — no storefront button |
| Staff management | yes | **hidden** |
| Business analytics & settings | yes | **hidden** |
| Personal app settings (theme, change password, sign out) | yes | yes |

Notes:

- The **"Business details"** appbar button (`home_shell_screen.dart`, storefront
  icon) is **not shown** on the staff shell.
- Product screens are read-only for staff — no add / edit / archive actions.
- Only *business* settings are hidden; staff keep *personal* settings (theme,
  change password, sign out).

## Sales, attribution and money

- Every transaction gains **`created_by_user_id`**, so the person who recorded it
  is stored alongside the sale (owner or staff).
- When a **staff records a sale**:
  - the sale is recorded under the business with `created_by_user_id = staff`,
  - it appears on the **staff's** list and dashboard (their own only),
  - the **amount is credited to the owner's wallet**, and
  - it appears on the **owner's** dashboard and sales list, tagged with the staff
    who made it.
- **The real money always belongs to the owner.** A staff has **no wallet**.
- The owner can see each staff's sales **as a list under that staff**, and as a
  full list with the staff recorded on each row.

> Today a sale does **not** touch the wallet — `wallet_transactions.kind` is only
> `funding | payout`. Crediting a sale needs a new wallet transaction kind
> (e.g. `sale`) and a credit to the business's wallet.

### Assumptions (to confirm)

- **Logistics stays available to staff** — it was not chosen as a hidden area.
- The wallet credit happens **automatically** at the moment the sale is recorded.

## Schema sketch (not applied)

```sql
-- users: allow the new role
CHECK (role IN ('business', 'logistics_partner', 'rider', 'staff'))

-- businesses: stable, unique prefix used to build staff codes
ALTER TABLE businesses ADD COLUMN business_code TEXT UNIQUE;

-- the link between a staff login and the business it serves
CREATE TABLE staff_members (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  business_id  TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  staff_code   TEXT NOT NULL UNIQUE,          -- the permanent login ID
  status       TEXT NOT NULL DEFAULT 'invited',  -- invited | active | disabled
  permissions  TEXT,                          -- role/limits, TBD
  created_by   TEXT REFERENCES users(id),     -- the owner who added them
  activated_at TEXT,
  created_at   TEXT NOT NULL DEFAULT now_iso(),
  updated_at   TEXT NOT NULL DEFAULT now_iso(),
  CHECK (status IN ('invited', 'active', 'disabled'))
);

-- transactions: record who created the sale (owner or staff)
ALTER TABLE transactions ADD COLUMN created_by_user_id TEXT REFERENCES users(id);

-- wallet_transactions: allow a sale credit (currently only funding | payout)
CHECK (kind IN ('funding', 'payout', 'sale'))
```

> Note: `users.email` is `NOT NULL` today. A code-only staff account needs email
> either relaxed to nullable or auto-synthesised (e.g. `staff+<id>@business.invalid`).

## API sketch (not built)

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/v1/staff` | Owner adds staff → creates invite + code |
| `GET` | `/api/v1/staff` | Owner lists staff |
| `PATCH` | `/api/v1/staff/:id` | Owner disables / edits a staff |
| `POST` | `/api/v1/staff/claim` | Staff submits a code → resolves business + staff |
| `POST` | `/api/v1/staff/activate` | Staff confirms name + sets password → activates |
| `GET` | `/api/v1/staff/:id/transactions` | Owner views one staff's sales |
| `POST` | `/api/v1/auth/login` | Extended to accept a **staff code** as the identifier |

Existing transaction routes become **staff-aware**: a staff's list returns only
their own sales, and editing/cancelling is refused for staff (notes only).

## UI entry points

| Screen | Who | Purpose |
|---|---|---|
| Settings → Staff | Owner | Add, list, disable staff; view each code |
| Settings → Staff → *staff* | Owner | That staff's sales list, tagged with each sale |
| Sign-in page → "I have my code" | Staff | Entry to activation |
| Code page | Staff | Enter + verify the code |
| Details page | Staff | Confirm name + set password |
| Sign-in page | Staff | Everyday login with code + password |
| Dashboard (staff shell) | Staff | Own sales + amounts only; **no** business-details button |
| Products (staff) | Staff | View-only — no add / edit / archive |
| Customers (staff) | Staff | Add-only — no edit / delete |
| Sale detail (staff) | Staff | View + add notes; no edit / cancel |

## Security rules

- Rate-limit and time-bound the **claim/activation** endpoint (attackers will try
  to guess short codes).
- Lockout on repeated failed logins for a staff code.
- The owner can **disable** a staff at any time.
- Owner never knows the staff password.
- Codes use **random** digits, not sequential, to reduce predictability.

## Open questions

1. Can one person staff **two businesses**, or is a staff account always exactly
   one Main?
2. Do we need staff **tiers** (e.g. cashier vs manager) beyond the single
   restricted role described above, or is one staff role enough for now?
3. Code length — is `3 letters + 3 digits` enough once random + rate-limited, or
   should it be longer?
4. Short business names (< 3 letters) — pad or reject?
5. Should activation ever offer a phone/email **OTP** as a second factor?
6. Does the owner's wallet credit also write a **wallet transaction (ledger) row**
   per sale, or just adjust the balance?
7. Same "hidden areas" — should staff keep **logistics** access? (currently assumed
   yes).
