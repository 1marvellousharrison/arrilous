import test, { describe } from 'node:test';
import assert from 'node:assert/strict';
import { api, createBusinessOwner, createUser, uniquePhone } from './helpers.js';

async function addCustomer(owner, overrides = {}) {
  const res = await api('POST', '/customers', {
    token: owner.token,
    body: { name: 'Chidi Okeke', phone: uniquePhone(), ...overrides },
  });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.customer;
}

describe('phase 4 — customers', () => {
  test('records a customer and returns it with zeroed history', async () => {
    const owner = await createBusinessOwner('Customer Store');
    const customer = await addCustomer(owner, {
      name: '  Ada Nwosu  ',
      email: 'ada@example.com',
      address: '9 Bode Thomas, Surulere',
    });

    assert.equal(customer.name, 'Ada Nwosu');
    assert.equal(customer.email, 'ada@example.com');
    assert.equal(customer.transactionCount, 0);
    assert.equal(customer.totalSpentKobo, 0);
  });

  test('rejects a customer with no name', async () => {
    const owner = await createBusinessOwner('Validation Store');
    const res = await api('POST', '/customers', {
      token: owner.token,
      body: { phone: uniquePhone() },
    });

    assert.equal(res.status, 422);
    assert.ok(res.body.error.details.some((d) => d.field === 'name'));
  });

  test('rejects a malformed phone number', async () => {
    const owner = await createBusinessOwner('Phone Store');
    const res = await api('POST', '/customers', {
      token: owner.token,
      body: { name: 'Bad Phone', phone: '12345' },
    });

    assert.equal(res.status, 422);
    assert.ok(res.body.error.details.some((d) => d.field === 'phone'));
  });

  test('searches by name, phone and email', async () => {
    const owner = await createBusinessOwner('Search Store');
    await addCustomer(owner, { name: 'Chidi Okeke', phone: '+2348011111111' });
    await addCustomer(owner, { name: 'Bisi Ade', email: 'bisi@example.com' });

    const byName = await api('GET', '/customers?search=chidi', { token: owner.token });
    assert.equal(byName.body.customers.length, 1);

    const byPhone = await api('GET', '/customers?search=801111', { token: owner.token });
    assert.equal(byPhone.body.customers.length, 1);

    const byEmail = await api('GET', '/customers?search=bisi@', { token: owner.token });
    assert.equal(byEmail.body.customers.length, 1);
  });

  test('updates a customer without wiping the other fields', async () => {
    const owner = await createBusinessOwner('Updating Store');
    const customer = await addCustomer(owner, { name: 'Old Name', address: 'Keep Me' });

    const res = await api('PATCH', `/customers/${customer.id}`, {
      token: owner.token,
      body: { name: 'New Name' },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.customer.name, 'New Name');
    assert.equal(res.body.customer.address, 'Keep Me');
  });

  test('rejects an update that changes nothing', async () => {
    const owner = await createBusinessOwner('Empty Update Store');
    const customer = await addCustomer(owner);

    const res = await api('PATCH', `/customers/${customer.id}`, {
      token: owner.token,
      body: {},
    });

    assert.equal(res.status, 422);
  });

  test('a customer record is not an account and never returns credentials', async () => {
    const owner = await createBusinessOwner('Security Store');
    const res = await api('POST', '/customers', {
      token: owner.token,
      body: { name: 'Password Attempt', password: 'hunter2' },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.customer.password, undefined);
    assert.equal(res.body.customer.userId, undefined);
  });

  test('lists a customer\'s transactions and spend total', async () => {
    const owner = await createBusinessOwner('History Store');
    const customer = await addCustomer(owner);
    const product = await (
      await api('POST', '/products', {
        token: owner.token,
        body: { name: 'Beans 5kg', price_kobo: 200000 },
      })
    ).body.product;

    await api('POST', '/transactions', {
      token: owner.token,
      body: { customer_id: customer.id, items: [{ product_id: product.id, quantity: 2 }] },
    });
    await api('POST', '/transactions', {
      token: owner.token,
      body: { customer_id: customer.id, items: [{ product_id: product.id, quantity: 1 }] },
    });

    const detail = await api('GET', `/customers/${customer.id}`, { token: owner.token });
    assert.equal(detail.status, 200);
    assert.equal(detail.body.customer.transactionCount, 2);
    assert.equal(detail.body.customer.totalSpentKobo, 600000);
    assert.equal(detail.body.transactions.length, 2);
  });

  test('one business cannot read or edit another business\'s customer', async () => {
    const owner = await createBusinessOwner('Real Store');
    const intruder = await createBusinessOwner('Thief Store');
    const customer = await addCustomer(owner, { name: 'Private Client' });

    const list = await api('GET', '/customers', { token: intruder.token });
    assert.equal(list.body.customers.length, 0);

    const read = await api('GET', `/customers/${customer.id}`, { token: intruder.token });
    assert.equal(read.status, 404);

    const write = await api('PATCH', `/customers/${customer.id}`, {
      token: intruder.token,
      body: { name: 'Stolen' },
    });
    assert.equal(write.status, 404);
  });

  test('cannot attach a transaction to another business\'s customer', async () => {
    const owner = await createBusinessOwner('Real Store');
    const intruder = await createBusinessOwner('Thief Store');
    const customer = await addCustomer(owner);

    const res = await api('POST', '/transactions', {
      token: intruder.token,
      body: {
        customer_id: customer.id,
        items: [{ name: 'Ad-hoc item', unit_price_kobo: 100, quantity: 1 }],
      },
    });

    assert.equal(res.status, 404);
  });

  test('requires a business profile', async () => {
    const { session } = await createUser();
    const res = await api('GET', '/customers', { token: session.access_token });
    assert.equal(res.status, 404);
  });
});
