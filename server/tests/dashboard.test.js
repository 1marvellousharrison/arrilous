import test, { describe } from 'node:test';
import assert from 'node:assert/strict';
import { api, createBusinessOwner } from './helpers.js';

/**
 * Phase 12 — the dashboard must report what is actually in the database.
 *
 * The number that matters most is the cancelled one: a cancelled sale is
 * excluded from every money total, because counting it as revenue would
 * overstate what the business earned.
 */

async function store(name = 'Dash Store') {
  const owner = await createBusinessOwner(name);
  const product = await api('POST', '/products', {
    token: owner.token,
    body: { name: 'Black Shirt', price_kobo: 1_500_000 },
  });
  return { ...owner, product: product.body.product };
}

async function sell(owner, product, { quantity = 1, ...overrides } = {}) {
  const res = await api('POST', '/transactions', {
    token: owner.token,
    body: { items: [{ product_id: product.id, quantity }], ...overrides },
  });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.transaction;
}

async function setStatus(owner, id, body) {
  const res = await api('PATCH', `/transactions/${id}/statuses`, {
    token: owner.token,
    body,
  });
  assert.equal(res.status, 200, JSON.stringify(res.body));
  return res.body.transaction;
}

/**
 * Walks a delivery from wherever it is up to `target`, one legal step at a time.
 *
 * The Phase 7 table has no shortcuts: pending -> accepted -> picked_up ->
 * in_transit -> delivered. Jumping straight to in_transit is rejected, which is
 * the correct behaviour, so tests that need a delivery state have to walk it.
 */
async function walkDelivery(owner, id, target) {
  const order = ['pending', 'accepted', 'picked_up', 'in_transit', 'delivered'];
  const detail = await api('GET', `/transactions/${id}`, { token: owner.token });
  const from = detail.body.transaction.deliveryStatus;
  const start = order.indexOf(from);
  const end = order.indexOf(target);
  assert.ok(start >= 0 && end >= 0, `unexpected delivery states ${from} -> ${target}`);
  for (let i = start + 1; i <= end; i++) {
    await setStatus(owner, id, { deliveryStatus: order[i] });
  }
}

async function summary(owner) {
  const res = await api('GET', '/dashboard/summary', { token: owner.token });
  assert.equal(res.status, 200, JSON.stringify(res.body));
  return res.body;
}

