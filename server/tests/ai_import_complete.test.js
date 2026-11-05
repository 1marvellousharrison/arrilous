import test, { describe } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { api, createBusinessOwner } from './helpers.js';
import { queryOne, run } from '../src/db/index.js';
import { normalizeNigerianPhone } from '../src/routes/ai.js';

async function addProduct(owner, overrides = {}) {
  const res = await api('POST', '/products', {
    token: owner.token,
    body: {
      name: 'Adidas Sneakers',
      category: 'Shoes',
      price_kobo: 2500000,
      stock_quantity: 8,
      ...overrides,
    },
  });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.product;
}

async function addCustomer(owner, body) {
  const res = await api('POST', '/customers', { token: owner.token, body });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.customer;
}

/** Creates the draft row the upload route would have written. */
async function createImport(owner, overrides = {}) {
  const id = crypto.randomUUID();
  const timestamp = new Date().toISOString();
  await run(
    `INSERT INTO order_imports
       (id, business_id, user_id, source, status, extracted_customer_name,
        extracted_customer_phone, items_json, delivery_required, created_at, updated_at)
     VALUES (?, ?, ?, 'screenshot', 'review', ?, ?, ?, ?, ?, ?)`,
    id,
    owner.business.id,
    owner.userId,
    overrides.customerName ?? null,
    overrides.customerPhone ?? null,
    JSON.stringify(overrides.items ?? []),
    overrides.deliveryRequired ? 1 : 0,
    timestamp,
    timestamp
  );
  return id;
}

