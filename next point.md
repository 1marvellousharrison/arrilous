# Business Management App — Integrated Build Specification v3

> This document **extends** the earlier `business_management_app_ui_spec.md` and `phase_build_prompt_v2.md`. It does not replace their core architecture. Existing authentication, business, product, customer, transaction, status, history, dashboard, navigation, and security rules remain the foundation unless this document explicitly adds to them.

---

## 1. Product Overview

This is a mobile-first business operations app for small and growing business owners.

Core lifecycle:

**Order → Payment → Delivery → Delivery Confirmation → Completed**

Main systems:

- Business management
- Product catalog
- Customer records
- Unified transactions
- Payment tracking
- Logistics network
- Delivery confirmation
- Transaction history and reports
- Future WhatsApp AI and image/screenshot order import

Customers do **not** need an app account in the current version.

---

## 2. Compatibility With the Earlier Build

Keep the earlier architecture intact:

- Authentication foundation
- Business profile
- Business location
- Product catalog
- Customer records
- Unified transaction system
- Transaction items
- Separate order/payment/delivery/completion statuses
- Immutable transaction status history
- Dashboard
- Transaction history
- Security/data isolation
- Main mobile navigation
- Future `WhatsAppService`, `PaymentService`, `LogisticsService`, and `NotificationService` extension points

Do **not** create duplicate authentication, transaction, or status systems.

---

## 3. Authentication

Follow `phase_build_prompt_v2.md`.

If authentication already exists:

- Reuse it.
- Do not replace it.
- Do not create a second auth system.

If authentication does not exist:

- Build signup
- Build login
- Build logout
- Build secure session/token handling
- Build protected routes
- Test authenticated-user identification
- Then continue to business features

All business, logistics organization, and rider data must be linked to authenticated users.

---

## 4. User Roles

### 4.1 Business Owner

Can:

- Manage business profile
- Manage products
- Manage customers
- Create transactions
- Review/confirm future AI or image-generated order drafts
- Track payment status
- Request delivery
- See suitable active logistics organizations
- See suitable active riders where direct rider selection is allowed
- Compare provider rates
- See provider service areas
- See provider vehicle/mode information
- Personally deliver orders
- Confirm personal delivery
- View history and reports

### 4.2 Logistics Organization

Can:

- Manage organization profile
- Set active/inactive status
- Set automatic closing time
- Extend availability where permitted
- Manage service areas
- Publish destination pricing
- Manage fleet/vehicles
- Track vehicle availability
- Receive delivery requests
- Quote for specific deliveries
- Accept/reject requests
- Manage riders
- See active riders inside the organization
- Assign riders
- Manage deliveries
- Confirm delivery
- View completed/failed deliveries

### 4.3 Rider / Delivery Staff

Can:

- Manage profile
- Set active/inactive status
- Set automatic closing time
- Extend by 30 minutes
- Extend by 1 hour
- Set a custom extension
- Manage service areas
- Manage delivery modes
- Publish applicable pricing
- Receive delivery requests
- Accept/reject requests
- View assigned deliveries
- Update delivery status
- Provide delivery proof
- Confirm customer OTP
- Report issues

---

## 5. Main Navigation

Preserve the earlier main navigation:

- Home
- Transactions
- AI / Chats
- Logistics
- Profile

The AI-related options are visible but **inactive** until their later implementation phases.

---

## 6. Create Transaction — Three Entry Options

When the business owner taps `+ New Transaction`, show:

### Manual Entry
**Available**

Allows:

- Customer selection/creation
- Product selection
- Quantity
- Unit price
- Discount
- Delivery fee
- Delivery requirement
- Delivery address
- Notes

### WhatsApp AI
**Coming Soon / Inactive**

Visible in the options, but no live AI processing yet.

### Screenshot / Photo
**Coming Soon / Inactive**

Visible in the options, but no image analysis yet.

All three methods will eventually feed the **same transaction engine**.

---

## 7. Critical Order Confirmation Rule

This is a core product rule.

**AI must never directly finalize an order.**

Any order coming from:

- WhatsApp AI
- Screenshot/image analysis
- Future import integrations

