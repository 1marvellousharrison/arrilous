import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

// Env must be set before importing anything that reads config.js.
const dbDir = fs.mkdtempSync(path.join(os.tmpdir(), 'dee-seed-test-'));
process.env.NODE_ENV = 'test';
process.env.DATABASE_PATH = path.join(dbDir, 'seed.db');
process.env.DATABASE_URL = '';
process.env.JWT_SECRET = 'test-secret-not-used-in-production';
process.env.RATE_LIMIT_MAX = '1000';

const {
  seedDatabase,
  assertSeedAllowed,
  SEED_OWNER_EMAIL,
  SEED_BUSINESS_NAME,
  SEED_RIDER_EMAIL,
} = await import('../src/db/seed.js');
const { closeDb, queryAll, queryOne } = await import('../src/db/index.js');

after(() => {
  closeDb();
  fs.rmSync(dbDir, { recursive: true, force: true });
});

async function business() {
  return await queryOne(
    `SELECT b.* FROM businesses b
       JOIN users u ON u.id = b.owner_user_id
      WHERE u.email = ?`,
    SEED_OWNER_EMAIL
  );
}

test('refuses to seed production unless forced', () => {
  assert.throws(() => assertSeedAllowed({ isProd: true, force: false }), /production/i);
  assert.doesNotThrow(() => assertSeedAllowed({ isProd: true, force: true }));
  assert.doesNotThrow(() => assertSeedAllowed({ isProd: false, force: false }));
});

test('seeds the ABC Fashion Store catalog and customers', async () => {
  const summary = await seedDatabase();
  assert.equal(summary.business, SEED_BUSINESS_NAME);

  const row = await business();
  assert.ok(row, 'the seed owner has a business');
  assert.equal(row.business_name, SEED_BUSINESS_NAME);

  const products = await queryAll(
    'SELECT name, price_kobo, sku FROM products WHERE business_id = ? ORDER BY price_kobo DESC',
    row.id
  );
  assert.deepEqual(
    products.map((p) => [p.name, p.price_kobo]),
    [
      ['Blue Jeans', 2_500_000],
      ['Black Shirt', 1_500_000],
      ['Cap', 500_000],
    ]
  );

  const customers = await queryAll(
    'SELECT name FROM customers WHERE business_id = ? ORDER BY name',
    row.id
  );
  assert.deepEqual(customers.map((c) => c.name), ['Jane Doe', 'John Doe']);

  const location = await queryOne(
    'SELECT city, country FROM business_locations WHERE business_id = ?',
    row.id
  );
  assert.equal(location.city, 'Lagos');
  assert.equal(location.country, 'Nigeria');
});

test('every required transaction state is represented', async () => {
  const row = await business();
  const transactions = await queryAll(
    'SELECT order_status, payment_status, delivery_status, completion_status, delivery_required\n'
      + '  FROM transactions WHERE business_id = ?',
    row.id
  );
  const combos = new Set(
    transactions.map(
      (t) => `${t.order_status}/${t.payment_status}/${t.delivery_status}/${t.completion_status}`
    )
  );

  for (const expected of [
    'pending/unpaid/not_required/open', // pending / unpaid
    'confirmed/paid/pending/open', // paid / awaiting delivery
    'confirmed/paid/in_transit/open', // in transit
    'confirmed/paid/delivered/completed', // completed
    'confirmed/failed/not_required/open', // payment failed
    'cancelled/refunded/not_required/open', // cancelled + refunded
  ]) {
    assert.ok(combos.has(expected), `expected a ${expected} transaction`);
  }
  assert.equal(transactions.length, 6);
});

test('totals are server-consistent with their items', async () => {
  const row = await business();
  const transactions = await queryAll('SELECT * FROM transactions WHERE business_id = ?', row.id);
  for (const tx of transactions) {
    assert.equal(tx.total_kobo, tx.subtotal_kobo + tx.delivery_fee_kobo - tx.discount_kobo);

    const items = await queryAll(
      'SELECT quantity, unit_price_kobo, subtotal_kobo FROM transaction_items WHERE transaction_id = ?',
      tx.id
    );
    const lineSum = items.reduce((sum, item) => sum + item.subtotal_kobo, 0);
    assert.equal(lineSum, tx.subtotal_kobo, `items add up for ${tx.transaction_number}`);
    for (const item of items) {
      assert.equal(item.subtotal_kobo, item.quantity * item.unit_price_kobo);
    }
  }

  const completed = await queryOne(
    'SELECT * FROM transactions WHERE business_id = ? AND completion_status = ?',
    row.id,
    'completed'
  );
  assert.equal(completed.subtotal_kobo, 2_500_000);
  assert.equal(completed.delivery_fee_kobo, 100_000);
  assert.equal(completed.total_kobo, 2_600_000);
});

