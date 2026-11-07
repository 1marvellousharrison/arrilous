import test from 'node:test';
import assert from 'node:assert/strict';
import { api, createBusinessOwner, createUser } from './helpers.js';

async function setupOrganization() {
  const { session } = await createUser({ role: 'logistics_partner', full_name: 'Fast Move' });
  const created = await api('POST', '/logistics/organization', {
    token: session.access_token,
    body: {
      name: 'FastMove Logistics',
      phone: '+2349011112233',
      category: 'Courier',
      description: 'Fast regional deliveries by motorcycle.',
    },
  });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  await api('POST', '/logistics/organization/areas', { token: session.access_token, body: { city: 'Warri' } });
  // Matching drops providers that cannot serve the route (spec 15), and a
  // provider with an empty fleet can never serve one, so the fixture needs a
  // vehicle for the provider to be matchable at all.
  const vehicle = await api('POST', '/logistics/organization/vehicles', {
    token: session.access_token,
    body: { vehicle_type: 'motorcycle', total_quantity: 3, available_quantity: 3, capacity_category: 'small', starting_price_kobo: 250000 },
  });
  assert.equal(vehicle.status, 201, JSON.stringify(vehicle.body));
  await api('PATCH', '/logistics/organization/availability', {
    token: session.access_token,
    body: { is_available: true, availability_expires_at: new Date(Date.now() + 3_600_000).toISOString() },
  });
  return { token: session.access_token, organization: created.body.organization };
}

async function deliverySale(owner) {
  await api('PUT', '/business/location', {
    token: owner.token,
    body: { address: '1 Market Road', city: 'Warri', state: 'Delta', country: 'Nigeria' },
  });
  const sale = await api('POST', '/transactions', {
    token: owner.token,
    body: { delivery_required: true, delivery_address: '2 Airport Road, Warri', items: [{ name: 'Dress', quantity: 1, unit_price_kobo: 300000 }] },
  });
  assert.equal(sale.status, 201, JSON.stringify(sale.body));
  return sale.body.transaction;
}

const STAFF_PASSWORD = 'Str0ngPass!23';

