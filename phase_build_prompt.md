# Master Build Prompt — Business Management App

Use the attached `business_management_app_ui_spec.md` as the product, UI, and feature specification.

## CRITICAL: Existing Authentication

The login/signup backend is ALREADY ACTIVE and WORKING.

- Do not rebuild it.
- Do not replace it.
- Do not reset it.
- Do not change its authentication provider unless absolutely necessary.
- Inspect the existing project first and reuse its authenticated user/session ID.

Everything below must be built ON TOP of the existing authentication.

---

# Global Rules

1. Build in phases and complete one phase before moving to the next.
2. Do not break existing login/signup.
3. Reuse the current frontend/backend/database stack and conventions.
4. Keep the app mobile-first and follow the attached MD/UI references.
5. Add server-side validation and proper error/loading/empty states.
6. Enforce business-level data isolation.
7. Use migrations for database changes.
8. Add tests for important business rules.
9. Document APIs, schema, setup, and future integration points.
10. Never hard-code secrets.

## DO NOT IMPLEMENT YET

Do NOT implement:

- WhatsApp AI
- WhatsApp API
- Automatic WhatsApp replies
- Payment gateways
- Bank/payment webhooks
- Automatic payment matching
- Logistics company APIs
- Rider tracking APIs
- Live delivery tracking

Create a clean architecture so these can be added later without redesigning the core transaction system.

---

# PHASE 0 — Inspect Existing Project

Before changing anything:

- Inspect project structure.
- Identify frontend framework.
- Identify backend framework.
- Identify database.
- Identify authentication provider.
- Identify user/session model.
- Identify existing business/user tables.
- Identify API/routes.
- Identify migration system.
- Identify environment variables.

Do not create duplicate auth or user systems.

Give a short summary of the existing architecture before coding.

---

# PHASE 1 — Business Profile

Create a business profile linked to the existing authenticated user.

Fields:

- id
- owner_user_id
- business_name
- business_category
- business_description
- phone
- email
- created_at
- updated_at

Create protected APIs/services to:

- Create business
- Get business
- Update business

A user must only access their own business.

After login, if no business profile exists, send the user through business setup.

---

# PHASE 2 — Business Location

Create business location storage.

Allow:

- Use current location
- Enter address manually
- Review location
- Confirm location

Store:

- business_id
- address
- city
- state
- country
- latitude
- longitude
- created_at
- updated_at

If location permission is denied, allow manual entry.

Design this so location can later be used for logistics matching, but DO NOT build logistics yet.

---

# PHASE 3 — Product Catalog

Create products belonging to a business.

Fields:

- id
- business_id
- name
- description
- category
- price
- sku
- stock_quantity
- image reference
- active
- created_at
- updated_at

Support:

- Add
- Edit
- View
- Archive/deactivate
- Search/filter

Important: historical transactions must keep the original product name and price even if the catalog changes later.

---

# PHASE 4 — Customers

Create customer records.

Fields:

- id
- business_id
- name
- phone
- email
- address
- notes
- created_at
- updated_at

Customers do NOT need app accounts.

Support customer list, profile, edit, and transaction history.

---

# PHASE 5 — Core Transactions

Create a unified transaction system.

Transactions can eventually come from:

- manual
- whatsapp

For now implement ONLY `manual`, but create the field for future `whatsapp`.

Transaction fields:

- id
- business_id
- customer_id
- transaction_number
- source
- subtotal
- discount
- delivery_fee
- total
- notes
- created_at
- updated_at

A transaction can exist BEFORE payment.

---

# PHASE 6 — Transaction Items

Every transaction must contain itemized products.

Create `transaction_items`:

- id
- transaction_id
- product_id (nullable where appropriate)
- product_name_snapshot
- quantity
- unit_price
- subtotal
- created_at

Example:

2 × Black Shirt × ₦15,000 = ₦30,000

Calculate:

`Subtotal + Delivery Fee - Discount = Total`

Financial totals must be calculated server-side.

Do not trust totals sent by the mobile client.

---

# PHASE 7 — Separate Statuses

Do NOT use one giant status field.

## Order Status

- pending
- confirmed
- cancelled

## Payment Status

- unpaid
- payment_pending
- paid
- failed
- refunded

## Delivery Status

- not_required
- pending
- accepted
- picked_up
- in_transit
- delivered
- failed

## Completion Status

- open
- completed

Example:

Order: confirmed
Payment: paid
Delivery: pending
Completion: open

Payment MUST NOT automatically complete the transaction.

For now payment status can be changed manually by an authorized business user. No payment provider integration yet.

---

# PHASE 8 — Transaction Status History

Create an immutable history table:

- id
- transaction_id
- business_id
- changed_by_user_id
- status_type
- old_value
- new_value
- note
- created_at

Every important status change creates a history record.

Example:

10:01 — Order created
10:05 — Order confirmed
10:30 — Payment marked paid
11:10 — Delivery requested
12:05 — Delivered
12:06 — Completed

