import test, { describe } from 'node:test';
import assert from 'node:assert/strict';
import { api, createBusinessOwner, uniqueEmail, uniquePhone } from './helpers.js';

/**
 * Phase 8 — the append-only status timeline.
 *
 * The point of these tests is that history cannot quietly fall out of step with
 * the status columns: every accepted change appends exactly one entry per axis
 * that actually moved, a rejected change appends nothing, and the entries
 * belong to the transaction's own business.
 */

async function ownerWithProduct(name = 'History Store') {
  const owner = await createBusinessOwner(name);
  const product = await api('POST', '/products', {
    token: owner.token,
    body: { name: 'Black Shirt', price_kobo: 1_500_000 },
  });
  assert.equal(product.status, 201, JSON.stringify(product.body));
  return { ...owner, product: product.body.product };
}

async function newTransaction(owner, product, overrides = {}) {
  const res = await api('POST', '/transactions', {
    token: owner.token,
    body: {
      items: [{ product_id: product.id, quantity: 2 }],
      ...overrides,
    },
  });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.transaction;
}

function entriesFor(history, statusType) {
  return history.filter((entry) => entry.statusType === statusType);
}

describe('phase 8 — transaction status history', () => {
  test('creating a transaction records how it was born', async () => {
    const owner = await ownerWithProduct('Birth Store');
    const txn = await newTransaction(owner, owner.product);

    const detail = await api('GET', `/transactions/${txn.id}`, { token: owner.token });
    assert.equal(detail.status, 200);

    const history = detail.body.history;
    assert.ok(Array.isArray(history), 'detail must expose a history array');
    assert.equal(history.length, 4, 'one entry per axis at creation');

    // Creation entries have no previous value — there was no prior state.
    for (const entry of history) {
      assert.equal(entry.oldValue, null);
      assert.equal(entry.transactionId, txn.id);
      assert.equal(entry.changedByUserId, owner.userId, 'the creator is recorded');
    }

    assert.equal(entriesFor(history, 'order')[0].newValue, 'pending');
    assert.equal(entriesFor(history, 'payment')[0].newValue, 'unpaid');
    assert.equal(entriesFor(history, 'completion')[0].newValue, 'open');
  });

  test('a delivery order starts at pending, a walk-in starts at not_required', async () => {
    const owner = await ownerWithProduct('Delivery Store');

    const walkIn = await newTransaction(owner, owner.product);
    const delivered = await newTransaction(owner, owner.product, {
      delivery_required: true,
      delivery_address: '10 Adeola Odeku St',
    });

    const walkInDetail = await api('GET', `/transactions/${walkIn.id}`, { token: owner.token });
    const deliveryDetail = await api('GET', `/transactions/${delivered.id}`, {
      token: owner.token,
    });

    assert.equal(
      entriesFor(walkInDetail.body.history, 'delivery')[0].newValue,
      'not_required'
    );
    assert.equal(
      entriesFor(deliveryDetail.body.history, 'delivery')[0].newValue,
      'pending'
    );
  });

  test('each status change appends an entry with the old and new value', async () => {
    const owner = await ownerWithProduct('Timeline Store');
    const txn = await newTransaction(owner, owner.product);

    const updated = await api('PATCH', `/transactions/${txn.id}/statuses`, {
      token: owner.token,
      body: { orderStatus: 'confirmed' },
    });
    assert.equal(updated.status, 200, JSON.stringify(updated.body));

    const detail = await api('GET', `/transactions/${txn.id}`, { token: owner.token });
    const order = entriesFor(detail.body.history, 'order');

    assert.equal(order.length, 2, 'the creation entry plus the confirmation');
    assert.equal(order[0].newValue, 'pending');
    assert.equal(order[1].oldValue, 'pending');
    assert.equal(order[1].newValue, 'confirmed');
    assert.equal(order[1].changedByUserId, owner.userId);
  });

  test('a change across several axes records one entry per axis', async () => {
    const owner = await ownerWithProduct('Multi Store');
    const txn = await newTransaction(owner, owner.product);

    const res = await api('PATCH', `/transactions/${txn.id}/statuses`, {
      token: owner.token,
      body: {
        orderStatus: 'confirmed',
        paymentStatus: 'paid',
        completionStatus: 'completed',
      },
    });
    assert.equal(res.status, 200, JSON.stringify(res.body));

    const detail = await api('GET', `/transactions/${txn.id}`, { token: owner.token });
    assert.equal(entriesFor(detail.body.history, 'order').length, 2);
    assert.equal(entriesFor(detail.body.history, 'payment').length, 2);
    assert.equal(entriesFor(detail.body.history, 'completion').length, 2);
    // Delivery was not part of the change and this sale needed no delivery.
    assert.equal(entriesFor(detail.body.history, 'delivery').length, 1);
  });

  test('re-sending a status a transaction already has records nothing', async () => {
    const owner = await ownerWithProduct('Noop Store');
    const txn = await newTransaction(owner, owner.product);

    const before = await api('GET', `/transactions/${txn.id}`, { token: owner.token });
    const countBefore = before.body.history.length;

    // The API treats a no-op as a success, which is right — it is not an error.
    const res = await api('PATCH', `/transactions/${txn.id}/statuses`, {
      token: owner.token,
      body: { orderStatus: 'pending' },
    });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.changed, [], 'nothing moved, so nothing to record');

    const after = await api('GET', `/transactions/${txn.id}`, { token: owner.token });
    assert.equal(
      after.body.history.length,
      countBefore,
      'a no-op must not pad the timeline'
    );
  });

  test('a rejected transition records nothing at all', async () => {
    const owner = await ownerWithProduct('Reject Store');
    const txn = await newTransaction(owner, owner.product);

    await api('PATCH', `/transactions/${txn.id}/statuses`, {
      token: owner.token,
      body: { orderStatus: 'confirmed' },
    });
    const before = await api('GET', `/transactions/${txn.id}`, { token: owner.token });

    // confirmed cannot go back to pending.
    const bad = await api('PATCH', `/transactions/${txn.id}/statuses`, {
      token: owner.token,
      body: { orderStatus: 'pending', paymentStatus: 'refunded' },
    });
    assert.equal(bad.status, 400);

    const after = await api('GET', `/transactions/${txn.id}`, { token: owner.token });
    assert.deepEqual(
      after.body.history,
      before.body.history,
      'a refused change must leave the timeline untouched'
    );
  });

  test('a rule violation across axes records nothing', async () => {
    const owner = await ownerWithProduct('Rules Store');
    const txn = await newTransaction(owner, owner.product);

    const before = await api('GET', `/transactions/${txn.id}`, { token: owner.token });
    const countBefore = before.body.history.length;

    // Completing requires payment to be paid; the combination check refuses it.
    const bad = await api('PATCH', `/transactions/${txn.id}/statuses`, {
      token: owner.token,
      body: { orderStatus: 'confirmed', completionStatus: 'completed' },
    });
    assert.equal(bad.status, 400);

    const after = await api('GET', `/transactions/${txn.id}`, { token: owner.token });
    assert.equal(after.body.history.length, countBefore);
    assert.equal(after.body.transaction.orderStatus, 'pending', 'and nothing was applied');
  });

  test('a note is kept on the entries a change writes', async () => {
    const owner = await ownerWithProduct('Note Store');
    const txn = await newTransaction(owner, owner.product);

    await api('PATCH', `/transactions/${txn.id}/statuses`, {
      token: owner.token,
      body: {
        paymentStatus: 'paid',
        note: 'Cash received at the counter',
      },
    });

    const detail = await api('GET', `/transactions/${txn.id}`, { token: owner.token });
    const payment = entriesFor(detail.body.history, 'payment');
    assert.equal(payment[1].note, 'Cash received at the counter');
  });

  test('a note on its own is not a status change', async () => {
    const owner = await ownerWithProduct('NoteOnly Store');
    const txn = await newTransaction(owner, owner.product);

    const res = await api('PATCH', `/transactions/${txn.id}/statuses`, {
      token: owner.token,
      body: { note: 'just thinking out loud' },
    });
    assert.equal(res.status, 422, 'a note alone is a malformed request, not a change');
    assert.equal(res.body.error.code, 'validation_failed');
  });

  test('history is ordered oldest first', async () => {
    const owner = await ownerWithProduct('Order Store');
    const txn = await newTransaction(owner, owner.product);

    await api('PATCH', `/transactions/${txn.id}/statuses`, {
      token: owner.token,
      body: { orderStatus: 'confirmed' },
    });
    await api('PATCH', `/transactions/${txn.id}/statuses`, {
      token: owner.token,
      body: { paymentStatus: 'paid' },
    });

    const detail = await api('GET', `/transactions/${txn.id}`, { token: owner.token });
    const times = detail.body.history.map((entry) => entry.createdAt);
    const sorted = [...times].sort();
    assert.deepEqual(times, sorted, 'the timeline reads top to bottom');
    assert.equal(detail.body.history.at(-1).statusType, 'payment');
  });

  test('one business cannot read another business\'s history', async () => {
    const owner = await ownerWithProduct('Isolated Store');
    const txn = await newTransaction(owner, owner.product);

    const signup = await api('POST', '/auth/signup', {
      body: {
        full_name: 'Nosy Owner',
        email: uniqueEmail('nosy'),
        phone: uniquePhone(),
        password: 'Str0ngPass!23',
        role: 'business',
      },
    });
    assert.equal(signup.status, 201, JSON.stringify(signup.body));
    const token = signup.body.access_token;

    await api('POST', '/business', {
      token,
      body: {
        business_name: 'Nosy Store',
        business_category: 'Testing',
        business_description: 'A shop that must stay out of the other owner\'s history.',
        phone: uniquePhone(),
      },
    });

    const res = await api('GET', `/transactions/${txn.id}`, { token });
    assert.equal(res.status, 404, 'the transaction is not theirs, so it does not exist');
    assert.equal(res.body.history, undefined, 'and no history leaks with it');
  });

  test('history survives a later catalog price change', async () => {
    const owner = await ownerWithProduct('Snapshot Store');
    const txn = await newTransaction(owner, owner.product);

    await api('PATCH', `/products/${owner.product.id}`, {
      token: owner.token,
      body: { price_kobo: 9_999_999 },
    });

    const detail = await api('GET', `/transactions/${txn.id}`, { token: owner.token });
    const payment = entriesFor(detail.body.history, 'payment')[0];
    assert.equal(payment.newValue, 'unpaid');
    assert.equal(detail.body.transaction.totalKobo, 3_000_000, 'the sale total is unchanged');
  });
});