must first become a **Draft / Pending Review**.

Flow:

**Input → AI extraction → Draft Order → Business Review → Business Confirmation → Active Transaction**

The review screen should display:

- Customer name
- Phone number
- Products
- Quantities
- Product variations/sizes
- Unit prices
- Subtotals
- Delivery requirement
- Delivery address
- Discount
- Delivery fee
- Total
- Missing/uncertain information

Highlight uncertainty, for example:

> ⚠️ Price not found

> ⚠️ Delivery address incomplete

Actions:

- Edit
- Confirm Order

Only after confirmation does the order enter the normal transaction lifecycle.

---

## 8. Future Screenshot / Image Order Import

Present in the UI but inactive initially.

Future inputs may include:

- WhatsApp screenshots
- SMS screenshots
- Instagram messages
- Facebook messages
- Typed order notes
- Handwritten order notes
- Invoices
- Order forms

Future flow:

**Image → AI/OCR understanding → Structured extraction → Product/customer matching → Draft Order → Business Confirmation**

Possible extracted data:

- Customer name
- Customer phone
- Products
- Quantity
- Size/variation
- Price
- Delivery requirement
- Delivery address
- Notes

Never save an unconfirmed AI order as a finalized order.

---

## 9. Transaction Source

Preserve the existing `source` field.

Current active source:

- `manual`

Future sources:

- `whatsapp`
- `screenshot`
- `image`
- `imported_document`

No AI processing is implemented yet.

---

## 10. Existing Transaction Structure — Preserve

Core transaction fields:

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

Transaction items:

- id
- transaction_id
- product_id
- product_name_snapshot
- quantity
- unit_price
- subtotal
- created_at

Financial totals must be calculated server-side.

Historical item names and prices must not change when the product catalog changes later.

---

## 11. Existing Status Model — Preserve

### Order Status

- pending
- confirmed
- cancelled

### Payment Status

- unpaid
- payment_pending
- paid
- failed
- refunded

### Delivery Status

- not_required
- pending
- accepted
- picked_up
- in_transit
- delivered
- failed

### Completion Status

- open
- completed

Payment must **not** automatically complete a transaction.

Example:

> Order: confirmed  
> Payment: paid  
> Delivery: pending  
> Completion: open

---

## 12. Existing Transaction History — Preserve

Keep immutable `transaction_status_history`.

Fields:

- id
- transaction_id
- business_id
- changed_by_user_id
- status_type
- old_value
- new_value
- note
- created_at

Every meaningful status change creates a new history record.

---

# 13. Logistics System Overview

The logistics system is a **multi-provider network**.

Multiple logistics organizations can operate in the same area.

Example:

Warri:
- Logistics Company A
- Logistics Company B
- Logistics Company C

Port Harcourt:
- Logistics Company D
- Logistics Company E

Do not hard-code one provider per location.

---

# 14. Business Owner — Logistics Dashboard

Show:

- Delivery requests
- Active deliveries
- Completed deliveries
- Failed deliveries
- Active nearby logistics organizations
- Active nearby riders where applicable

### Active Logistics Provider Card

Show:

- Organization name
- Active/inactive status
- Approximate distance from business
- Service areas
- Published rates
- Available vehicle types
- Relevant capacity
- Availability
- Estimated delivery time where available

### Active Rider Card

Show, where direct rider selection is supported:

- Rider name
- Active status
- Approximate distance
- Service area
- Delivery mode
- Published rate or quote
- Relevant capacity
- Current availability

The business owner's location must strongly influence which providers/riders are shown.

---

# 15. Location-Based Provider Matching

Use, at minimum:

1. Business pickup location
2. Customer delivery destination
3. Active/inactive status
4. Service-area coverage
5. Vehicle/delivery-mode suitability
6. Published price or available quote
7. Current capacity/availability
8. Distance

Future ranking can also consider workload, estimated pickup time, estimated delivery time, reliability, and business preferences.

First remove providers/riders who cannot serve the route.

---

# 16. Logistics Organization Availability

A logistics organization needs a prominent availability control.

Example:

**● ACTIVE**

The organization can set:

**Automatic closing time**

