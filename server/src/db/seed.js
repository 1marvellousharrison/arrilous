import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { config } from '../config.js';
import { closeDb, run, runMigrations, transaction } from './index.js';
import { hashPassword } from '../lib/password.js';

/**
 * Phase 17 — development seed data.
 *
 * Builds the "ABC Fashion Store" scenario from `phase_build_prompt.md` so the
 * dashboard, list filters, and timeline have something realistic to show, plus
 * the logistics network of the integrated spec: one partner organization with
 * coverage, pricing and fleet, one rider, and the delivery requests that hang
 * off the delivery-required transactions. This is development/test data only
 * and refuses to touch a production database.
 *
 * The seed is idempotent: it owns the owner, partner and rider accounts (by
 * email) and rebuilds everything they own from scratch on every run, so running
 * it twice does not double the data. Nothing outside those accounts is touched.
 */

export const SEED_OWNER_EMAIL = 'owner@abcfashion.test';
export const SEED_OWNER_PASSWORD = process.env.SEED_PASSWORD ?? 'Str0ngPass!23';
export const SEED_BUSINESS_NAME = 'ABC Fashion Store';
export const SEED_PARTNER_EMAIL = 'partner@swiftmove.test';
export const SEED_RIDER_EMAIL = 'rider@swiftmove.test';
export const SEED_PARTNER_ORG_NAME = 'SwiftMove Logistics';

const YEAR = new Date().getUTCFullYear();
const naira = (amount) => amount * 100;

/** Products (prices in naira in the prompt; stored as kobo). */
const PRODUCTS = [
  { key: 'shirt', id: 'seed-product-shirt', name: 'Black Shirt', price: naira(15_000), sku: 'SHIRT-BLK', stock: 40 },
  { key: 'jeans', id: 'seed-product-jeans', name: 'Blue Jeans', price: naira(25_000), sku: 'JEANS-BLU', stock: 25 },
  { key: 'cap', id: 'seed-product-cap', name: 'Cap', price: naira(5_000), sku: 'CAP-001', stock: 60 },
];

const CUSTOMERS = [
  { key: 'john', id: 'seed-customer-john', name: 'John Doe', phone: '+2348030000001' },
  { key: 'jane', id: 'seed-customer-jane', name: 'Jane Doe', phone: '+2348030000002' },
];

/**
 * One transaction per state the prompt asks to demonstrate, plus a
 * cancelled/refunded sale so the "cancelled" dashboard count is not always 0.
 *
 * `events` are the status moves after creation; the creation state itself is
 * derived (pending/unpaid/not_required|pending/open) exactly like the API does.
 */
const SCENARIOS = [
  {
    key: 'pending-unpaid',
    customer: 'john',
    items: [['shirt', 1]],
    deliveryRequired: false,
    notes: 'Customer is still deciding.',
    events: [],
  },
  {
    key: 'paid-awaiting-delivery',
    customer: 'jane',
    items: [['jeans', 1], ['cap', 2]],
    deliveryRequired: true,
    deliveryFee: naira(2_000),
    address: '12 Marina Road, Lagos Island',
    events: [
      ['order', 'pending', 'confirmed', 'Stock confirmed.'],
      ['payment', 'unpaid', 'paid', 'Transfer received.'],
    ],
  },
  {
    key: 'in-transit',
    customer: 'john',
    items: [['shirt', 2]],
    deliveryRequired: true,
    deliveryFee: naira(1_500),
    address: '7 Adeola Odeku Street, Victoria Island',
    events: [
      ['order', 'pending', 'confirmed'],
      ['payment', 'unpaid', 'paid'],
      ['delivery', 'pending', 'accepted'],
      ['delivery', 'accepted', 'picked_up'],
      ['delivery', 'picked_up', 'in_transit', 'Rider is on the way.'],
    ],
  },
  {
    key: 'completed',
    customer: 'jane',
    items: [['jeans', 1]],
    deliveryRequired: true,
    deliveryFee: naira(1_000),
    address: '12 Marina Road, Lagos Island',
    events: [
      ['order', 'pending', 'confirmed'],
      ['payment', 'unpaid', 'paid'],
      ['delivery', 'pending', 'accepted'],
      ['delivery', 'accepted', 'picked_up'],
      ['delivery', 'picked_up', 'in_transit'],
      ['delivery', 'in_transit', 'delivered', 'Signed for at the door.'],
      ['completion', 'open', 'completed', 'Sale closed.'],
    ],
  },
  {
    key: 'payment-failed',
    customer: 'john',
    items: [['cap', 3]],
    deliveryRequired: false,
    events: [
      ['order', 'pending', 'confirmed'],
      ['payment', 'unpaid', 'failed', 'Card declined.'],
    ],
  },
  {
    key: 'cancelled-refunded',
    customer: 'jane',
    items: [['shirt', 1]],
    deliveryRequired: false,
    events: [
      ['order', 'pending', 'confirmed'],
      ['payment', 'unpaid', 'paid'],
      ['order', 'confirmed', 'cancelled', 'Customer changed their mind.'],
      ['payment', 'paid', 'refunded', 'Refund sent to source.'],
    ],
  },
];