Never silently overwrite this history.

---

# PHASE 9 — Manual Transaction UI

Build `+ New Transaction`.

Fields:

### Customer
- Select existing customer
- Or create new customer

### Products
- Search/select product
- Quantity
- Unit price
- Subtotal
- Add another product

### Charges
- Subtotal
- Discount
- Delivery fee
- Total

### Delivery
- Required: Yes/No
- Address if required

### Notes

On creation:

- Order = pending
- Payment = unpaid
- Delivery = not_required OR pending
- Completion = open

---

# PHASE 10 — Transaction Details

Show:

- Transaction number
- Customer
- Products
- Quantities
- Unit prices
- Subtotals
- Total
- Source
- Order status
- Payment status
- Delivery status
- Completion status
- Created date
- Updated date

Include a chronological transaction timeline from `transaction_status_history`.

Only show actions that are valid for the current state.

---

# PHASE 11 — Transaction List / History

Create the Transactions screen.

Support:

- Search
- Date filters
- Status filters
- Source filters

Status filters:

- Pending
- Unpaid
- Paid
- Awaiting Delivery
- In Transit
- Delivered
- Completed
- Failed
- Cancelled

For now only manual transactions are active.

---

# PHASE 12 — Dashboard

Connect the Home dashboard to real database data.

Show:

- Total sales
- Number of transactions
- Pending payment
- Awaiting delivery
- In transit
- Completed
- Failed
- Recent transactions
- Quick actions
- Business information
- Location

Do not use static fake numbers after backend integration.

---

# PHASE 13 — Security

A business user may only access:

- Their business
- Their products
- Their customers
- Their transactions
- Their transaction items
- Their transaction history

Changing an ID in a request must never expose another business's data.

Validate ownership on the server. Use row-level security where supported.

---

# PHASE 14 — Future Integration Architecture

Create clean service/interfaces for future:

- `WhatsAppService`
- `PaymentService`
- `LogisticsService`
- `NotificationService`

These are architecture extension points only.

Do not make external API calls yet.

Future flows will eventually be:

### WhatsApp
Customer → WhatsApp → AI → Transaction draft → Business confirmation

### Payments
Transaction → Payment reference → Provider → Webhook → PaymentService → Paid

### Logistics
Transaction → Delivery request → Location matching → Logistics partner → Rider → Delivery confirmation

---

# PHASE 15 — Business Rules and Validation

Validate:

- Required fields
- Product ownership
- Customer ownership
- Quantity > 0
- Price >= 0
- Valid totals
- Valid status transitions
- Delivery requirements

Reject invalid transitions.

Do not allow a completed transaction to silently revert to an earlier state.

---

# PHASE 16 — Testing

Test at minimum:

- Existing authentication still works.
- Authenticated user can create/access only their business.
- Business A cannot access Business B.
- Products belong to the correct business.
- Historical transaction prices do not change when catalog prices change.
- Multi-item transaction totals are correct.
- Status changes work.
- Every important status change creates history.
- Invalid state transitions are rejected.

---

# PHASE 17 — Development Seed Data

Add development/test data only:

Business:
ABC Fashion Store

Products:
- Black Shirt — ₦15,000
- Blue Jeans — ₦25,000
- Cap — ₦5,000

Customers:
- John Doe
- Jane Doe

Transactions:
- Pending/unpaid
- Paid/awaiting delivery
- In transit
- Completed
- Failed

---

# PHASE 18 — Documentation

Document:

- Architecture
- Database schema
- Migrations
- Environment variables
- API endpoints
- Authentication integration
- Business rules
- Status definitions
- Test commands
- Future integration points

---

# REQUIRED DEVELOPMENT ORDER

Phase 0
→ Phase 1
→ Phase 2
→ Phase 3
→ Phase 4
→ Phase 5
→ Phase 6
→ Phase 7
→ Phase 8
→ Phase 9
→ Phase 10
→ Phase 11
→ Phase 12
→ Phase 13
→ Phase 14
→ Phase 15
→ Phase 16
→ Phase 17
→ Phase 18

For EACH phase:

1. Inspect existing code.
2. Implement only that phase.
3. Run migrations.
4. Run tests.
5. Verify existing features still work.
6. Fix errors.
7. Summarize what changed.
8. Stop and wait before starting the next phase.

## FINAL PHASE-1 GOAL

The working app should support:

Login
→ Business Setup
→ Location Confirmation
→ Dashboard
→ Product Setup
→ Customer
→ Manual Transaction
→ Itemized Products
→ Payment Status
→ Delivery Status
→ Completion Status
→ Full Transaction History

Again:

**DO NOT IMPLEMENT WHATSAPP AI, PAYMENT PROVIDER INTEGRATIONS, OR LOGISTICS INTEGRATIONS YET.**

Prepare the architecture for them, but implement those integrations only in later phases.