describe('screenshot import - creating the order', () => {
  test('creates a screenshot transaction with totals, statuses and a timeline', async () => {
    const owner = await createBusinessOwner('Import Store');
    const product = await addProduct(owner);
    const importId = await createImport(owner, {
      customerName: 'Mr Ben',
      customerPhone: '08037311300',
      items: [{ name: 'adidas', quantity: 2, product_id: product.id }],
    });

    const res = await api('POST', `/ai/imports/${importId}/complete`, {
      token: owner.token,
      body: {
        customer_name: 'Mr Ben',
        customer_phone: '08037311300',
        items: [{ name: 'adidas', quantity: 2, product_id: product.id }],
        delivery_required: false,
        discount_kobo: 200000,
      },
    });

    assert.equal(res.status, 200, JSON.stringify(res.body));

    const txn = await queryOne(
      'SELECT * FROM transactions WHERE id = ?',
      res.body.transactionId
    );
    assert.equal(txn.source, 'screenshot');
    assert.equal(txn.subtotal_kobo, 5000000);
    assert.equal(txn.discount_kobo, 200000);
    assert.equal(txn.total_kobo, 4800000);
    assert.equal(txn.delivery_required, 0);
    assert.equal(txn.delivery_status, 'not_required');
    assert.equal(txn.order_status, 'pending');
    assert.equal(txn.payment_status, 'unpaid');

    const items = await queryOne(
      'SELECT COUNT(*) AS total FROM transaction_items WHERE transaction_id = ?',
      txn.id
    );
    assert.equal(items.total, 1);

    const history = await queryOne(
      'SELECT COUNT(*) AS total FROM transaction_status_history WHERE transaction_id = ?',
      txn.id
    );
    assert.equal(history.total, 4);

    const imp = await queryOne('SELECT * FROM order_imports WHERE id = ?', importId);
    assert.equal(imp.status, 'completed');
    assert.equal(imp.transaction_id, txn.id);

    const imports = await api('GET', '/ai/imports', { token: owner.token });
    assert.equal(imports.status, 200, JSON.stringify(imports.body));
    const completedImport = imports.body.imports.find((entry) => entry.id === importId);
    assert.equal(completedImport.transactionId, txn.id);
    assert.equal(completedImport.transactionNumber, txn.transaction_number);

    const detail = await api('GET', `/ai/imports/${importId}`, { token: owner.token });
    assert.equal(detail.status, 200, JSON.stringify(detail.body));
    assert.equal(detail.body.import.transactionNumber, txn.transaction_number);
  });

  test('reuses a saved customer when the screenshot phone is formatted differently', async () => {
    const owner = await createBusinessOwner('Repeat Customer Store');
    const product = await addProduct(owner);
    const customer = await addCustomer(owner, {
      name: 'Ben Okafor',
      phone: '+2348037311300',
    });
    const importId = await createImport(owner, { customerPhone: '+2348037311300' });

    const res = await api('POST', `/ai/imports/${importId}/complete`, {
      token: owner.token,
      body: {
        customer_phone: '+2348037311300',
        items: [{ name: 'adidas', quantity: 1, product_id: product.id }],
        delivery_required: false,
      },
    });

    assert.equal(res.status, 200, JSON.stringify(res.body));
    // The name the screenshot did not show comes back from the saved record.
    assert.equal(res.body.customer.id, customer.id);
    assert.equal(res.body.customer.name, 'Ben Okafor');

    const txn = await queryOne(
      'SELECT customer_id FROM transactions WHERE id = ?',
      res.body.transactionId
    );
    assert.equal(txn.customer_id, customer.id);

    const count = await queryOne(
      'SELECT COUNT(*) AS total FROM customers WHERE business_id = ?',
      owner.business.id
    );
    assert.equal(count.total, 1, 'no duplicate customer was created');
  });

  test('reuses a saved customer by name when the phone is missing', async () => {
    const owner = await createBusinessOwner('Name Match Store');
    const product = await addProduct(owner);
    const customer = await addCustomer(owner, { name: 'Mr Ben', phone: '+2348030000000' });
    const importId = await createImport(owner, { customerName: 'ben' });

    const res = await api('POST', `/ai/imports/${importId}/complete`, {
      token: owner.token,
      body: {
        customer_name: 'ben',
        items: [{ name: 'adidas', quantity: 1, product_id: product.id }],
        delivery_required: false,
      },
    });

    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.customer.id, customer.id);
    assert.equal(res.body.customer.phone, '+2348030000000');
  });

  test('creates a customer from a name when none exists yet', async () => {
    const owner = await createBusinessOwner('New Customer Store');
    const product = await addProduct(owner);
    const importId = await createImport(owner, { customerName: 'Chinedu' });

    const res = await api('POST', `/ai/imports/${importId}/complete`, {
      token: owner.token,
      body: {
        customer_name: 'Chinedu',
        customer_phone: '08031234567',
        items: [{ name: 'adidas', quantity: 1, product_id: product.id }],
        delivery_required: false,
      },
    });

    assert.equal(res.status, 200, JSON.stringify(res.body));
    const saved = await queryOne('SELECT * FROM customers WHERE id = ?', res.body.customer.id);
    assert.equal(saved.name, 'Chinedu');
    assert.equal(saved.phone, '+2348031234567');
  });

  test('records delivery status and address for a delivery order', async () => {
    const owner = await createBusinessOwner('Delivery Store');
    const product = await addProduct(owner);
    const importId = await createImport(owner, { deliveryRequired: true });

    const res = await api('POST', `/ai/imports/${importId}/complete`, {
      token: owner.token,
      body: {
        customer_name: 'Mr Ben',
        items: [{ name: 'adidas', quantity: 1, product_id: product.id }],
        delivery_required: true,
        delivery_address: '12 Allen Avenue, Ikeja',
        delivery_fee_kobo: 150000,
      },
    });

    assert.equal(res.status, 200, JSON.stringify(res.body));
    const txn = await queryOne(
      'SELECT * FROM transactions WHERE id = ?',
      res.body.transactionId
    );
    assert.equal(txn.delivery_required, 1);
    assert.equal(txn.delivery_status, 'pending');
    assert.equal(txn.delivery_address, '12 Allen Avenue, Ikeja');
    assert.equal(txn.delivery_fee_kobo, 150000);
    assert.equal(txn.total_kobo, 2650000);
  });

  test('asks for an address instead of failing when delivery has none', async () => {
    const owner = await createBusinessOwner('No Address Store');
    const product = await addProduct(owner);
    const importId = await createImport(owner, { deliveryRequired: true });

    const res = await api('POST', `/ai/imports/${importId}/complete`, {
      token: owner.token,
      body: {
        customer_name: 'Mr Ben',
        items: [{ name: 'adidas', quantity: 1, product_id: product.id }],
        delivery_required: true,
        delivery_fee_kobo: 0,
      },
    });

    assert.equal(res.status, 400, JSON.stringify(res.body));
    assert.equal(res.body.error.details[0].field, 'delivery_address');
  });

  test('refuses to complete the same import twice', async () => {
    const owner = await createBusinessOwner('Once Store');
    const product = await addProduct(owner);
    const importId = await createImport(owner, { customerName: 'Mr Ben' });
    const body = {
      customer_name: 'Mr Ben',
      items: [{ name: 'adidas', quantity: 1, product_id: product.id }],
      delivery_required: false,
    };

    const first = await api('POST', `/ai/imports/${importId}/complete`, {
      token: owner.token,
      body,
    });
    assert.equal(first.status, 200, JSON.stringify(first.body));

    const second = await api('POST', `/ai/imports/${importId}/complete`, {
      token: owner.token,
      body,
    });
    assert.equal(second.status, 400, JSON.stringify(second.body));
  });

  test('returns the saved customer for the review screen lookup', async () => {
    const owner = await createBusinessOwner('Lookup Store');
    const customer = await addCustomer(owner, { name: 'Mr Ben', phone: '+2348037311300' });

    const res = await api('GET', '/ai/customers/match?name=ben&phone=%2B2348037311300', {
      token: owner.token,
    });

    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.customer.id, customer.id);
    assert.equal(res.body.matchedBy, 'phone');
  });

  test('queues the upload and exposes a pollable draft', async () => {
    const owner = await createBusinessOwner('Queue Store');
    const image = 'data:image/png;base64,iVBORw0KGgo=';

    const res = await api('POST', '/ai/import', {
      token: owner.token,
      body: { imageDataUrl: image, source: 'screenshot' },
    });
    assert.equal(res.status, 202, JSON.stringify(res.body));
    assert.equal(res.body.import.status, 'processing');
    const id = res.body.import.id;

    // No Gemini key exists in tests, so the background read settles quickly
    // with a review draft instead of holding the upload request open.
    let detail;
    for (let i = 0; i < 50; i += 1) {
      detail = await api('GET', `/ai/imports/${id}`, { token: owner.token });
      if (detail.body.import.status !== 'processing') break;
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    assert.notEqual(detail.body.import.status, 'processing');

    const chat = await api('GET', '/ai/chat', { token: owner.token });
    assert.ok(
      chat.body.messages.some(
        (message) => message.orderImportId === id && message.messageType === 'order_draft'
      ),
      'the finished draft is in the chat'
    );

    // Re-uploading the same image returns the existing draft, not a duplicate.
    const again = await api('POST', '/ai/import', {
      token: owner.token,
      body: { imageDataUrl: image, source: 'screenshot' },
    });
    assert.equal(again.status, 200, JSON.stringify(again.body));
    assert.equal(again.body.import.id, id);
    assert.equal(again.body.deduplicated, true);
  });

  test('normalizes Nigerian phone formats and rejects unusable numbers', () => {
    assert.equal(normalizeNigerianPhone('0803 731 1300'), '+2348037311300');
    assert.equal(normalizeNigerianPhone('+2348037311300'), '+2348037311300');
    assert.equal(normalizeNigerianPhone('2348037311300'), '+2348037311300');
    assert.equal(normalizeNigerianPhone('8037311300'), '+2348037311300');
    assert.equal(normalizeNigerianPhone('08037311300 / 08021234567'), '+2348037311300');
    assert.equal(normalizeNigerianPhone('12345'), null);
    assert.equal(normalizeNigerianPhone(''), null);
  });

  test('refuses an unusable phone instead of saving it', async () => {
    const owner = await createBusinessOwner('Bad Phone Store');
    const product = await addProduct(owner);
    const importId = await createImport(owner, { customerName: 'Mr Ben' });

    const res = await api('POST', `/ai/imports/${importId}/complete`, {
      token: owner.token,
      body: {
        customer_name: 'Mr Ben',
        customer_phone: '12345',
        items: [{ name: 'adidas', quantity: 1, product_id: product.id }],
        delivery_required: false,
      },
    });

    assert.equal(res.status, 400, JSON.stringify(res.body));
    assert.equal(res.body.error.details[0].field, 'customer_phone');
    const count = await queryOne(
      'SELECT COUNT(*) AS total FROM customers WHERE business_id = ?',
      owner.business.id
    );
    assert.equal(count.total, 0);
  });

  test('deletes a draft that has not become a sale', async () => {
    const owner = await createBusinessOwner('Draft Delete Store');
    const importId = await createImport(owner, { customerName: 'Mr Ben' });

    const res = await api('DELETE', `/ai/imports/${importId}`, { token: owner.token });

    assert.equal(res.status, 204, JSON.stringify(res.body));
    const row = await queryOne('SELECT id FROM order_imports WHERE id = ?', importId);
    assert.equal(row, undefined);
  });

  test('refuses to delete a draft that became a sale', async () => {
    const owner = await createBusinessOwner('Sold Draft Store');
    const product = await addProduct(owner);
    const importId = await createImport(owner, { customerName: 'Mr Ben' });

    const completed = await api('POST', `/ai/imports/${importId}/complete`, {
      token: owner.token,
      body: {
        customer_name: 'Mr Ben',
        items: [{ name: 'adidas', quantity: 1, product_id: product.id }],
        delivery_required: false,
      },
    });
    assert.equal(completed.status, 200, JSON.stringify(completed.body));

    const res = await api('DELETE', `/ai/imports/${importId}`, { token: owner.token });
    assert.equal(res.status, 400, JSON.stringify(res.body));
    const txn = await queryOne(
      'SELECT id FROM transactions WHERE id = ?',
      completed.body.transactionId
    );
    assert.ok(txn, 'the recorded sale is still there');
  });
});
