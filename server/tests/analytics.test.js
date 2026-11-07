import test, { describe } from 'node:test';
import assert from 'node:assert/strict';
import { api, createBusinessOwner, uniquePhone } from './helpers.js';

async function addProduct(owner, overrides = {}) {
  const res = await api('POST', '/products', {
    token: owner.token,
    body: {
      name: 'Ankara Fabric',
      price_kobo: 100_000,
      stock_quantity: 50,
      ...overrides,
    },
  });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.product;
}

async function addCustomer(owner, name) {
  const res = await api('POST', '/customers', {
    token: owner.token,
    body: { name, phone: uniquePhone() },
  });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.customer;
}

async function sell(owner, items, customerId) {
  const res = await api('POST', '/transactions', {
    token: owner.token,
    body: {
      customer_id: customerId,
      items: items.map((item) => ({ product_id: item.product.id, quantity: item.quantity })),
    },
  });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.transaction;
}

describe('business analysis', () => {
  test('summarises money, products, customers, stock and delivery', async () => {
    const owner = await createBusinessOwner('Analysis Store');
    const fabric = await addProduct(owner, { name: 'Ankara Fabric', price_kobo: 100_000 });
    const thread = await addProduct(owner, {
      name: 'Thread Spool',
      price_kobo: 50_000,
      stock_quantity: 2,
    });
    const customer = await addCustomer(owner, 'Ada Nwosu');

    await sell(owner, [{ product: fabric, quantity: 2 }, { product: thread, quantity: 1 }], customer.id);
    await sell(owner, [{ product: fabric, quantity: 1 }]);

    const res = await api('GET', '/analytics/overview?days=7&tz_offset_minutes=0', {
      token: owner.token,
    });
    assert.equal(res.status, 200, JSON.stringify(res.body));

    assert.equal(res.body.range.days, 7);
    assert.equal(res.body.totals.orders, 2);
    assert.equal(res.body.totals.revenueKobo, 350_000);
    assert.equal(res.body.totals.averageOrderKobo, 175_000);
    assert.equal(res.body.totals.collectedKobo, 0);
    assert.equal(res.body.totals.outstandingKobo, 350_000);

    assert.equal(res.body.daily.length, 7);
    assert.equal(
      res.body.daily.reduce((sum, day) => sum + day.revenueKobo, 0),
      350_000
    );

    assert.equal(res.body.topProducts[0].name, 'Ankara Fabric');
    assert.equal(res.body.topProducts[0].quantity, 3);
    assert.equal(res.body.topProducts[0].revenueKobo, 300_000);

    assert.equal(res.body.customers.buyers, 1);
    assert.equal(res.body.customers.newCustomers, 1);
    assert.equal(res.body.customers.returning, 0);
    assert.equal(res.body.customers.walkInOrders, 1);

    assert.equal(res.body.inventory.activeProducts, 2);
    assert.equal(res.body.inventory.lowStock, 1);
    assert.equal(res.body.inventory.outOfStock, 0);
    assert.equal(res.body.inventory.inventoryValueKobo, 5_100_000);
    assert.equal(res.body.inventory.products[0].name, 'Thread Spool');

    const unpaid = res.body.paymentMix.find((slice) => slice.status === 'unpaid');
    assert.equal(unpaid.count, 2);
    assert.equal(unpaid.amountKobo, 350_000);
    const pending = res.body.orderMix.find((slice) => slice.status === 'pending');
    assert.equal(pending.count, 2);
    assert.equal(res.body.logistics.requests, 0);
    assert.equal(res.body.logistics.successRate, null);
  });

  test('an owner with no sales still gets a shaped report', async () => {
    const owner = await createBusinessOwner('Quiet Store');
    const res = await api('GET', '/analytics/overview', { token: owner.token });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.totals.orders, 0);
    assert.equal(res.body.totals.revenueKobo, 0);
    assert.equal(res.body.daily.length, 30);
    assert.deepEqual(res.body.topProducts, []);
    assert.equal(res.body.customers.buyers, 0);
  });

  test('only the owner may read the business analysis', async () => {
    const owner = await createBusinessOwner('Private Books');
    const created = await api('POST', '/staff', {
      token: owner.token,
      body: { full_name: 'Front Desk' },
    });
    const code = created.body.staff.staffCode;
    await api('POST', '/staff/claim', { body: { staff_code: code } });
    await api('POST', '/staff/activate', {
      body: { staff_code: code, password: 'Str0ngPass!23' },
    });
    const login = await api('POST', '/auth/login', {
      body: { identifier: code, password: 'Str0ngPass!23' },
    });

    const res = await api('GET', '/analytics/overview', {
      token: login.body.access_token,
    });
    assert.equal(res.status, 403, JSON.stringify(res.body));
  });
});