Example:

> Active until 8:00 PM

At the closing time:

**Active → Inactive**

This affects only **availability for new delivery requests**.

It must NOT:

- Cancel existing deliveries
- Remove existing assignments
- Stop active riders already handling deliveries
- Change completed records
- Stop an in-transit delivery

Existing work continues normally.

---

# 17. Rider Availability

Riders have the same availability concept.

Example:

**● ACTIVE**

> Active until 7:00 PM

Quick extensions:

- +30 minutes
- +1 hour
- Custom duration

Example:

7:00 PM → +1 hour → 8:00 PM

When the final availability time is reached:

**Active → Inactive**

Again, this only affects new availability matching. Existing assigned deliveries continue.

---

# 18. Availability Data Model

Availability must be separate from active-delivery state.

A rider can validly be:

> Availability: Inactive  
> Current Delivery: In Transit

A logistics company can validly be:

> Availability: Inactive  
> Existing Delivery: Active

Do not use one boolean to represent both concepts.

Suggested fields:

- is_available
- availability_started_at
- availability_expires_at
- current_delivery_count

---

# 19. Logistics Service Areas

Both organizations and riders can define where they operate.

`+ Add Location`

Each location may contain:

- City
- Area
- State
- Country
- Coordinates where useful
- Radius/route information where useful

Example:

- Warri → Effurun
- Warri → Ughelli
- Warri → Sapele
- Warri → Benin City

Service areas are used in matching.

---

# 20. Area-Based Pricing

Logistics organizations and riders can publish destination pricing.

Example:

| Destination | Published Price |
|---|---:|
| Effurun | ₦2,500 |
| Ughelli | ₦4,000 |
| Sapele | ₦5,000 |
| Abraka | ₦5,500 |
| Benin City | ₦8,000 |

Providers can add future destinations and pricing in advance.

This information should be visible on their profiles to business users.

---

# 21. Order-Specific Delivery Quotes

Published area pricing is not always the final price.

When a provider receives:

- Pickup location
- Destination
- Package size
- Quantity
- Estimated weight where available
- Special handling requirements

it can submit a specific quote.

Example:

> Delivery quote: ₦3,000

The business owner can:

- Accept
- Decline
- Choose another provider

Store both the published price and the actual order quote where applicable.

---

# 22. Logistics Organization Fleet / Vehicles

Fleet management is a **required core feature** for logistics organizations.

Each organization needs a:

**Vehicles / Fleet** section.

Manage:

- Vehicle type
- Total quantity
- Available quantity
- Capacity category
- Rate/price
- Active/inactive status
- Optional description

Supported examples:

- Motorcycle
- Tricycle
- Car
- Van
- Pickup
- Truck
- Other

Example:

| Vehicle | Total | Available | Capacity | Starting Price |
|---|---:|---:|---|---:|
| Motorcycle | 8 | 5 | Small | ₦2,500 |
| Tricycle | 3 | 2 | Medium | ₦4,000 |
| Car | 2 | 1 | Large | ₦6,000 |
| Van | 1 | 1 | Very Large | ₦10,000 |

Vehicle availability must change as vehicles are assigned and released.

---

# 23. Fleet Visibility to Business Users

When a business owner opens a logistics company profile, show relevant available vehicles.

Example:

**FastMove Logistics**

🟢 Active

**Available Vehicles**

- Motorcycle — from ₦2,500
- Tricycle — from ₦4,000
- Car — from ₦6,000
- Van — from ₦10,000

The profile should also expose relevant service-area pricing.

---

# 24. Rider Delivery Modes

Use **Delivery Modes** for individual riders, not Fleet.

A rider may have:

- Motorcycle
- Car
- Bicycle
- Other supported mode

For each mode, where appropriate, store:

- Primary/secondary
- Capacity
- Rate
- Active/inactive

If the rider has multiple modes, do not show all of them indiscriminately.

---

# 25. Rider Mode Matching

Mode suitability should not depend only on item count.

Consider:

- Quantity
- Package dimensions
- Estimated weight
- Vehicle/mode capacity
- Distance
- Destination
- Rider availability
- Current workload

Example:

Small order:

> Motorcycle — Suitable

Large-volume order:

> Motorcycle — Not suitable  
> Car — Suitable

Only appropriate modes should be surfaced as available options.

---

# 26. Logistics Organization — Rider Management

The logistics organization needs an internal rider view.

Example:

| Rider | Status | Location | Active Jobs |
|---|---|---|---:|
| Michael | Active | Warri | 1 |
| David | Active | Effurun | 0 |
| James | Inactive | Warri | 0 |

Organization capabilities:

- View riders
- See active riders
- See rider status
- See rider current jobs
- See rider availability time
- See delivery mode
- Assign riders
- Manage rider accounts where permitted

Do not expose all internal operational information to business users.

---

# 27. Delivery Request Notifications

Delivery requests must be highly visible.

Example:

### NEW DELIVERY REQUEST

Business:
**ABC Fashion Store**

Pickup:
Warri

Destination:
Effurun

Package:
3 items

Order value:
₦65,000

Actions:

**View Request**

**Accept**

**Decline**

Use:

- Push notifications
- In-app badges
- New Requests counter
- Notification history

Do not depend only on a small notification icon.

---

# 28. Delivery Request Information

A request should contain enough information to make a decision.

Minimum:

- Order reference
- Business name
- Pickup location
- Customer destination
- Item count
- Package size/weight where available
- Special handling notes
- Preferred mode where applicable
- Current delivery fee or quote request
- Required timing

Expose only the customer information required by the recipient's role.

---

# 29. Logistics Delivery Lifecycle

Preserve the earlier lifecycle:

**Delivery Requested → Accepted → Rider Assigned → Picked Up → In Transit → Delivered / Failed**

Do not replace the existing delivery status model.

---

# 30. Delivery Confirmation

### Logistics delivery

Preferred:

- Customer OTP

Optional supporting proof:

- Photo
- Signature
- Timestamp
- Location information

### Personal business-owner delivery

Supported confirmation methods:

- Customer OTP
- Customer signature
- Delivery photo
- Manual confirmation

After valid confirmation:

**Delivery = Delivered**

Then, when all transaction requirements are satisfied:

**Completion = Completed**

---

# 31. Failed Delivery

Possible reasons:

- Customer unavailable
- Wrong address
- Customer rejected/cancelled
- Rider issue
- Vehicle issue
- Business issue
- Other

Allow notes and retry/reschedule.

Never delete the failed attempt from history.

---

# 32. Logistics Organization Profile

Show business-facing information such as:

- Organization name
- Active/inactive status
- Service areas
- Published delivery prices
- Fleet/vehicle types
- Available vehicles
- Operating hours
- Current availability
- Relevant verification information

---

# 33. Rider Profile

Show business-facing information such as:

- Rider name
- Active/inactive status
- Service areas
- Delivery mode(s)
- Relevant capacity
- Published rates
- Current availability
- Relevant verification information

Keep business-facing information concise.

---

# 34. Business-Facing vs Internal Logistics Information

### Business owner sees

- Suitable active providers
- Suitable riders where applicable
- Relevant rates
- Service coverage
- Relevant vehicle/mode choices
- Current availability
- Delivery quote
- Delivery progress

### Logistics organization sees

- Their riders
- Rider availability
- Rider current jobs
- Assignment information
- Fleet state
- Internal operational information

Role-appropriate visibility is required.

---

# 35. Payment Architecture — Still Inactive

Payment remains a separate transaction stage.

For the current build:

**Payment status may be changed manually for testing.**

Do NOT integrate a live payment provider yet.

Keep the existing `PaymentService` extension point ready for future:

- Bank/virtual-account collection
- Payment webhooks
- Automatic order/payment reconciliation
- Business settlement
- Logistics settlement
- Split settlement

---

# 36. AI Architecture — Present but Inactive

AI UI should be visible, but inactive initially.

### Present now

- AI options in transaction creation
- AI/Chats navigation
- Coming-soon cards/states
- Architecture extension points

### Not active now

- WhatsApp AI processing
- WhatsApp API
- Automatic replies
- Screenshot/image analysis
- Automatic AI order creation
- AI product matching