async function staffSession(owner, fullName = 'Desk Staff') {
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

test('logistics organizations publish availability, areas, pricing and fleet', async () => {
  const org = await setupOrganization();
  const price = await api('POST', '/logistics/organization/pricing', { token: org.token, body: { destination: 'Warri', price_kobo: 250000 } });
  assert.equal(price.status, 201, JSON.stringify(price.body));
  const vehicle = await api('POST', '/logistics/organization/vehicles', { token: org.token, body: { vehicle_type: 'motorcycle', total_quantity: 3, available_quantity: 3, capacity_category: 'small', starting_price_kobo: 250000 } });
  assert.equal(vehicle.status, 201, JSON.stringify(vehicle.body));
  const profile = await api('GET', '/logistics/organization', { token: org.token });
  assert.equal(profile.status, 200, JSON.stringify(profile.body));
  assert.equal(profile.body.organization.isAvailable, true);
  assert.equal(profile.body.vehicles[0].availableQuantity, 3);
});

test('a business matches an active provider then completes its delivery workflow', async () => {
  const owner = await createBusinessOwner();
  const org = await setupOrganization();
  const sale = await deliverySale(owner);
  const providers = await api('GET', '/logistics/providers?destination_city=Warri', { token: owner.token });
  assert.equal(providers.status, 200, JSON.stringify(providers.body));
  assert.ok(providers.body.providers.some((provider) => provider.organization.id === org.organization.id));
  const requested = await api('POST', '/logistics/requests', { token: owner.token, body: { transaction_id: sale.id, organization_id: org.organization.id, package_size: 'small' } });
  assert.equal(requested.status, 201, JSON.stringify(requested.body));
  const accepted = await api('PATCH', `/logistics/requests/${requested.body.deliveryRequest.id}/status`, { token: org.token, body: { status: 'accepted' } });
  assert.equal(accepted.status, 200, JSON.stringify(accepted.body));
  const pickedUp = await api('PATCH', `/logistics/requests/${requested.body.deliveryRequest.id}/status`, { token: org.token, body: { status: 'picked_up' } });
  assert.equal(pickedUp.status, 200, JSON.stringify(pickedUp.body));
  const transit = await api('PATCH', `/logistics/requests/${requested.body.deliveryRequest.id}/status`, { token: org.token, body: { status: 'in_transit' } });
  assert.equal(transit.status, 200, JSON.stringify(transit.body));
  const delivered = await api('PATCH', `/logistics/requests/${requested.body.deliveryRequest.id}/status`, { token: org.token, body: { status: 'delivered' } });
  assert.equal(delivered.status, 200, JSON.stringify(delivered.body));
  const confirmed = await api('POST', `/logistics/requests/${requested.body.deliveryRequest.id}/confirm`, { token: owner.token, body: { method: 'manual' } });
  assert.equal(confirmed.status, 201, JSON.stringify(confirmed.body));
  const transaction = await api('GET', `/transactions/${sale.id}`, { token: owner.token });
  assert.equal(transaction.body.transaction.deliveryStatus, 'delivered');
});

test('a staff member works the business delivery desk', async () => {
  const owner = await createBusinessOwner();
  const org = await setupOrganization();
  const sale = await deliverySale(owner);
  const staffToken = await staffSession(owner);

  const requested = await api('POST', '/logistics/requests', {
    token: owner.token,
    body: { transaction_id: sale.id, organization_id: org.organization.id, package_size: 'small' },
  });
  assert.equal(requested.status, 201, JSON.stringify(requested.body));
  const requestId = requested.body.deliveryRequest.id;

  // A staff member sees the same business request list and detail as the owner.
  const list = await api('GET', '/logistics/requests', { token: staffToken });
  assert.equal(list.status, 200, JSON.stringify(list.body));
  assert.ok(list.body.deliveryRequests.some((request) => request.id === requestId));

  const detail = await api('GET', `/logistics/requests/${requestId}`, { token: staffToken });
  assert.equal(detail.status, 200, JSON.stringify(detail.body));

  // Business-side notifications fan out to the active team, not only the owner.
  const quoted = await api('PATCH', `/logistics/requests/${requestId}/quote`, {
    token: org.token,
    body: { quoted_price_kobo: 260000 },
  });
  assert.equal(quoted.status, 200, JSON.stringify(quoted.body));
  const staffInbox = await api('GET', '/logistics/notifications', { token: staffToken });
  assert.equal(staffInbox.status, 200, JSON.stringify(staffInbox.body));
  assert.ok(staffInbox.body.notifications.some((item) => item.kind === 'quote_received'));

  // The staff can accept the quote, read the timeline, and confirm the delivery.
  const accepted = await api('PATCH', `/logistics/requests/${requestId}/accept-quote`, {
    token: staffToken,
  });
  assert.equal(accepted.status, 200, JSON.stringify(accepted.body));
  for (const status of ['picked_up', 'in_transit', 'delivered']) {
    const moved = await api('PATCH', `/logistics/requests/${requestId}/status`, {
      token: org.token,
      body: { status },
    });
    assert.equal(moved.status, 200, `${status}: ${JSON.stringify(moved.body)}`);
  }
  const events = await api('GET', `/logistics/requests/${requestId}/events`, {
    token: staffToken,
  });
  assert.equal(events.status, 200, JSON.stringify(events.body));

  const otp = await api('POST', `/logistics/requests/${requestId}/otp`, {
    token: staffToken,
    body: { expires_in_minutes: 10 },
  });
  assert.equal(otp.status, 201, JSON.stringify(otp.body));

  const confirmed = await api('POST', `/logistics/requests/${requestId}/confirm`, {
    token: staffToken,
    body: { method: 'manual' },
  });
  assert.equal(confirmed.status, 201, JSON.stringify(confirmed.body));
});
