import test, { describe } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

import { api, createBusinessOwner } from './helpers.js';
import { queryOne, run } from '../src/db/index.js';

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

async function staffSession(owner, fullName = 'Amina Staff') {
  const created = await api('POST', '/staff', {
    token: owner.token,
    body: { full_name: fullName },
  });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  const staff = created.body.staff;
  await api('POST', '/staff/claim', { body: { staff_code: staff.staffCode } });
  const activated = await api('POST', '/staff/activate', {
    body: { staff_code: staff.staffCode, password: STAFF_PASSWORD },
  });
  assert.equal(activated.status, 200, JSON.stringify(activated.body));
  const login = await api('POST', '/auth/login', {
    body: { identifier: staff.staffCode, password: STAFF_PASSWORD },
  });
  assert.equal(login.status, 200, JSON.stringify(login.body));
  return {
    staff,
    token: login.body.access_token,
    userId: login.body.user.id,
  };
}

function saleBody(totalKobo = 150000) {
  return {
    items: [{ name: 'Walk-in item', unit_price_kobo: totalKobo, quantity: 1 }],
  };
}

async function inbox(token) {
  const res = await api('GET', '/notifications', { token });
  assert.equal(res.status, 200, JSON.stringify(res.body));
  return res.body;
}

async function insertNotification({
  businessId,
  userId,
  actorUserId = null,
  title = 'Personal alert',
}) {
  const id = crypto.randomUUID();
  await run(
    `INSERT INTO notifications
       (id, business_id, user_id, actor_user_id, type, title, message, severity, created_at)
     VALUES (?, ?, ?, ?, 'test_alert', ?, 'Body', 'info', ?)`,
    id,
    businessId,
    userId,
    actorUserId,
    title,
    new Date().toISOString()
  );
  return id;
}

describe('business event notifications', () => {
  test('an owner sale lands in the inbox and points at the transaction', async () => {
    const owner = await createBusinessOwner('Event Store');
    const sale = await api('POST', '/transactions', {
      token: owner.token,
      body: saleBody(150000),
    });
    assert.equal(sale.status, 201, JSON.stringify(sale.body));

    const body = await inbox(owner.token);
    const event = body.notifications.find(
      (n) => n.type === 'sale_recorded'
    );
    assert.ok(event, 'a sale raises a notification');
    assert.equal(event.transactionId, sale.body.transaction.id);
    assert.equal(event.actorUserId, owner.userId);
    assert.equal(event.actorName, 'Test Owner');
    assert.match(event.message, /₦1,500/);
    assert.equal(event.readAt, null);
  });

  test('a staff sale reaches the owner, names the staff, and is visible to them', async () => {
    const owner = await createBusinessOwner('Team Sales Store');
    const staff = await staffSession(owner);

    const sale = await api('POST', '/transactions', {
      token: staff.token,
      body: saleBody(250000),
    });
    assert.equal(sale.status, 201, JSON.stringify(sale.body));

    const ownerInbox = await inbox(owner.token);
    const event = ownerInbox.notifications.find(
      (n) => n.type === 'sale_recorded'
    );
    assert.ok(event);
    assert.equal(event.transactionId, sale.body.transaction.id);
    assert.equal(event.actorUserId, staff.userId);
    assert.equal(event.actorName, 'Amina Staff');
    assert.match(event.message, /Amina Staff recorded sale/);

    const staffInbox = await inbox(staff.token);
    assert.ok(
      staffInbox.notifications.some((n) => n.id === event.id),
      'the staff sees the business-wide sale they caused'
    );

    const activity = await api('GET', `/staff/${staff.staff.id}/notifications`, {
      token: owner.token,
    });
    assert.equal(activity.status, 200, JSON.stringify(activity.body));
    assert.deepEqual(
      activity.body.notifications.map((n) => n.id),
      [event.id]
    );

    const refused = await api('GET', `/staff/${staff.staff.id}/notifications`, {
      token: staff.token,
    });
    assert.equal(refused.status, 403, JSON.stringify(refused.body));
  });

  test('a payment update raises a status notification', async () => {
    const owner = await createBusinessOwner('Payment Watch Store');
    const sale = await api('POST', '/transactions', {
      token: owner.token,
      body: saleBody(100000),
    });
    assert.equal(sale.status, 201, JSON.stringify(sale.body));

    const updated = await api(
      'PATCH',
      `/transactions/${sale.body.transaction.id}/statuses`,
      { token: owner.token, body: { paymentStatus: 'paid' } }
    );
    assert.equal(updated.status, 200, JSON.stringify(updated.body));

    const body = await inbox(owner.token);
    const event = body.notifications.find((n) => n.type === 'sale_status');
    assert.ok(event);
    assert.equal(event.transactionId, sale.body.transaction.id);
    assert.match(event.title, /Payment received/);
    assert.match(event.message, /Payment unpaid → paid/);
    assert.equal(event.severity, 'success');
  });

  test('a restock raises a stock notification for that product', async () => {
    const owner = await createBusinessOwner('Restock Events Store');
    const product = await addProduct(owner, { name: 'Garri', stock_quantity: 2 });

    const restocked = await api('POST', `/products/${product.id}/restock`, {
      token: owner.token,
      body: { quantity: 10 },
    });
    assert.equal(restocked.status, 200, JSON.stringify(restocked.body));

    const body = await inbox(owner.token);
    const event = body.notifications.find((n) => n.type === 'restock');
    assert.ok(event);
    assert.equal(event.productId, product.id);
    assert.equal(event.actorUserId, owner.userId);
    assert.match(event.title, /Restocked Garri/);
    assert.match(event.message, /10 units added/);
    assert.match(event.message, /12 now in stock/);
  });

  test('audience scoping keeps personal alerts out of other staff inboxes', async () => {
    const owner = await createBusinessOwner('Private Inbox Store');
    const first = await staffSession(owner, 'First Staff');
    const second = await staffSession(owner, 'Second Staff');

    const personal = await insertNotification({
      businessId: owner.business.id,
      userId: owner.userId,
      title: 'Owner only',
    });
    const forFirst = await insertNotification({
      businessId: owner.business.id,
      userId: first.userId,
      title: 'First only',
    });

    const firstInbox = await inbox(first.token);
    assert.ok(firstInbox.notifications.some((n) => n.id === forFirst));
    assert.ok(
      !firstInbox.notifications.some((n) => n.id === personal),
      'another user\'s message is not in this staff inbox'
    );

    const secondInbox = await inbox(second.token);
    assert.ok(!secondInbox.notifications.some((n) => n.id === forFirst));

    const ownerInbox = await inbox(owner.token);
    assert.ok(ownerInbox.notifications.some((n) => n.id === personal));
    assert.ok(ownerInbox.notifications.some((n) => n.id === forFirst));
  });

  test('a staff clearing their inbox cannot clear another person\'s message', async () => {
    const owner = await createBusinessOwner('Read Scope Store');
    const staff = await staffSession(owner);
    const personal = await insertNotification({
      businessId: owner.business.id,
      userId: owner.userId,
      title: 'Keep me',
    });

    const cleared = await api('POST', '/notifications/read-all', {
      token: staff.token,
      body: { include_important: true },
    });
    assert.equal(cleared.status, 200, JSON.stringify(cleared.body));

    const row = await queryOne(
      'SELECT read_at FROM notifications WHERE id = ?',
      personal
    );
    assert.equal(row.read_at, null);
  });
});

