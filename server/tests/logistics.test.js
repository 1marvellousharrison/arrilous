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
