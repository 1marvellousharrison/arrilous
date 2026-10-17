import test, { describe } from 'node:test';
import assert from 'node:assert/strict';
import { api, createBusinessOwner, createUser } from './helpers.js';

async function seedStore(owner) {
  const product = (
    await api('POST', '/products', {
      token: owner.token,
      body: { name: 'Rice 50kg', price_kobo: 2500050, stock_quantity: 10 },
    })
  ).body.product;

  const customer = (
    await api('POST', '/customers', {
      token: owner.token,
      body: { name: 'Ada Nwosu' },
    })
  ).body.customer;

  return { product, customer };
}

async function createTransaction(owner, body) {
  const res = await api('POST', '/transactions', { token: owner.token, body });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.transaction;
}

describe('phase 5 — transaction core', () => {
  test('records a sale and numbers it', async () => {
    const owner = await createBusinessOwner('Sales Store');
    const { product, customer } = await seedStore(owner);

    const created = await createTransaction(owner, {
      customer_id: customer.id,
      items: [{ product_id: product.id, quantity: 2 }],
    });

    assert.match(created.transactionNumber, /^TXN-\d{4}-\d{5}$/);
    assert.equal(created.source, 'manual');
    assert.equal(created.customerId, customer.id);
    assert.equal(created.orderStatus, 'pending');
    assert.equal(created.paymentStatus, 'unpaid');
    assert.equal(created.completionStatus, 'open');
    assert.equal(created.deliveryRequired, false);
    assert.equal(created.deliveryStatus, 'not_required');
    assert.equal(created.items.length, 1);
    assert.equal(created.items[0].name, 'Rice 50kg');
  });

  test('numbers each transaction uniquely inside a business', async () => {
    const owner = await createBusinessOwner('Numbering Store');
    const { product } = await seedStore(owner);

    const first = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
    });
    const second = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
    });

    assert.notEqual(first.transactionNumber, second.transactionNumber);
  });

  test('starts delivery as pending when the order needs delivering', async () => {
    const owner = await createBusinessOwner('Delivery Store');
    const { product } = await seedStore(owner);

    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
      delivery_required: true,
      delivery_address: '4 Bode Thomas, Surulere',
    });

    assert.equal(created.deliveryRequired, true);
    assert.equal(created.deliveryStatus, 'pending');
  });

  test('requires a delivery address when delivery is needed', async () => {
    const owner = await createBusinessOwner('Address Store');
    const { product } = await seedStore(owner);

    const res = await api('POST', '/transactions', {
      token: owner.token,
      body: { items: [{ product_id: product.id, quantity: 1 }], delivery_required: true },
    });

    assert.equal(res.status, 400);
    assert.ok(res.body.error.details.some((d) => d.field === 'delivery_address'));
  });

  test('requires at least one item', async () => {
    const owner = await createBusinessOwner('Empty Store');
    const res = await api('POST', '/transactions', { token: owner.token, body: { items: [] } });

    assert.equal(res.status, 422);
    assert.ok(res.body.error.details.some((d) => d.field === 'items'));
  });

  test('rejects a zero or fractional quantity', async () => {
    const owner = await createBusinessOwner('Quantity Store');
    const { product } = await seedStore(owner);

    const zero = await api('POST', '/transactions', {
      token: owner.token,
      body: { items: [{ product_id: product.id, quantity: 0 }] },
    });
    assert.equal(zero.status, 422);

    const fractional = await api('POST', '/transactions', {
      token: owner.token,
      body: { items: [{ product_id: product.id, quantity: 1.5 }] },
    });
    assert.equal(fractional.status, 422);
  });

  test('refuses to sell an archived product', async () => {
    const owner = await createBusinessOwner('Archived Store');
    const { product } = await seedStore(owner);
    await api('POST', `/products/${product.id}/archive`, { token: owner.token });

    const res = await api('POST', '/transactions', {
      token: owner.token,
      body: { items: [{ product_id: product.id, quantity: 1 }] },
    });

    assert.equal(res.status, 400);
  });

  test('cannot sell another business\'s product', async () => {
    const owner = await createBusinessOwner('Real Store');
    const intruder = await createBusinessOwner('Thief Store');
    const { product } = await seedStore(owner);

    const res = await api('POST', '/transactions', {
      token: intruder.token,
      body: { items: [{ product_id: product.id, quantity: 1 }] },
    });

    assert.equal(res.status, 404);
  });

  test('lists transactions newest first and filters by status', async () => {
    const owner = await createBusinessOwner('Listing Store');
    const { product } = await seedStore(owner);

    const first = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
    });
    await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
    });

    const all = await api('GET', '/transactions', { token: owner.token });
    assert.equal(all.body.transactions.length, 2);
    assert.equal(all.body.transactions[0].createdAt >= first.createdAt, true);

    const pending = await api('GET', '/transactions?order_status=pending', { token: owner.token });
    assert.equal(pending.body.transactions.length, 2);

    const confirmed = await api('GET', '/transactions?order_status=confirmed', { token: owner.token });
    assert.equal(confirmed.body.transactions.length, 0);
  });

  test('searches by transaction number', async () => {
    const owner = await createBusinessOwner('Search Store');
    const { product } = await seedStore(owner);
    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
    });

    const res = await api('GET', `/transactions?search=${created.transactionNumber}`, {
      token: owner.token,
    });
    assert.equal(res.body.transactions.length, 1);
  });
});

