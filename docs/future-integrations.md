# Future integration points

WhatsApp AI and payment providers are not implemented, and no external calls are
made. The **local** logistics network (partner/rider accounts, matching, the
delivery lifecycle and notifications) *is* implemented in
`server/src/routes/logistics.js` — what remains future work is connecting a
third-party fleet through `LogisticsService`. This file is the reserved shape so
the remaining integrations land without redesigning the transaction core.

## Why these are not built yet

`phase_build_prompt.md` explicitly excludes WhatsApp AI, payment gateways and
webhooks, and live logistics integrations. The transaction model was designed so
they can be added as *writers* of the same four status groups, not as a
replacement of them.

## The four status groups (Phase 7)

Any integration must move these independently. Payment **never** implies
completion — that is the product's central rule (spec section 42).

| Group | Values |
|---|---|
| Order | `pending`, `confirmed`, `cancelled` |
| Payment | `unpaid`, `payment_pending`, `paid`, `failed`, `refunded` |
| Delivery | `not_required`, `pending`, `accepted`, `picked_up`, `in_transit`, `delivered`, `failed` |
| Completion | `open`, `completed` |

Example: `order=confirmed, payment=paid, delivery=pending, completion=open`.

## Service interfaces (Phase 14)

Four boundaries, each owning its own external call and nothing else. Business
logic calls these, so a provider swap never touches routes or UI.

| Service | Responsibility (future) |
|---|---|
| `WhatsAppService` | Receive inbound messages, run AI replies, extract order drafts, hand control back to the owner |
| `PaymentService` | Create a per-transaction reference, verify provider callbacks, mark `payment` status |
| `LogisticsService` | Reserved slot for a **third-party** provider (`LOGISTICS_PROVIDER`): hand a delivery request to an external fleet and stream their tracking events back. Local matching and the delivery lifecycle already run in `routes/logistics.js`. |
| `NotificationService` | Fan out push/email/WhatsApp events (order detected, paid, picked up, delivered, failed, human attention needed) |

None of these may write to `transactions` directly. They go through the same
service layer as the manual path so history and validation stay identical.

### Where they live

```
server/src/services/
├─ extension.js      IntegrationService base + reservedMethod() (throws 501)
├─ whatsapp.js       WhatsAppService      — receiveInboundMessage, sendMessage, ...
├─ payments.js       PaymentService       — createReference, verifyWebhook, ...
├─ logistics.js      LogisticsService     — matchPartners, createDeliveryRequest, ...
├─ notifications.js  NotificationService  — send, notifyOwner, notifyCustomer
└─ index.js          services registry + integrationCapabilities()
```

Every method is a **reserved slot**: it throws `501 not_implemented` rather than
making a call, so the seams can be reviewed and tested before any provider is
chosen. `server/tests/integrations.test.js` asserts the boundaries exist, are
inert, and attempt no network request.

### Turning one on later

A service reports `configured: true` only when its provider name is present in
the environment — `WHATSAPP_PROVIDER`, `PAYMENT_PROVIDER`, `LOGISTICS_PROVIDER`,
`NOTIFICATION_PROVIDER` (see `docs/environment.md`). The credential itself is
read where it is used and is never copied into the config object or logged.
Implementing a provider means filling in that service's methods and calling the
existing status-change service — no schema change and no route change.


## Planned flows

**WhatsApp (Phase 2 of the product spec)**

```
Customer → WhatsApp → Webhook → WhatsAppService → AI reply
        → transaction draft (source='whatsapp')
        → Business owner confirms availability
        → same four status groups as a manual sale
```

`transactions.source` already admits `'whatsapp'`; only `'manual'` is writable
today. The AI must always be disableable and must support human takeover
(spec sections 19–20).

**Payments (Phase 3)**

```
Transaction → PaymentService → reference (e.g. ORDER-1045-83921)
            → provider
            → provider webhook → verified → payment = 'paid'
            → completion stays 'open'
```

**Logistics (Phase 3–4)** — the local half is built:

```
Transaction (delivery_required) → delivery_requests row (destination city derived
  from the address) → GET /logistics/providers matches on service area,
  availability, distance, package capacity and published price
  → partner quotes / business accepts → assign rider + vehicle
  → pending → accepted → picked_up → in_transit → delivered | failed
  → OTP / signature / photo / manual confirmation, with a retry path
```

Still future work behind `LogisticsService`: delegating the request to an
external fleet, receiving their tracking events, and live rider maps. The
status vocabulary, confirmation flow and failure/retry rules above are already
enforced by the local routes, so a provider slot can be added without a schema
change.

Confirmation uses a customer OTP (generated server-side), optionally plus proof
photo, timestamp, GPS or signature (spec section 29). The business owner's own
delivery path (spec section 30) supports OTP, signature, photo or manual
confirmation, and always records who confirmed, when, and where.

**Failed deliveries (spec section 31)** are never deleted: a reason and note are
stored, the transaction stays visible as `delivery='failed'`, and the owner can
retry or reschedule.

## Data already in place for this

- `users.role` accepts `logistics_partner` and `rider`, so partner and rider
  accounts need no auth migration.
- `business_locations` (Phase 2) stores structured `latitude`/`longitude`,
  `city` and `state` — the inputs location matching needs. Distance and radius
  queries can use the SQLite `earthdistance`-style computation or a spatial
  index later without a schema change.
- `transaction_status_history` (Phase 8) records who changed what and when, so
  automated transitions from these services are auditable exactly like manual
  ones.
- Delivery must support many partners in one city; there is no
  one-partner-per-location constraint anywhere in the schema.