describe('staff AI isolation', () => {
  async function insertImport({ businessId, userId, customerName }) {
    const id = crypto.randomUUID();
    const at = new Date().toISOString();
    await run(
      `INSERT INTO order_imports
         (id, business_id, user_id, source, status, extracted_customer_name,
          items_json, created_at, updated_at)
       VALUES (?, ?, ?, 'screenshot', 'review', ?, '[]', ?, ?)`,
      id,
      businessId,
      userId,
      customerName,
      at,
      at
    );
    await run(
      `INSERT INTO ai_chat_messages
         (id, business_id, user_id, order_import_id, role, message_type, content, created_at)
       VALUES (?, ?, ?, ?, 'assistant', 'order_draft', ?, ?)`,
      crypto.randomUUID(),
      businessId,
      userId,
      id,
      `Draft for ${customerName}`,
      at
    );
    return id;
  }

  test('a staff member only sees their own chat and drafts', async () => {
    const owner = await createBusinessOwner('AI Privacy Store');
    const staff = await staffSession(owner);
    const ownerImport = await insertImport({
      businessId: owner.business.id,
      userId: owner.userId,
      customerName: 'Owner Customer',
    });
    const staffImport = await insertImport({
      businessId: owner.business.id,
      userId: staff.userId,
      customerName: 'Staff Customer',
    });

    const staffChat = await api('GET', '/ai/chat', { token: staff.token });
    assert.equal(staffChat.status, 200, JSON.stringify(staffChat.body));
    assert.deepEqual(
      staffChat.body.messages.map((m) => m.content),
      ['Draft for Staff Customer']
    );

    const staffImports = await api('GET', '/ai/imports', { token: staff.token });
    assert.equal(staffImports.status, 200, JSON.stringify(staffImports.body));
    assert.deepEqual(
      staffImports.body.imports.map((imp) => imp.id),
      [staffImport]
    );

    const hidden = await api('GET', `/ai/imports/${ownerImport}`, {
      token: staff.token,
    });
    assert.equal(hidden.status, 404, JSON.stringify(hidden.body));

    const deleteHidden = await api('DELETE', `/ai/imports/${ownerImport}`, {
      token: staff.token,
    });
    assert.equal(deleteHidden.status, 404, JSON.stringify(deleteHidden.body));

    const completeHidden = await api(
      'POST',
      `/ai/imports/${ownerImport}/complete`,
      { token: staff.token, body: { customer_name: 'X', items: [] } }
    );
    assert.equal(completeHidden.status, 404, JSON.stringify(completeHidden.body));

    const ownerChat = await api('GET', '/ai/chat', { token: owner.token });
    assert.equal(ownerChat.body.messages.length, 2, 'the owner still sees the whole business');
    const ownerImports = await api('GET', '/ai/imports', { token: owner.token });
    assert.equal(ownerImports.body.imports.length, 2);
  });
});