describe('phase 6 — items and server-side totals', () => {
  test('computes the subtotal from the catalog price', async () => {
    const owner = await createBusinessOwner('Totals Store');
    const { product } = await seedStore(owner);

    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 3 }],
    });

    assert.equal(created.subtotalKobo, 2500050 * 3);
    assert.equal(created.totalKobo, 2500050 * 3);
    assert.equal(created.items[0].subtotalKobo, 2500050 * 3);
  });

  test('ignores totals sent by the client', async () => {
    const owner = await createBusinessOwner('Honest Store');
    const { product } = await seedStore(owner);

    const res = await api('POST', '/transactions', {
      token: owner.token,
      body: {
        items: [{ product_id: product.id, quantity: 2 }],
        subtotal_kobo: 1,
        total_kobo: 1,
        subtotalKobo: 1,
        totalKobo: 1,
      },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.transaction.totalKobo, 2500050 * 2);
  });

  test('takes the price from the catalog, not from the payload', async () => {
    const owner = await createBusinessOwner('Price Attack Store');
    const { product } = await seedStore(owner);

    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1, unit_price_kobo: 100, name: 'Free Lunch' }],
    });

    assert.equal(created.items[0].unitPriceKobo, 2500050);
    assert.equal(created.items[0].name, 'Rice 50kg');
    assert.equal(created.totalKobo, 2500050);
  });

  test('snapshots the product picture onto the line it was sold as', async () => {
    const owner = await createBusinessOwner('Photo Sale Store');
    const png =
      'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP478oAAAOLAUV+7IS+AAAAAElFTkSuQmCC';
    const product = (
      await api('POST', '/products', {
        token: owner.token,
        body: { name: 'Rice 50kg', price_kobo: 2500050, stock_quantity: 10, image_url: png },
      })
    ).body.product;

    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
    });

    assert.equal(created.items[0].imageUrl, png);

    // The snapshot is stamped at sale time: editing the product later does not
    // reach back and rewrite what the receipt says was sold.
    await api('PATCH', `/products/${product.id}`, {
      token: owner.token,
      body: { image_url: null },
    });
    const fetched = await api('GET', `/transactions/${created.id}`, { token: owner.token });
    assert.equal(fetched.body.transaction.items[0].imageUrl, png);
  });

  test('an ad-hoc line carries no product image', async () => {
    const owner = await createBusinessOwner('Ad Hoc Photo Store');

    const created = await createTransaction(owner, {
      items: [{ name: 'Custom cake order', unit_price_kobo: 35000, quantity: 1 }],
    });

    assert.equal(created.items[0].imageUrl, null);
  });

  test('allows an ad-hoc line with its own name and price', async () => {
    const owner = await createBusinessOwner('Ad Hoc Store');

    const created = await createTransaction(owner, {
      items: [{ name: 'Custom cake order', unit_price_kobo: '35000', quantity: 2 }],
    });

    assert.equal(created.items[0].productId, null);
    assert.equal(created.items[0].name, 'Custom cake order');
    assert.equal(created.items[0].unitPriceKobo, 3500000);
    assert.equal(created.totalKobo, 7000000);
  });

  test('mixes catalog and ad-hoc lines in one transaction', async () => {
    const owner = await createBusinessOwner('Mixed Store');
    const { product } = await seedStore(owner);

    const created = await createTransaction(owner, {
      items: [
        { product_id: product.id, quantity: 2 },
        { name: 'Delivery tip jar', unit_price_kobo: 50000, quantity: 1 },
      ],
    });

    assert.equal(created.items.length, 2);
    assert.equal(created.subtotalKobo, 2500050 * 2 + 50000);
  });

  test('rejects an ad-hoc line with neither a product nor a name', async () => {
    const owner = await createBusinessOwner('Nameless Line');
    const res = await api('POST', '/transactions', {
      token: owner.token,
      body: { items: [{ unit_price_kobo: 100, quantity: 1 }] },
    });

    assert.equal(res.status, 400);
  });

  test('applies a discount and a delivery fee', async () => {
    const owner = await createBusinessOwner('Adjustment Store');
    const { product } = await seedStore(owner);

    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
      discount_kobo: 50000,
      delivery_fee_kobo: '1500',
    });

    assert.equal(created.discountKobo, 50000);
    assert.equal(created.deliveryFeeKobo, 150000);
    assert.equal(created.totalKobo, 2500050 - 50000 + 150000);
  });

  test('refuses a discount larger than the subtotal', async () => {
    const owner = await createBusinessOwner('Greedy Store');
    const { product } = await seedStore(owner);

    const res = await api('POST', '/transactions', {
      token: owner.token,
      body: { items: [{ product_id: product.id, quantity: 1 }], discount_kobo: 99999999 },
    });

    assert.equal(res.status, 400);
    assert.ok(res.body.error.details.some((d) => d.field === 'discount_kobo'));
  });

  test('accepts a discount that brings the total to exactly zero', async () => {
    const owner = await createBusinessOwner('Free Store');
    const { product } = await seedStore(owner);

    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
      discount_kobo: 2500050,
    });

    assert.equal(created.totalKobo, 0);
  });

  test('returns the stored items and customer when a transaction is opened', async () => {
    const owner = await createBusinessOwner('Detail Store');
    const { product, customer } = await seedStore(owner);
    const created = await createTransaction(owner, {
      customer_id: customer.id,
      items: [{ product_id: product.id, quantity: 2 }],
      notes: 'Deliver before 5pm',
    });

    const res = await api('GET', `/transactions/${created.id}`, { token: owner.token });
    assert.equal(res.status, 200);
    assert.equal(res.body.transaction.items.length, 1);
    assert.equal(res.body.transaction.notes, 'Deliver before 5pm');
    assert.equal(res.body.customer.name, 'Ada Nwosu');
  });

  test('keeps the item price snapshot after the catalog price changes', async () => {
    const owner = await createBusinessOwner('Snapshot Store');
    const { product } = await seedStore(owner);
    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
    });

    await api('PATCH', `/products/${product.id}`, {
      token: owner.token,
      body: { price_kobo: 999900 },
    });

    const res = await api('GET', `/transactions/${created.id}`, { token: owner.token });
    assert.equal(res.body.transaction.items[0].unitPriceKobo, 2500050);
    assert.equal(res.body.transaction.totalKobo, 2500050);
  });

  test('one business cannot read another business\'s transaction', async () => {
    const owner = await createBusinessOwner('Real Store');
    const intruder = await createBusinessOwner('Thief Store');
    const { product } = await seedStore(owner);
    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
    });

    const list = await api('GET', '/transactions', { token: intruder.token });
    assert.equal(list.body.transactions.length, 0);

    const read = await api('GET', `/transactions/${created.id}`, { token: intruder.token });
    assert.equal(read.status, 404);
  });
});