test('history mirrors creation plus every move, with no invented events', async () => {
  const row = await business();
  const history = await queryAll(
    'SELECT * FROM transaction_status_history WHERE business_id = ?',
    row.id
  );

  // 6 transactions x 4 creation rows + (0+2+5+7+2+4) status moves.
  assert.equal(history.length, 44);
  assert.equal(history.filter((h) => h.old_value === null).length, 24);
  for (const entry of history) {
    assert.ok(entry.new_value, 'every entry records the value it moved to');
    assert.notEqual(entry.old_value, entry.new_value, 'no no-op entries');
    assert.ok(entry.changed_by_user_id, 'every entry names who changed it');
  }

  const completed = await queryOne(
    'SELECT id FROM transactions WHERE business_id = ? AND completion_status = ?',
    row.id,
    'completed'
  );
  const timeline = await queryAll(
    'SELECT * FROM transaction_status_history WHERE transaction_id = ? ORDER BY created_at, seq',
    completed.id
  );
  assert.equal(timeline.length, 11);
  const last = timeline[timeline.length - 1];
  assert.equal(last.status_type, 'completion');
  assert.equal(last.old_value, 'open');
  assert.equal(last.new_value, 'completed');
});

test('seeds a logistics network the business can actually match against', async () => {
  const summary = await seedDatabase();

  const org = await queryOne('SELECT * FROM logistics_organizations WHERE name = ?', 'SwiftMove Logistics');
  assert.ok(org, 'the partner organization exists');
  assert.equal(org.is_available, 1);
  assert.ok(new Date(org.availability_expires_at) > new Date(), 'availability is live');

  // Pickup city + both destinations the scenarios deliver to (spec 19/20/21).
  const cities = (await queryAll(
    'SELECT city FROM logistics_service_areas WHERE organization_id = ? ORDER BY city',
    org.id
  )).map((row) => row.city);
  assert.deepEqual(cities, ['Lagos', 'Lagos Island', 'Victoria Island']);
  assert.ok(
    (await queryAll('SELECT * FROM logistics_service_areas WHERE organization_id = ? AND latitude IS NOT NULL', org.id)).length === 3,
    'service areas carry coordinates for distance ranking'
  );

  // The fleet must have free vehicles or the provider is excluded from matching.
  const vehicles = await queryAll(
    'SELECT vehicle_type, total_quantity, available_quantity FROM logistics_vehicles WHERE organization_id = ?',
    org.id
  );
  assert.deepEqual(
    vehicles.map((v) => [v.vehicle_type, v.total_quantity, v.available_quantity]),
    [
      ['motorcycle', 8, 7],
      ['car', 3, 3],
    ]
  );
  assert.ok(
    vehicles.some((v) => v.available_quantity > 0),
    'at least one vehicle is free so the provider matches'
  );

  const rider = await queryOne('SELECT * FROM logistics_riders WHERE id = ?', 'seed-rider-1');
  assert.ok(rider, 'the rider exists');
  assert.equal(rider.organization_id, org.id);
  assert.equal(rider.is_available, 1);
  assert.ok(rider.availability_expires_at && new Date(rider.availability_expires_at) > new Date());

  // One request per delivery-required transaction, in the state of its axis.
  const requests = await queryAll(
    `SELECT dr.status, dr.destination_city, dr.rider_id, t.delivery_status
       FROM delivery_requests dr
       JOIN transactions t ON t.id = dr.transaction_id
      ORDER BY dr.created_at DESC`
  );
  assert.equal(requests.length, 3);
  assert.deepEqual(
    requests.map((r) => `${r.status}/${r.delivery_status}`),
    ['requested/pending', 'in_transit/in_transit', 'delivered/delivered']
  );

  // The in-transit delivery holds a vehicle; the delivered one released it.
  const held = (await queryOne(
    'SELECT COUNT(*) AS n FROM delivery_assignments WHERE released_at IS NULL'
  )).n;
  assert.equal(held, 1);

  assert.ok(summary.deliveryRequests === 3, 'summary reports the delivery count');
});

test('re-seeding rebuilds the same data instead of doubling it', async () => {
  const first = await business();
  await seedDatabase();

  const count = async (table) =>
    (await queryOne(`SELECT COUNT(*) AS n FROM ${table} WHERE business_id = ?`, first.id)).n;
  assert.equal(await count('products'), 3);
  assert.equal(await count('customers'), 2);
  assert.equal(await count('transactions'), 6);
  assert.equal(await count('transaction_status_history'), 44);

  // Still one owner, one business.
  assert.equal(
    (await queryOne('SELECT COUNT(*) AS n FROM users WHERE email = ?', SEED_OWNER_EMAIL)).n,
    1
  );
  assert.equal(
    (await queryAll('SELECT id FROM businesses WHERE business_name = ?', SEED_BUSINESS_NAME)).length,
    1
  );

  // The logistics network is rebuilt, not duplicated.
  assert.equal((await queryAll('SELECT id FROM logistics_organizations')).length, 1);
  assert.equal((await queryAll('SELECT id FROM logistics_riders')).length, 1);
  assert.equal((await queryAll('SELECT id FROM delivery_requests')).length, 3);
  assert.equal(
    (await queryOne('SELECT COUNT(*) AS n FROM users WHERE email = ?', SEED_RIDER_EMAIL)).n,
    1
  );
});