These are future implementation phases.

---

# 37. Database Additions

Extend the earlier schema without duplicating existing entities.

Potential logistics entities:

- logistics_organizations
- logistics_service_areas
- logistics_pricing
- logistics_vehicles
- logistics_riders
- rider_delivery_modes
- rider_service_areas
- rider_pricing
- availability_windows
- delivery_requests
- delivery_quotes
- delivery_assignments
- delivery_confirmations

Potential future AI/import entities:

- order_drafts
- order_draft_items
- ai_import_sources
- ai_extraction_results

Only create AI-specific tables when a later AI phase requires them.

---

# 38. Delivery Request Data Model

A delivery request should reference the existing transaction rather than duplicate the complete transaction.

Conceptually:

`delivery_request.transaction_id → transaction.id`

Store delivery-specific information:

- pickup location
- destination
- package information
- provider/rider target
- published price where applicable
- quoted price
- accepted price
- request status
- created_at
- updated_at

---

# 39. Availability Rules

When `availability_expires_at` is reached:

`is_available = false`

This affects:

- New provider/rider matching
- New delivery requests
- Active availability lists

It does NOT affect:

- Existing deliveries
- Existing assignments
- In-transit deliveries
- Completed records

---

# 40. Fleet Availability Rules

Example:

Total motorcycles = 8

Assigned motorcycles = 6

Available motorcycles = 2

The business-facing profile should not report 8 as currently available.

When a vehicle becomes free, its availability is restored.

---

# 41. Business Dashboard Additions

Keep the earlier dashboard and add:

### Logistics Summary

- Pending delivery requests
- Active deliveries
- Available nearby logistics providers
- Available nearby riders where applicable
- Delivery failures

### New Transaction Options

- Manual Entry — Available
- WhatsApp AI — Coming Soon
- Screenshot / Photo — Coming Soon

---

# 42. Logistics Organization Dashboard

### Header

- Organization name
- Active/Inactive control
- Availability countdown
- Automatic closing time

### Summary

- New requests
- Active deliveries
- Completed deliveries
- Failed deliveries

### Fleet

- Vehicle totals
- Available vehicles
- Vehicle prices
- Capacity categories

### Riders

- Active riders
- Inactive riders
- Current jobs

### Service Areas & Pricing

- Destinations
- Published fees

### Requests

- New
- Accepted
- Declined
- Assigned
- Completed
- Failed

---

# 43. Rider Dashboard

### Header

- Rider name
- Active/Inactive control
- Closing time

### Availability Extension

- +30 min
- +1 hour
- Custom

### Summary

- New requests
- Assigned
- In transit
- Completed
- Failed

### Delivery Modes

- Primary mode
- Additional modes
- Capacity/rates

### Active Delivery

- Pickup
- Destination
- Package details
- Delivery status

### History

- Completed
- Failed
- Cancelled

---

# 44. Business-Facing Provider Selection

When requesting delivery:

1. Confirm pickup location.
2. Confirm customer delivery destination.
3. Find active suitable providers/riders.
4. Filter by service area.
5. Filter by vehicle/mode suitability.
6. Display rates/quotes.
7. Business chooses a provider/mode or requests a quote.
8. Delivery request is sent.

Example:

**FastMove Logistics**
2.4 km away
🟢 Active

Motorcycle — from ₦2,500
Car — from ₦6,000
Van — from ₦10,000

---

# 45. Pricing Rules

A published rate is not necessarily the final delivery charge.

Final price may depend on:

- Route
- Package details
- Vehicle/mode
- Special handling
- Provider quote

Where applicable store:

- published_price
- quoted_price
- accepted_price

---

# 46. Notifications

### Business owner

- Delivery request accepted
- Request declined
- Rider assigned
- Pickup complete
- In transit
- Delivered
- Failed
- Provider quote received

### Logistics organization

- New delivery request
- Business accepted quote
- Assignment changes
- Delivery updates

### Rider

- New assignment
- Request accepted
- Request cancelled
- Delivery details changed

---

# 47. Security and Role Isolation

Preserve business-level isolation and add role-level permissions.

### Business owner

