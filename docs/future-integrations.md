# Future integration points

Nothing in this file is implemented, and no external calls are made yet. This is
the reserved shape so Phase 2+ integrations land without redesigning the
transaction core.

## Why these are not built yet

`phase_build_prompt.md` explicitly excludes WhatsApp AI, payment gateways and
webhooks, and logistics partner/rider APIs. The transaction model was designed so
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
| `LogisticsService` | Match partners by service area/availability/distance/price/capacity, create delivery requests, track riders |
| `NotificationService` | Fan out push/email/WhatsApp events (order detected, paid, picked up, delivered, failed, human attention needed) |

None of these may write to `transactions` directly. They go through the same
service layer as the manual path so history and validation stay identical.

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

**Logistics (Phase 3–4)**

```
Transaction (delivery_required) → LogisticsService
  → match on service area, availability, distance, delivery type,
    price, capacity, partner status
  → delivery request → partner → rider
  → status updates: pending → accepted → picked_up → in_transit → delivered
```

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