export function assertSeedAllowed({ isProd, force }) {
  if (isProd && !force) {
    throw new Error(
      'Refusing to seed a production database. Set SEED_FORCE=true to override.'
    );
  }
}

function initialStatuses(scenario) {
  return {
    order: 'pending',
    payment: 'unpaid',
    delivery: scenario.deliveryRequired ? 'pending' : 'not_required',
    completion: 'open',
  };
}

function applyEvents(scenario) {
  const status = initialStatuses(scenario);
  const timeline = [];
  for (const [type, from, to, note] of scenario.events) {
    if (status[type] !== from) {
      throw new Error(
        `Seed scenario "${scenario.key}" moves ${type} from "${from}", but it is "${status[type]}".`
      );
    }
    status[type] = to;
    timeline.push({ type, from, to, note: note ?? null });
  }
  return { status, timeline };
}

function addMinutes(iso, minutes) {
  return new Date(new Date(iso).getTime() + minutes * 60_000).toISOString();
}

export async function seedDatabase({ force = false } = {}) {
  assertSeedAllowed({
    isProd: config.isProd,
    force: force || process.env.SEED_FORCE === 'true',
  });

  // Migrations first, so seeding a brand-new file just works.
  await runMigrations();

  const passwordHash = await hashPassword(SEED_OWNER_PASSWORD);
  const now = Date.now();

  let summary;

  await transaction(async () => {
    // Rebuild from zero. The owner is deleted first so the business (and with
    // it every transaction and delivery request) cascades away before the
    // partner and rider accounts that reference them are removed.
    await run('DELETE FROM users WHERE email = ?', SEED_OWNER_EMAIL);
    await run('DELETE FROM users WHERE email = ?', SEED_RIDER_EMAIL);
    await run('DELETE FROM users WHERE email = ?', SEED_PARTNER_EMAIL);

    const userId = 'seed-user-owner';
    const partnerUserId = 'seed-user-partner';
    const riderUserId = 'seed-user-rider';
    const businessId = 'seed-business-abc';
    const organizationId = 'seed-organization-swiftmove';
    const riderId = 'seed-rider-1';
    const createdAt = new Date(now - 30 * 24 * 60 * 60 * 1000).toISOString();

    await run(
      `INSERT INTO users (id, full_name, email, phone, password_hash, role, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, 'business', 'active', ?, ?)`,
      userId,
      'ABC Fashion Owner',
      SEED_OWNER_EMAIL,
      '+2348030000000',
      passwordHash,
      createdAt,
      createdAt
    );

    // The logistics network accounts (integrated spec 42/43): one partner that
    // owns coverage, pricing and fleet, and one rider working under them.
    await run(
      `INSERT INTO users (id, full_name, email, phone, password_hash, role, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, 'logistics_partner', 'active', ?, ?)`,
      partnerUserId,
      'SwiftMove Dispatch',
      SEED_PARTNER_EMAIL,
      '+2348030000010',
      passwordHash,
      createdAt,
      createdAt
    );

    await run(
      `INSERT INTO users (id, full_name, email, phone, password_hash, role, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, 'rider', 'active', ?, ?)`,
      riderUserId,
      'Musa Bello',
      SEED_RIDER_EMAIL,
      '+2348030000011',
      passwordHash,
      createdAt,
      createdAt
    );

    // The category matches the app's dropdown list, so the seeded business never
    // shows a second fashion option beside 'Fashion & Clothing'.
    await run(
      `INSERT INTO businesses
         (id, owner_user_id, business_name, business_category, business_description,
          phone, email, created_at, updated_at)
       VALUES (?, ?, ?, 'Fashion & Clothing', 'Clothing and accessories.', ?, ?, ?, ?)`,
      businessId,
      userId,
      SEED_BUSINESS_NAME,
      '+2348030000000',
      SEED_OWNER_EMAIL,
      createdAt,
      createdAt
    );

    await run(
      `INSERT INTO business_locations
         (id, business_id, address, city, area, state, country, latitude, longitude, created_at, updated_at)
       VALUES ('seed-location-abc', ?, '24 Broad Street', 'Lagos', 'Obalende', 'Lagos', 'Nigeria', 6.4541, 3.3947, ?, ?)`,
      businessId,
      createdAt,
      createdAt
    );

    for (const product of PRODUCTS) {
      await run(
        `INSERT INTO products
           (id, business_id, name, description, category, price_kobo, sku,
            stock_quantity, active, created_at, updated_at)
         VALUES (?, ?, ?, ?, 'Fashion', ?, ?, ?, 1, ?, ?)`,
        product.id,
        businessId,
        product.name,
        `${product.name} from ABC Fashion Store.`,
        product.price,
        product.sku,
        product.stock,
        createdAt,
        createdAt
      );
    }

    for (const customer of CUSTOMERS) {
      await run(
        `INSERT INTO customers (id, business_id, name, phone, email, address, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, 'Lagos, Nigeria', ?, ?)`,
        customer.id,
        businessId,
        customer.name,
        customer.phone,
        `${customer.key}@example.com`,
        createdAt,
        createdAt
      );
    }

    const productByKey = Object.fromEntries(PRODUCTS.map((p) => [p.key, p]));
    const customerByKey = Object.fromEntries(CUSTOMERS.map((c) => [c.key, c]));

    let itemsSeeded = 0;
    let historySeeded = 0;

    for (const [index, scenario] of SCENARIOS.entries()) {
      const { status, timeline } = applyEvents(scenario);
      const transactionId = `seed-txn-${index + 1}`;
      const number = `TXN-${YEAR}-${String(index + 1).padStart(5, '0')}`;
      // Scenario 0 is oldest; the last is newest, so "recent" is meaningful.
      const txCreatedAt = new Date(
        now - (SCENARIOS.length - index) * 5 * 60 * 60 * 1000
      ).toISOString();

      const lines = scenario.items.map(([productKey, quantity]) => {
        const product = productByKey[productKey];
        return {
          product,
          quantity,
          subtotal: product.price * quantity,
        };
      });
      const subtotal = lines.reduce((sum, line) => sum + line.subtotal, 0);
      const deliveryFee = scenario.deliveryFee ?? 0;
      const discount = scenario.discount ?? 0;
      const total = subtotal + deliveryFee - discount;

      const updatedAt = timeline.length
        ? addMinutes(txCreatedAt, timeline.length)
        : txCreatedAt;

      await run(
        `INSERT INTO transactions
           (id, business_id, customer_id, transaction_number, source, subtotal_kobo,
            discount_kobo, delivery_fee_kobo, total_kobo, notes, delivery_required,
            delivery_address, order_status, payment_status, delivery_status,
            completion_status, created_at, updated_at)
         VALUES (?, ?, ?, ?, 'manual', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        transactionId,
        businessId,
        customerByKey[scenario.customer].id,
        number,
        subtotal,
        discount,
        deliveryFee,
        total,
        scenario.notes ?? null,
        scenario.deliveryRequired ? 1 : 0,
        scenario.address ?? null,
        status.order,
        status.payment,
        status.delivery,
        status.completion,
        txCreatedAt,
        updatedAt
      );

      for (const line of lines) {
        await run(
          `INSERT INTO transaction_items
             (id, transaction_id, product_id, product_name_snapshot, quantity,
              unit_price_kobo, subtotal_kobo, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
          `seed-item-${index + 1}-${line.product.key}`,
          transactionId,
          line.product.id,
          line.product.name,
          line.quantity,
          line.product.price,
          line.subtotal,
          txCreatedAt
        );
        itemsSeeded += 1;
      }

      // Creation entry per axis, then one entry per move — the same shape the
      // API writes, so the timeline renders identically.
      const initial = initialStatuses(scenario);
      let order = 0;
      for (const type of ['order', 'payment', 'delivery', 'completion']) {
        await run(
          `INSERT INTO transaction_status_history
             (id, transaction_id, business_id, changed_by_user_id, status_type,
              old_value, new_value, note, created_at)
           VALUES (?, ?, ?, ?, ?, NULL, ?, NULL, ?)`,
          `seed-history-${index + 1}-create-${type}`,
          transactionId,
          businessId,
          userId,
          type,
          initial[type],
          txCreatedAt
        );
        order += 1;
        historySeeded += 1;
      }
      for (const move of timeline) {
        await run(
          `INSERT INTO transaction_status_history
             (id, transaction_id, business_id, changed_by_user_id, status_type,
              old_value, new_value, note, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          `seed-history-${index + 1}-${move.type}-${order}`,
          transactionId,
          businessId,
          userId,
          move.type,
          move.from,
          move.to,
          move.note,
          addMinutes(txCreatedAt, order)
        );
        order += 1;
        historySeeded += 1;
      }
    }

    // --- Logistics network (integrated spec 14/19/42/43) ------------------
    // One partner covering the business's pickup city and both delivery
    // destinations in the scenarios above, so "find providers" returns a real
    // match instead of an empty list.
    const availableUntil = new Date(now + 8 * 60 * 60 * 1000).toISOString();
    const AREAS = [
      { key: 'lagos', id: 'seed-area-org-lagos', city: 'Lagos', area: 'Broad Street', state: 'Lagos', latitude: 6.4541, longitude: 3.3947, radius_km: 30 },
      { key: 'lagos-island', id: 'seed-area-org-lagos-island', city: 'Lagos Island', area: 'Marina', state: 'Lagos', latitude: 6.4549, longitude: 3.3965, radius_km: 20 },
      { key: 'victoria-island', id: 'seed-area-org-victoria-island', city: 'Victoria Island', area: 'Adeola Odeku', state: 'Lagos', latitude: 6.4281, longitude: 3.4219, radius_km: 20 },
    ];

    await run(
      `INSERT INTO logistics_organizations
         (id, owner_user_id, name, phone, email, description, category, is_available,
          availability_started_at, availability_expires_at, planned_hours, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?, 8, ?, ?)`,
      organizationId,
      partnerUserId,
      SEED_PARTNER_ORG_NAME,
      '+2348030000010',
      SEED_PARTNER_EMAIL,
      'Motorcycle and car delivery across Lagos.',
      'Courier',
      createdAt,
      availableUntil,
      createdAt,
      createdAt
    );

    for (const area of AREAS) {
      await run(
        `INSERT INTO logistics_service_areas
           (id, organization_id, city, area, state, country, latitude, longitude, radius_km, created_at)
         VALUES (?, ?, ?, ?, ?, 'Nigeria', ?, ?, ?, ?)`,
        area.id,
        organizationId,
        area.city,
        area.area,
        area.state,
        area.latitude,
        area.longitude,
        area.radius_km,
        createdAt
      );
    }

    // Published rates keyed by the destination city the matcher derives from
    // the delivery address (spec 20/21/45).
    for (const [destination, priceKobo] of [
      ['Lagos', naira(1_500)],
      ['Lagos Island', naira(2_000)],
      ['Victoria Island', naira(2_500)],
    ]) {
      await run(
        `INSERT INTO logistics_pricing (id, organization_id, destination, price_kobo, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
        `seed-price-${destination.toLowerCase().replace(/[^a-z]+/g, '-')}`,
        organizationId,
        destination,
        priceKobo,
        createdAt,
        createdAt
      );
    }

    // Fleet: one motorcycle is held by the delivery that is still in transit,
    // and it comes back when that delivery reaches a terminal status.
    await run(
      `INSERT INTO logistics_vehicles
         (id, organization_id, vehicle_type, total_quantity, available_quantity,
          capacity_category, starting_price_kobo, active, description, created_at, updated_at)
       VALUES (?, ?, 'motorcycle', 8, 7, 'small', ?, 1, ?, ?, ?),
              (?, ?, 'car', 3, 3, 'large', ?, 1, ?, ?, ?)`,
      'seed-vehicle-motorcycle',
      organizationId,
      naira(1_500),
      'Riders\' own motorcycles.',
      createdAt,
      createdAt,
      'seed-vehicle-car',
      organizationId,
      naira(6_000),
      'Air-conditioned cars for premium deliveries.',
      createdAt,
      createdAt
    );

    await run(
      `INSERT INTO logistics_riders
         (id, user_id, organization_id, phone, category, description, is_available,
          availability_started_at, availability_expires_at, planned_hours, current_latitude,
          current_longitude, updated_location_at, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?, 8, 6.4541, 3.3947, ?, ?, ?)`,
      riderId,
      riderUserId,
      organizationId,
      '+2348030000011',
      'Bike messenger',
      'Reliable motorcycle rider for city deliveries.',
      createdAt,
      availableUntil,
      createdAt,
      createdAt,
      createdAt
    );

    for (const area of AREAS) {
      await run(
        `INSERT INTO rider_service_areas
           (id, rider_id, city, area, state, country, latitude, longitude, radius_km, created_at)
         VALUES (?, ?, ?, ?, ?, 'Nigeria', ?, ?, ?, ?)`,
        `${area.id}-rider`,
        riderId,
        area.city,
        area.area,
        area.state,
        area.latitude,
        area.longitude,
        area.radius_km,
        createdAt
      );
    }

    await run(
      `INSERT INTO rider_delivery_modes
         (id, rider_id, mode, capacity_category, rate_kobo, is_primary, active, created_at)
       VALUES (?, ?, 'motorcycle', 'small', ?, 1, 1, ?),
              (?, ?, 'car', 'large', ?, 0, 1, ?)`,
      'seed-mode-motorcycle',
      riderId,
      naira(1_500),
      createdAt,
      'seed-mode-car',
      riderId,
      naira(6_000),
      createdAt
    );

    // One request per delivery-required transaction, each in the state its
    // transaction's delivery axis is already in.
    const DELIVERY_REQUESTS = [
      {
        id: 'seed-request-new',
        transactionId: 'seed-txn-2',
        riderId: null,
        destinationAddress: '12 Marina Road, Lagos Island',
        destinationCity: 'Lagos Island',
        status: 'requested',
        acceptedPrice: null,
        released: false,
        failureReason: null,
        age: 2,
      },
      {
        id: 'seed-request-transit',
        transactionId: 'seed-txn-3',
        riderId,
        destinationAddress: '7 Adeola Odeku Street, Victoria Island',
        destinationCity: 'Victoria Island',
        status: 'in_transit',
        acceptedPrice: naira(1_500),
        released: false,
        failureReason: null,
        age: 6,
      },
      {
        id: 'seed-request-done',
        transactionId: 'seed-txn-4',
        riderId,
        destinationAddress: '12 Marina Road, Lagos Island',
        destinationCity: 'Lagos Island',
        status: 'delivered',
        acceptedPrice: naira(2_000),
        released: true,
        failureReason: null,
        age: 30,
      },
    ];

    let requestsSeeded = 0;
    for (const request of DELIVERY_REQUESTS) {
      const requestedAt = new Date(now - request.age * 60 * 60 * 1000).toISOString();
      await run(
        `INSERT INTO delivery_requests
           (id, transaction_id, business_id, organization_id, rider_id,
            pickup_address, pickup_city, destination_address, destination_city,
            package_description, package_size, preferred_mode,
            published_price_kobo, accepted_price_kobo, status, failure_reason,
            created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, 'Lagos', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        request.id,
        request.transactionId,
        businessId,
        organizationId,
        request.riderId,
        '24 Broad Street',
        request.destinationAddress,
        request.destinationCity,
        'Apparel order',
        'small',
        'motorcycle',
        naira(2_000),
        request.acceptedPrice,
        request.status,
        request.failureReason,
        requestedAt,
        requestedAt
      );
      // An assignment row only exists once a rider actually holds the job —
      // the brand-new request has no rider, so no vehicle is checked out yet.
      if (request.riderId) {
        await run(
          `INSERT INTO delivery_assignments
             (id, delivery_request_id, rider_id, vehicle_id, assigned_by_user_id,
              assigned_at, released_at)
           VALUES (?, ?, ?, ?, ?, ?, ?)`,
          `seed-assignment-${request.id}`,
          request.id,
          request.riderId,
          'seed-vehicle-motorcycle',
          partnerUserId,
          requestedAt,
          request.released ? requestedAt : null
        );
      }
      requestsSeeded += 1;
    }

    // The unread work the partner sees when they open their workspace (spec 27).
    await run(
      `INSERT INTO logistics_notifications
         (id, user_id, delivery_request_id, kind, title, body, read_at, created_at)
       VALUES (?, ?, ?, 'delivery_requested', 'New delivery request',
               'ABC Fashion Store is looking for a rider to Lagos Island.', NULL, ?)`,
      'seed-notification-request',
      partnerUserId,
      'seed-request-new',
      new Date(now - 2 * 60 * 60 * 1000).toISOString()
    );
    await run(
      `INSERT INTO logistics_notifications
         (id, user_id, delivery_request_id, kind, title, body, read_at, created_at)
       VALUES (?, ?, ?, 'delivery_assigned', 'Rider assigned',
               'Musa Bello is handling TXN delivery to Victoria Island.', ?, ?)`,
      'seed-notification-assigned',
      userId,
      'seed-request-transit',
      new Date(now - 5 * 60 * 60 * 1000).toISOString(),
      new Date(now - 6 * 60 * 60 * 1000).toISOString()
    );

    summary = {
      owner: SEED_OWNER_EMAIL,
      password: SEED_OWNER_PASSWORD,
      business: SEED_BUSINESS_NAME,
      products: PRODUCTS.length,
      customers: CUSTOMERS.length,
      transactions: SCENARIOS.length,
      items: itemsSeeded,
      history: historySeeded,
      organization: SEED_PARTNER_ORG_NAME,
      partner: SEED_PARTNER_EMAIL,
      rider: SEED_RIDER_EMAIL,
      deliveryRequests: requestsSeeded,
    };
  });

  return summary;
}

const isMain =
  process.argv[1] &&
  path.resolve(process.argv[1]).toLowerCase() ===
    fileURLToPath(import.meta.url).toLowerCase();

if (isMain) {
  try {
    const summary = await seedDatabase();
    console.log('Seeded development data:');
    console.log(`  business     ${summary.business}`);
    console.log(`  owner        ${summary.owner}`);
    console.log(`  password     ${summary.password}`);
    console.log(`  products     ${summary.products}`);
    console.log(`  customers    ${summary.customers}`);
    console.log(`  transactions ${summary.transactions}`);
    console.log(`  items        ${summary.items}`);
    console.log(`  history rows ${summary.history}`);
    console.log(`  organization ${summary.organization}`);
    console.log(`  partner      ${summary.partner}`);
    console.log(`  rider        ${summary.rider}`);
    console.log(`  deliveries   ${summary.deliveryRequests}`);
  } catch (error) {
    console.error(`Seed error: ${error.message}`);
    process.exitCode = 1;
  } finally {
    await closeDb();
  }
}
