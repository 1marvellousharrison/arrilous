import test, { describe } from 'node:test';
import assert from 'node:assert/strict';
import { api, createBusinessOwner } from './helpers.js';

const STAFF_PASSWORD = 'Str0ngPass!23';

async function addProduct(owner, overrides = {}) {
  const res = await api('POST', '/products', {
    token: owner.token,
    body: {
      name: 'Bag of Rice',
      price_kobo: 5000000,
      stock_quantity: 20,
      ...overrides,
    },
  });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.product;
}

async function staffSession(owner, fullName = 'Shop Assistant') {
  const created = await api('POST', '/staff', {
    token: owner.token,
    body: { full_name: fullName },
  });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  const code = created.body.staff.staffCode;
  await api('POST', '/staff/claim', { body: { staff_code: code } });
  const activated = await api('POST', '/staff/activate', {
    body: { staff_code: code, password: STAFF_PASSWORD },
  });
  assert.equal(activated.status, 200, JSON.stringify(activated.body));
  const login = await api('POST', '/auth/login', {
    body: { identifier: code, password: STAFF_PASSWORD },
  });
  assert.equal(login.status, 200, JSON.stringify(login.body));
  return login.body.access_token;
}

describe('low-stock alerts', () => {
  test('a product at the threshold raises one low-stock alert', async () => {
    const owner = await createBusinessOwner('Shelf Watch');
    const product = await addProduct(owner, { stock_quantity: 5 });

    const inbox = await api('GET', '/notifications', { token: owner.token });
    assert.equal(inbox.status, 200, JSON.stringify(inbox.body));
    assert.equal(inbox.body.counts.lowStock, 1);
    assert.equal(inbox.body.counts.outOfStock, 0);
    assert.equal(inbox.body.lowStock.products[0].id, product.id);
    assert.equal(inbox.body.lowStock.products[0].stockQuantity, 5);

    const alert = inbox.body.notifications.find((n) => n.type === 'low_stock');
    assert.ok(alert);
    assert.equal(alert.severity, 'warning');
    assert.equal(alert.productId, product.id);
    assert.equal(alert.readAt, null);
  });

  test('an out-of-stock product is an error, not a warning', async () => {
    const owner = await createBusinessOwner('Empty Shelf');
    await addProduct(owner, { name: 'Soap', stock_quantity: 0 });

    const inbox = await api('GET', '/notifications', { token: owner.token });
    assert.equal(inbox.body.counts.lowStock, 1);
    assert.equal(inbox.body.counts.outOfStock, 1);
    assert.equal(inbox.body.counts.errors, 1);

    const alert = inbox.body.notifications.find((n) => n.type === 'low_stock');
    assert.equal(alert.severity, 'error');
    assert.match(alert.title, /Out of stock/);
  });

  test('re-reading the inbox does not duplicate the alert', async () => {
    const owner = await createBusinessOwner('One Alert');
    await addProduct(owner, { stock_quantity: 3 });

    await api('GET', '/notifications', { token: owner.token });
    const second = await api('GET', '/notifications', { token: owner.token });
    const alerts = second.body.notifications.filter((n) => n.type === 'low_stock');
    assert.equal(alerts.length, 1);
    assert.equal(second.body.counts.lowStock, 1);
  });

  test('restocking resolves the alert', async () => {
    const owner = await createBusinessOwner('Restock Store');
    const product = await addProduct(owner, { stock_quantity: 2 });
    await api('GET', '/notifications', { token: owner.token });

    const restocked = await api('PATCH', `/products/${product.id}`, {
      token: owner.token,
      body: { stock_quantity: 40 },
    });
    assert.equal(restocked.status, 200, JSON.stringify(restocked.body));

    const inbox = await api('GET', '/notifications', { token: owner.token });
    assert.equal(inbox.body.counts.lowStock, 0);
    const alert = inbox.body.notifications.find((n) => n.type === 'low_stock');
    assert.ok(alert.readAt, 'the resolved alert is marked read');
  });

  test('archiving resolves the alert and restoring raises it again', async () => {
    const owner = await createBusinessOwner('Archive Store');
    const product = await addProduct(owner, { stock_quantity: 1 });
    await api('GET', '/notifications', { token: owner.token });

    await api('POST', `/products/${product.id}/archive`, { token: owner.token });
    const archived = await api('GET', '/notifications', { token: owner.token });
    assert.equal(archived.body.counts.lowStock, 0);

    await api('POST', `/products/${product.id}/restore`, { token: owner.token });
    const restored = await api('GET', '/notifications', { token: owner.token });
    assert.equal(restored.body.counts.lowStock, 1);
    assert.equal(
      restored.body.notifications.filter(
        (n) => n.type === 'low_stock' && n.readAt === null
      ).length,
      1
    );
  });

  test('the dashboard carries the same low-stock summary', async () => {
    const owner = await createBusinessOwner('Dashboard Shelf');
    await addProduct(owner, { name: 'Milk', stock_quantity: 0 });
    await addProduct(owner, { name: 'Sugar', stock_quantity: 4 });

    const summary = await api('GET', '/dashboard/summary', { token: owner.token });
    assert.equal(summary.status, 200, JSON.stringify(summary.body));
    assert.equal(summary.body.lowStock.count, 2);
    assert.equal(summary.body.lowStock.outOfStock, 1);
    assert.deepEqual(
      summary.body.lowStock.products.map((p) => p.name),
      ['Milk', 'Sugar']
    );
    // The old catalog shape is untouched for clients that only read it.
    assert.deepEqual(summary.body.catalog, { activeProducts: 2, customers: 0 });
  });

  test('restocking adds to the existing count instead of replacing it', async () => {
    const owner = await createBusinessOwner('Add Stock Store');
    const product = await addProduct(owner, { name: 'Garri', stock_quantity: 2 });
    await api('GET', '/notifications', { token: owner.token });

    const restocked = await api('POST', `/products/${product.id}/restock`, {
      token: owner.token,
      body: { quantity: 10 },
    });
    assert.equal(restocked.status, 200, JSON.stringify(restocked.body));
    assert.equal(restocked.body.product.stockQuantity, 12);

    const second = await api('POST', `/products/${product.id}/restock`, {
      token: owner.token,
      body: { quantity: 3 },
    });
    assert.equal(second.body.product.stockQuantity, 15);

    const inbox = await api('GET', '/notifications', { token: owner.token });
    assert.equal(inbox.body.counts.lowStock, 0);
  });

  test('restock rejects zero and negatives', async () => {
    const owner = await createBusinessOwner('Bad Restock Store');
    const product = await addProduct(owner, { name: 'Salt', stock_quantity: 1 });

    for (const quantity of [0, -4]) {
      const res = await api('POST', `/products/${product.id}/restock`, {
        token: owner.token,
        body: { quantity },
      });
      assert.equal(res.status, 422, JSON.stringify(res.body));
    }
  });

  test('opening the inbox clears routine alerts but keeps stock warnings', async () => {
    const owner = await createBusinessOwner('Inbox Read Store');
    await addProduct(owner, { name: 'Beans', stock_quantity: 1 });

    const before = await api('GET', '/notifications', { token: owner.token });
    const alert = before.body.notifications.find((n) => n.type === 'low_stock');
    assert.equal(alert.readAt, null);

    await api('POST', '/notifications/read-all', { token: owner.token });
    const after = await api('GET', '/notifications', { token: owner.token });
    const kept = after.body.notifications.find((n) => n.id === alert.id);
    assert.equal(kept.readAt, null, 'a low-stock alert is not cleared by opening the page');

    await api('POST', '/notifications/read-all', {
      token: owner.token,
      body: { include_important: true },
    });
    const cleared = await api('GET', '/notifications', { token: owner.token });
    assert.ok(cleared.body.notifications.find((n) => n.id === alert.id).readAt);
  });

  test('staff still see the shop-wide shelf warning, but not the owner\'s alert row', async () => {
    const owner = await createBusinessOwner('Team Shelf');
    const token = await staffSession(owner);
    await addProduct(owner, { name: 'Bread', stock_quantity: 2 });

    const inbox = await api('GET', '/notifications', { token });
    assert.equal(inbox.status, 200, JSON.stringify(inbox.body));
    assert.equal(inbox.body.counts.lowStock, 1);
    assert.equal(inbox.body.lowStock.products[0].name, 'Bread');
    assert.ok(
      !inbox.body.notifications.some((n) => n.type === 'low_stock'),
      'the low-stock row belongs to the owner\'s inbox'
    );

    const summary = await api('GET', '/dashboard/summary', { token });
    assert.equal(summary.body.lowStock.count, 1);
  });
});