describe('phase 7 — independent status axes', () => {
  test('a fresh transaction reports four separate statuses', async () => {
    const owner = await createBusinessOwner('Status Store');
    const { product } = await seedStore(owner);
    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
    });

    assert.deepEqual(
      {
        orderStatus: created.orderStatus,
        paymentStatus: created.paymentStatus,
        deliveryStatus: created.deliveryStatus,
        completionStatus: created.completionStatus,
      },
      {
        orderStatus: 'pending',
        paymentStatus: 'unpaid',
        deliveryStatus: 'not_required',
        completionStatus: 'open',
      }
    );
  });

  test('confirms an order without touching payment', async () => {
    const owner = await createBusinessOwner('Confirm Store');
    const { product } = await seedStore(owner);
    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
    });

    const res = await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { orderStatus: 'confirmed' },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.transaction.orderStatus, 'confirmed');
    assert.equal(res.body.transaction.paymentStatus, 'unpaid');
    assert.equal(res.body.transaction.completionStatus, 'open');
  });

  test('walks a delivery through its steps', async () => {
    const owner = await createBusinessOwner('Walk Store');
    const { product } = await seedStore(owner);
    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
      delivery_required: true,
      delivery_address: '4 Bode Thomas, Surulere',
    });

    for (const deliveryStatus of ['accepted', 'picked_up', 'in_transit', 'delivered']) {
      const res = await api('PATCH', `/transactions/${created.id}/statuses`, {
        token: owner.token,
        body: { deliveryStatus },
      });
      assert.equal(res.status, 200, `step ${deliveryStatus}: ${JSON.stringify(res.body)}`);
      assert.equal(res.body.transaction.deliveryStatus, deliveryStatus);
    }
  });

  test('rejects a status the vocabulary does not contain', async () => {
    const owner = await createBusinessOwner('Vocabulary Store');
    const { product } = await seedStore(owner);
    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
    });

    const res = await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { orderStatus: 'shipped' },
    });

    assert.equal(res.status, 422);
  });

  test('rejects a backwards transition', async () => {
    const owner = await createBusinessOwner('Backwards Store');
    const { product } = await seedStore(owner);
    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
    });

    await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { orderStatus: 'confirmed' },
    });
    const res = await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { orderStatus: 'pending' },
    });

    assert.equal(res.status, 400);
  });

  test('refuses to complete a transaction that has not been paid', async () => {
    const owner = await createBusinessOwner('Unpaid Store');
    const { product } = await seedStore(owner);
    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
    });

    const res = await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { completionStatus: 'completed' },
    });

    assert.equal(res.status, 400);
    assert.ok(res.body.error.details.some((d) => d.field === 'completionStatus'));
  });

  test('refuses to complete a delivered order that is still in transit', async () => {
    const owner = await createBusinessOwner('In Transit Store');
    const { product } = await seedStore(owner);
    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
      delivery_required: true,
      delivery_address: '4 Bode Thomas, Surulere',
    });

    await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { paymentStatus: 'paid', deliveryStatus: 'in_transit' },
    });
    const res = await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { completionStatus: 'completed' },
    });

    assert.equal(res.status, 400);
  });

  test('completes a paid, delivered transaction in one call', async () => {
    const owner = await createBusinessOwner('Complete Store');
    const { product } = await seedStore(owner);
    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
      delivery_required: true,
      delivery_address: '4 Bode Thomas, Surulere',
    });

    await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { orderStatus: 'confirmed', paymentStatus: 'paid', deliveryStatus: 'accepted' },
    });
    await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { deliveryStatus: 'picked_up' },
    });
    await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { deliveryStatus: 'in_transit' },
    });

    const delivered = await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { deliveryStatus: 'delivered', completionStatus: 'completed' },
    });

    assert.equal(delivered.status, 200, JSON.stringify(delivered.body));
    assert.equal(delivered.body.transaction.deliveryStatus, 'delivered');
    assert.equal(delivered.body.transaction.completionStatus, 'completed');
    assert.equal(delivered.body.transaction.paymentStatus, 'paid');
    assert.equal(delivered.body.transaction.orderStatus, 'confirmed');
  });

  test('completes a paid walk-in sale with no delivery', async () => {
    const owner = await createBusinessOwner('Walk In Store');
    const { product } = await seedStore(owner);
    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
    });

    const res = await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { paymentStatus: 'paid', completionStatus: 'completed' },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.transaction.completionStatus, 'completed');
  });

  test('refuses to move delivery on a transaction that needs no delivery', async () => {
    const owner = await createBusinessOwner('No Delivery Store');
    const { product } = await seedStore(owner);
    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
    });

    const res = await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { deliveryStatus: 'in_transit' },
    });

    assert.equal(res.status, 400);
  });

  test('a cancelled transaction is final and frozen', async () => {
    const owner = await createBusinessOwner('Cancel Store');
    const { product } = await seedStore(owner);
    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
    });

    const cancelled = await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { orderStatus: 'cancelled' },
    });
    assert.equal(cancelled.status, 200);
    assert.equal(cancelled.body.transaction.orderStatus, 'cancelled');

    const revive = await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { orderStatus: 'confirmed' },
    });
    assert.equal(revive.status, 400);
    // The message is shown to an owner, so it should read as English rather
    // than "A order ...".
    assert.match(revive.body.error.message, /^An order /);

    const keepCharging = await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { paymentStatus: 'paid' },
    });
    assert.equal(keepCharging.status, 400);
  });

  test('a cancelled transaction can still be refunded', async () => {
    const owner = await createBusinessOwner('Refund Store');
    const { product } = await seedStore(owner);
    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
    });

    await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { paymentStatus: 'paid' },
    });
    await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { orderStatus: 'cancelled' },
    });

    // Cancelling money that was already taken is still allowed: that is a refund.
    const res = await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { paymentStatus: 'refunded' },
    });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.transaction.paymentStatus, 'refunded');
    assert.equal(res.body.transaction.orderStatus, 'cancelled');
  });

  test('a cancelled transaction can never be completed', async () => {
    const owner = await createBusinessOwner('Zombie Store');
    const { product } = await seedStore(owner);
    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
    });

    await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { paymentStatus: 'paid' },
    });
    await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: { orderStatus: 'cancelled', completionStatus: 'completed' },
    });

    const res = await api('GET', `/transactions/${created.id}`, { token: owner.token });
    assert.equal(res.body.transaction.completionStatus, 'open');
  });

  test('requires at least one status in the payload', async () => {
    const owner = await createBusinessOwner('Empty Patch Store');
    const { product } = await seedStore(owner);
    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
    });

    const res = await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: owner.token,
      body: {},
    });

    assert.equal(res.status, 422);
  });

  test('one business cannot change another business\'s transaction statuses', async () => {
    const owner = await createBusinessOwner('Real Store');
    const intruder = await createBusinessOwner('Thief Store');
    const { product } = await seedStore(owner);
    const created = await createTransaction(owner, {
      items: [{ product_id: product.id, quantity: 1 }],
    });

    const res = await api('PATCH', `/transactions/${created.id}/statuses`, {
      token: intruder.token,
      body: { orderStatus: 'cancelled' },
    });

    assert.equal(res.status, 404);

    const check = await api('GET', `/transactions/${created.id}`, { token: owner.token });
    assert.equal(check.body.transaction.orderStatus, 'pending');
  });

  test('requires a business profile', async () => {
    const { session } = await createUser();
    const res = await api('GET', '/transactions', { token: session.access_token });
    assert.equal(res.status, 404);
  });
});