describe('phase 12 — dashboard summary', () => {
  test('starts at zero rather than showing placeholder numbers', async () => {
    const owner = await store('Empty Store');
    const body = await summary(owner);

    assert.equal(body.totals.transactionCount, 0);
    assert.equal(body.totals.grossSalesKobo, 0);
    assert.equal(body.totals.collectedKobo, 0);
    assert.equal(body.totals.outstandingKobo, 0);
    assert.deepEqual(body.recent, []);
    assert.deepEqual(body.catalog, { activeProducts: 1, customers: 0 });
    for (const value of Object.values(body.counts)) {
      assert.equal(value, 0);
    }
  });

  test('counts the catalog and customers for the business card', async () => {
    const owner = await store('Catalog Store');

    await api('POST', '/products', {
      token: owner.token,
      body: { name: 'Second Product', price_kobo: 250_000, stock_quantity: 3 },
    });
    const archived = await api('POST', '/products', {
      token: owner.token,
      body: { name: 'Retired Product', price_kobo: 100_000, stock_quantity: 1 },
    });
    const { body: retired } = await api('POST', `/products/${archived.body.product.id}/archive`, {
      token: owner.token,
    });
    const added = await api('POST', '/customers', {
      token: owner.token,
      body: { name: 'Ada Nwosu', phone: '+2348010000001' },
    });
    assert.equal(added.status, 201, JSON.stringify(added.body));

    const body = await summary(owner);
    assert.equal(body.catalog.activeProducts, 2, 'archived products do not count');
    assert.equal(body.catalog.customers, 1);
    assert.equal(retired.product.active, false);
  });

  test('the catalog counts never leak across businesses', async () => {
    const mine = await store('Mine');
    const theirs = await store('Theirs');

    await api('POST', '/customers', {
      token: theirs.token,
      body: { name: 'Someone Else', phone: '+2348010000009' },
    });

    const body = await summary(mine);
    assert.equal(body.catalog.customers, 0);
    assert.equal(body.catalog.activeProducts, 1, 'only this business catalog');
  });

  test('counts sales, unpaid money and recent transactions', async () => {
    const owner = await store('Counting Store');

    await sell(owner, owner.product, { quantity: 2 }); // 3,000,000 unpaid
    await sell(owner, owner.product, { quantity: 1 }); // 1,500,000 unpaid

    const body = await summary(owner);
    assert.equal(body.totals.transactionCount, 2);
    assert.equal(body.totals.grossSalesKobo, 4_500_000);
    assert.equal(body.totals.collectedKobo, 0);
    assert.equal(body.totals.outstandingKobo, 4_500_000);
    assert.equal(body.counts.pendingPayment, 2);
    assert.equal(body.recent.length, 2);
  });

  test('paid money moves from outstanding to collected', async () => {
    const owner = await store('Paid Store');
    const txn = await sell(owner, owner.product, { quantity: 2 });

    await setStatus(owner, txn.id, { paymentStatus: 'paid' });

    const body = await summary(owner);
    assert.equal(body.totals.collectedKobo, 3_000_000);
    assert.equal(body.totals.outstandingKobo, 0);
    assert.equal(body.counts.pendingPayment, 0, 'paid is no longer pending payment');
  });

  test('delivery states are counted separately', async () => {
    const owner = await store('Delivery Dash');
    const a = await sell(owner, owner.product, {
      delivery_required: true,
      delivery_address: '10 Adeola Odeku St',
    });
    const b = await sell(owner, owner.product, {
      delivery_required: true,
      delivery_address: '5 Bourdillon Rd',
    });

    await walkDelivery(owner, b.id, 'in_transit');

    const body = await summary(owner);
    // a is still at pending, b has moved to in_transit.
    assert.equal(body.counts.awaitingDelivery, 1);
    assert.equal(body.counts.inTransit, 1);

    await walkDelivery(owner, a.id, 'delivered');
    const after = await summary(owner);
    assert.equal(after.counts.awaitingDelivery, 0);
    assert.equal(after.counts.inTransit, 1);
  });

  test('completed and failed are counted on their own axes', async () => {
    const owner = await store('State Dash');
    const done = await sell(owner, owner.product);
    const failed = await sell(owner, owner.product);

    await setStatus(owner, done.id, {
      orderStatus: 'confirmed',
      paymentStatus: 'paid',
      completionStatus: 'completed',
    });
    await setStatus(owner, failed.id, { paymentStatus: 'failed' });

    const body = await summary(owner);
    assert.equal(body.counts.completed, 1);
    assert.equal(body.counts.failed, 1);
  });

  test('a cancelled sale is excluded from the money totals', async () => {
    const owner = await store('Cancel Dash');
    const keep = await sell(owner, owner.product, { quantity: 1 });
    const drop = await sell(owner, owner.product, { quantity: 10 });

    await setStatus(owner, drop.id, { orderStatus: 'cancelled' });

    const body = await summary(owner);
    assert.equal(body.totals.grossSalesKobo, 1_500_000, 'only the live sale counts');
    assert.equal(body.totals.transactionCount, 1);
    assert.equal(body.totals.outstandingKobo, 1_500_000);
    assert.equal(body.counts.cancelled, 1, 'but the cancellation is still visible');

    // The cancelled sale is still a real record an owner can open.
    assert.equal(body.recent.length, 2);
    assert.ok(body.recent.some((t) => t.id === drop.id));
    assert.ok(body.recent.some((t) => t.id === keep.id));
  });

  test('recent transactions come back newest first', async () => {
    const owner = await store('Recent Store');
    const first = await sell(owner, owner.product);
    const second = await sell(owner, owner.product);

    const body = await summary(owner);
    assert.equal(body.recent[0].id, second.id, 'the newest sale leads');
    assert.equal(body.recent[1].id, first.id);
  });

  test('the recent list is capped so it cannot grow without bound', async () => {
    const owner = await store('Big Store');
    for (let i = 0; i < 10; i++) {
      await sell(owner, owner.product);
    }
    const body = await summary(owner);
    assert.equal(body.recent.length, 8);
    assert.equal(body.totals.transactionCount, 10, 'but the totals still see all ten');
  });

  test('one business never sees another business\'s numbers', async () => {
    const mine = await store('Mine');
    const theirs = await store('Theirs');

    await sell(mine, mine.product, { quantity: 3 });
    await sell(theirs, theirs.product, { quantity: 9 });

    const body = await summary(mine);
    assert.equal(body.totals.transactionCount, 1);
    assert.equal(body.totals.grossSalesKobo, 4_500_000);
    assert.equal(body.recent.every((t) => t.businessId === mine.business.id), true);
  });

  test('the dashboard needs a business and a signed-in owner', async () => {
    const owner = await store('Guarded Store');
    assert.equal((await api('GET', '/dashboard/summary')).status, 401);
  });
});

describe('phase 12 — dashboard business card', () => {
  test('reports the business name and its location', async () => {
    const owner = await createBusinessOwner('Card Store');
    await api('PUT', '/business/location', {
      token: owner.token,
      body: { address: '12 Allen Avenue', city: 'Ikeja', country: 'Nigeria' },
    });

    const res = await api('GET', '/dashboard/business', { token: owner.token });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.businessName, 'Card Store');
    assert.equal(res.body.location.address, '12 Allen Avenue');
    assert.equal(res.body.location.city, 'Ikeja');
  });

  test('reports a null location before setup finishes', async () => {
    const owner = await createBusinessOwner('No Location Store');
    const res = await api('GET', '/dashboard/business', { token: owner.token });
    assert.equal(res.status, 200);
    assert.equal(res.body.location, null);
  });
});