Access only their business and delivery relationships.

### Logistics organization

Access only its organization, riders, fleet, service areas, pricing, and relevant delivery requests.

### Rider

Access only assigned/relevant delivery information and personal profile/availability.

All authorization checks must happen on the server/backend.

---

# 48. Empty and Coming-Soon States

Examples:

### No transactions
> No transactions yet.

### No active providers
> No suitable active logistics providers are currently available.

### AI inactive
> AI order creation is coming soon.

### No fleet
> Add your first vehicle.

### No riders
> Add a rider to your organization.

### No service areas
> Add the locations you deliver to.

---

# 49. Overall Build Order

The original build phases remain the foundation.

## Core Foundation

1. Inspect project + establish/verify authentication
2. Business profile
3. Business location
4. Product catalog
5. Customers
6. Core transactions
7. Transaction items
8. Separate statuses
9. Transaction status history
10. Manual transaction UI
11. Transaction details
12. Transaction list/history
13. Dashboard
14. Security
15. Future service architecture
16. Validation/business rules
17. Testing
18. Development seed data
19. Documentation

## Logistics Extension

After the transaction foundation is stable:

A. Logistics organization accounts/profile

B. Rider profiles/accounts

C. Availability + automatic closing

D. Service areas + pricing

E. Fleet/vehicle management

F. Rider delivery modes

G. Delivery requests + notifications

H. Provider/rider matching

I. Delivery assignment/status flow

J. Delivery confirmation

K. Business-facing provider selection

L. Logistics security/testing

---

# 50. Future AI Phases — Do Not Implement Yet

A. WhatsApp integration

B. WhatsApp conversation understanding

C. Draft order extraction

D. Business review/confirmation

E. Screenshot/image analysis

F. Product matching

G. Customer matching

The AI must always feed the Draft → Review → Confirm workflow.

---

# 51. Future Payment Phases — Do Not Implement Yet

A. Provider comparison/selection

B. Provider account setup

C. Order-specific payment reference/virtual account

D. Payment webhook/reconciliation

E. Business settlement

F. Logistics settlement/split

G. Payment audit/reconciliation

---

# 52. Critical Product Principles

1. **AI prepares; the business owner confirms.**
2. **Payment does not equal completion.**
3. **Delivery must be separately confirmed.**
4. **Automatic closing affects only new availability.**
5. **Existing deliveries continue after availability expires.**
6. **Business location strongly influences provider/rider matching.**
7. **Service areas and published prices live on provider profiles.**
8. **Logistics organizations manage real fleets.**
9. **Rider modes are matched to order suitability.**
10. **Transaction history is auditable and immutable.**
11. **Role permissions are enforced server-side.**
12. **AI, live payments, and live logistics integrations remain inactive until their dedicated phases.**

---

# 53. Final Unified Flows

## Manual Order

**Business owner → New Transaction → Manual Entry → Review → Confirm → Payment → Delivery → Delivery Confirmation → Completed**

## Future WhatsApp Order

**Customer → WhatsApp → AI → Draft Order → Business Review → Confirm → Payment → Delivery → Delivery Confirmation → Completed**

## Future Screenshot Order

**Business owner → Screenshot/Photo → AI Analysis → Draft Order → Business Review → Confirm → Payment → Delivery → Delivery Confirmation → Completed**

## Logistics Matching

**Business location + customer destination → Active providers → Service-area filtering → Vehicle/mode suitability → Published rates/quotes → Business selection → Delivery request → Assignment → Delivery → Confirmation**

---

# 54. Final Implementation Rule

This file is an **integrated extension** of the earlier build, not a replacement.

Keep the existing transaction, dashboard, customer, product, authentication, history, and navigation architecture intact.

Add the new logistics, availability, fleet, pricing, rider-mode, provider-matching, order-confirmation, and inactive-AI requirements without creating conflicting versions of existing systems.

The final platform remains one coherent system:

**Business Management + Transactions + Payment Tracking + Logistics Network + Delivery Confirmation + Future AI Order Intake**

with the unified lifecycle:

**Draft → Confirmed Order → Payment → Delivery → Confirmed Delivery → Completed**