describe('phase 11 — transaction filters', () => {
  test('filters by a single status value', async () => {
    const owner = await store('Filter Store');
    const paid = await sell(owner, owner.product);
    await sell(owner, owner.product);
    await setStatus(owner, paid.id, { paymentStatus: 'paid' });

    const res = await api('GET', '/transactions?payment_status=paid', {
      token: owner.token,
    });
    assert.equal(res.status, 200);
    assert.equal(res.body.transactions.length, 1);
    assert.equal(res.body.transactions[0].id, paid.id);
  });

  test('filters by source', async () => {
    const owner = await store('Source Store');
    await sell(owner, owner.product);

    const res = await api('GET', '/transactions?source=manual', { token: owner.token });
    assert.equal(res.body.transactions.length, 1);

    const whatsapp = await api('GET', '/transactions?source=whatsapp', {
      token: owner.token,
    });
    assert.equal(whatsapp.status, 200);
    assert.equal(whatsapp.body.transactions.length, 0, 'no WhatsApp sales exist yet');
  });

  test('filters by a date range', async () => {
    const owner = await store('Date Store');
    const txn = await sell(owner, owner.product);

    const today = new Date();
    const startOfToday = new Date(today.getFullYear(), today.getMonth(), today.getDate());
    const endOfToday = new Date(
      today.getFullYear(),
      today.getMonth(),
      today.getDate(),
      23,
      59,
      59,
      999,
    );

    const inside = await api(
      'GET',
      `/transactions?from=${startOfToday.toISOString()}&to=${endOfToday.toISOString()}`,
      { token: owner.token },
    );
    assert.equal(inside.body.transactions.length, 1, 'a sale made today is in range');

    const tomorrow = new Date(startOfToday.getTime() + 86_400_000);
    const future = await api('GET', `/transactions?from=${tomorrow.toISOString()}`, {
      token: owner.token,
    });
    assert.equal(future.body.transactions.length, 0, 'tomorrow excludes today');

    const past = await api(
      'GET',
      `/transactions?to=${new Date(startOfToday.getTime() - 86_400_000).toISOString()}`,
      { token: owner.token },
    );
    assert.equal(past.body.transactions.length, 0, 'yesterday excludes today');
    assert.equal(past.status, 200);
    assert.ok(txn);
  });

  test('a bare calendar day includes the whole day', async () => {
    const owner = await store('Bare Date Store');
    await sell(owner, owner.product);

    // This is the form the docs promise and a hand-written request uses. `to`
    // must mean the end of the day, not midnight, or a sale made this morning
    // would be filtered out.
    const start = new Date();
    const dateOnly = [
      start.getUTCFullYear(),
      String(start.getUTCMonth() + 1).padStart(2, '0'),
      String(start.getUTCDate()).padStart(2, '0'),
    ].join('-');

    const sameDay = await api('GET', `/transactions?from=${dateOnly}&to=${dateOnly}`, {
      token: owner.token,
    });
    assert.equal(
      sameDay.body.transactions.length,
      1,
      'a sale earlier today is inside a same-day range',
    );

    const fromOnly = await api('GET', `/transactions?from=${dateOnly}`, {
      token: owner.token,
    });
    assert.equal(fromOnly.body.transactions.length, 1);

    const toOnly = await api('GET', `/transactions?to=${dateOnly}`, {
      token: owner.token,
    });
    assert.equal(toOnly.body.transactions.length, 1, 'to includes the whole day');
  });

  test('rejects an inverted date range', async () => {
    const owner = await store('Bad Range Store');
    const res = await api(
      'GET',
      '/transactions?from=2026-05-02T00:00:00Z&to=2026-05-01T00:00:00Z',
      { token: owner.token },
    );
    assert.equal(res.status, 422);
  });

  test('rejects a date that is not a date', async () => {
    const owner = await store('Bad Date Store');
    const res = await api('GET', '/transactions?from=yesterday', { token: owner.token });
    assert.equal(res.status, 422);
  });

  test('paginates', async () => {
    const owner = await store('Paged Store');
    for (let i = 0; i < 5; i++) await sell(owner, owner.product);

    const first = await api('GET', '/transactions?limit=2&offset=0', {
      token: owner.token,
    });
    assert.equal(first.body.transactions.length, 2);

    const second = await api('GET', '/transactions?limit=2&offset=2', {
      token: owner.token,
    });
    assert.equal(second.body.transactions.length, 2);

    const ids = new Set([
      ...first.body.transactions.map((t) => t.id),
      ...second.body.transactions.map((t) => t.id),
    ]);
    assert.equal(ids.size, 4, 'pages do not overlap');
  });
});