import test from 'node:test';
import assert from 'node:assert/strict';
import { api, createBusinessOwner, createUser } from './helpers.js';

/**
 * Integrated Build Specification v3 — logistics extension.
 *
 * These cover the product principles that must not regress: availability is
 * separate from delivery state, automatic closing affects only new matching,
 * fleet comes back when freed, and role permissions are server-side.
 */

const HOUR = 3_600_000;

const RIDER_PROFILE = {
  phone: '+2349090000001',
  category: 'Rider',
  description: 'Personal rider registered for this suite.',
};

async function makeOrganization({ city = 'Warri', vehicle = true, latitude = null, longitude = null, name, state = null } = {}) {
  const { session } = await createUser({ role: 'logistics_partner', full_name: name ?? 'Fast Move' });
  const token = session.access_token;
  const created = await api('POST', '/logistics/organization', {
    token,
    body: {
      name: name ?? 'FastMove Logistics',
      phone: '+2349011112233',
      category: 'Courier',
      description: 'Fast regional deliveries by motorcycle.',
    },
  });
  assert.equal(created.status, 201, JSON.stringify(created.body));

  const area = await api('POST', '/logistics/organization/areas', {
    token,
    body: { city, ...(state ? { state } : {}), ...(latitude != null ? { latitude, longitude } : {}) },
  });
  assert.equal(area.status, 201, JSON.stringify(area.body));

  if (vehicle) {
    const fleet = await api('POST', '/logistics/organization/vehicles', {
      token,
      body: {
        vehicle_type: 'motorcycle',
        total_quantity: 2,
        available_quantity: 2,
        capacity_category: 'small',
        starting_price_kobo: 250000,
      },
    });
    assert.equal(fleet.status, 201, JSON.stringify(fleet.body));
  }

  await api('PATCH', '/logistics/organization/availability', {
    token,
    body: { is_available: true, availability_expires_at: new Date(Date.now() + HOUR).toISOString() },
  });

  return { token, organization: created.body.organization };
}

/** A delivery-required sale whose destination city is derivable from the address. */
async function deliverySale(owner, destination = '2 Airport Road, Warri') {
  const location = await api('PUT', '/business/location', {
    token: owner.token,
    body: { address: '1 Market Road', city: 'Warri', state: 'Delta', country: 'Nigeria' },
  });
  assert.equal(location.status, 200, JSON.stringify(location.body));
  const sale = await api('POST', '/transactions', {
    token: owner.token,
    body: {
      delivery_required: true,
      delivery_address: destination,
      items: [{ name: 'Dress', quantity: 1, unit_price_kobo: 300000 }],
    },
  });
  assert.equal(sale.status, 201, JSON.stringify(sale.body));
  return sale.body.transaction;
}

async function vehicles(token) {
  const res = await api('GET', '/logistics/organization/vehicles', { token });
  assert.equal(res.status, 200, JSON.stringify(res.body));
  return res.body.vehicles;
}

test('spec 40 — fleet held by an assignment comes back when the delivery ends', async () => {
  const org = await makeOrganization();
  const owner = await createBusinessOwner();
  const sale = await deliverySale(owner);

  const before = await vehicles(org.token);
  assert.equal(before[0].available_quantity, 2, 'fixture should start with two available motorcycles');

  const requested = await api('POST', '/logistics/requests', {
    token: owner.token,
    body: { transaction_id: sale.id, organization_id: org.organization.id, package_size: 'small' },
  });
  assert.equal(requested.status, 201, JSON.stringify(requested.body));
  const requestId = requested.body.deliveryRequest.id;

  const assigned = await api('PATCH', `/logistics/requests/${requestId}/assign`, {
    token: org.token,
    body: { vehicle_id: before[0].id },
  });
  assert.equal(assigned.status, 200, JSON.stringify(assigned.body));
  assert.equal((await vehicles(org.token))[0].available_quantity, 1, 'assignment takes one vehicle out of the pool');

  for (const status of ['picked_up', 'in_transit', 'delivered']) {
    const step = await api('PATCH', `/logistics/requests/${requestId}/status`, { token: org.token, body: { status } });
    assert.equal(step.status, 200, `${status}: ${JSON.stringify(step.body)}`);
  }

  assert.equal(
    (await vehicles(org.token))[0].available_quantity,
    2,
    'spec 40 — the vehicle has to be restored once the delivery is over',
  );
});

test('spec 40 — a failed delivery returns its vehicle so the fleet is not lost', async () => {
  const org = await makeOrganization();
  const owner = await createBusinessOwner();
  const sale = await deliverySale(owner);

  const requested = await api('POST', '/logistics/requests', {
    token: owner.token,
    body: { transaction_id: sale.id, organization_id: org.organization.id, package_size: 'small' },
  });
  const requestId = requested.body.deliveryRequest.id;
  const fleet = await vehicles(org.token);

  await api('PATCH', `/logistics/requests/${requestId}/assign`, { token: org.token, body: { vehicle_id: fleet[0].id } });
  assert.equal((await vehicles(org.token))[0].available_quantity, 1);

  for (const status of ['picked_up', 'in_transit']) {
    await api('PATCH', `/logistics/requests/${requestId}/status`, { token: org.token, body: { status } });
  }
  const failed = await api('PATCH', `/logistics/requests/${requestId}/status`, {
    token: org.token,
    body: { status: 'failed', failure_reason: 'Customer unavailable' },
  });
  assert.equal(failed.status, 200, JSON.stringify(failed.body));

  assert.equal(
    (await vehicles(org.token))[0].available_quantity,
    2,
    'a failed delivery must not permanently consume a vehicle',
  );

  const retried = await api('POST', `/logistics/requests/${requestId}/retry`, { token: owner.token });
  assert.equal(retried.status, 200, JSON.stringify(retried.body));
  assert.equal((await vehicles(org.token))[0].available_quantity, 2, 'retry must not double-count the restore');
});

test('spec 40 — re-assigning an open request releases the previously held vehicle', async () => {
  const org = await makeOrganization();
  const owner = await createBusinessOwner();
  const sale = await deliverySale(owner);

  const requested = await api('POST', '/logistics/requests', {
    token: owner.token,
    body: { transaction_id: sale.id, organization_id: org.organization.id, package_size: 'small' },
  });
  const requestId = requested.body.deliveryRequest.id;
  // The fixture publishes a single vehicle type; a second row is needed so the
  // two assignments can be told apart.
  const extra = await api('POST', '/logistics/organization/vehicles', {
    token: org.token,
    body: { vehicle_type: 'car', total_quantity: 1, available_quantity: 1, capacity_category: 'large', starting_price_kobo: 600000 },
  });
  assert.equal(extra.status, 201, JSON.stringify(extra.body));
  const fleet = await vehicles(org.token);
  assert.equal(fleet.length, 2);
  const car = fleet.find((entry) => entry.vehicle_type === 'car');
  const motorcycle = fleet.find((entry) => entry.vehicle_type === 'motorcycle');
  assert.ok(car && motorcycle, 'the fixture publishes a car and a motorcycle');

  await api('PATCH', `/logistics/requests/${requestId}/assign`, { token: org.token, body: { vehicle_id: car.id } });
  await api('PATCH', `/logistics/requests/${requestId}/assign`, { token: org.token, body: { vehicle_id: motorcycle.id } });

  const after = await vehicles(org.token);
  assert.equal(after.find((entry) => entry.id === car.id).available_quantity, 1, 'the reassigned-away vehicle went back');
  assert.equal(after.find((entry) => entry.id === motorcycle.id).available_quantity, 1, 'the current vehicle is still held');
});

test('spec 39 — availability expiring stops new matching but never stops an active delivery', async () => {
  const org = await makeOrganization();
  const owner = await createBusinessOwner();
  const sale = await deliverySale(owner);

  const requested = await api('POST', '/logistics/requests', {
    token: owner.token,
    body: { transaction_id: sale.id, organization_id: org.organization.id, package_size: 'small' },
  });
  assert.equal(requested.status, 201, JSON.stringify(requested.body));
  const requestId = requested.body.deliveryRequest.id;

  // Automatic closing arrives while the delivery is already running.
  const closed = await api('PATCH', '/logistics/organization/availability', {
    token: org.token,
    body: { is_available: false },
  });
  assert.equal(closed.status, 200, JSON.stringify(closed.body));

  const matched = await api('GET', '/logistics/providers?destination_city=Warri', { token: owner.token });
  const stillOffered = matched.body.providers.some((entry) => entry.organization.id === org.organization.id);
  assert.equal(stillOffered, false, 'a closed provider is not offered for new work');

  // Existing work continues normally (spec 16, 18, 39).
  for (const status of ['accepted', 'picked_up', 'in_transit', 'delivered']) {
    const step = await api('PATCH', `/logistics/requests/${requestId}/status`, { token: org.token, body: { status } });
    assert.equal(step.status, 200, `closing must not block ${status}: ${JSON.stringify(step.body)}`);
  }
});

test('spec 39 — an automatic closing time in the past is rejected, one in the future is honoured', async () => {
  const org = await makeOrganization();

  const past = await api('PATCH', '/logistics/organization/availability', {
    token: org.token,
    body: { is_available: true, availability_expires_at: new Date(Date.now() - 60_000).toISOString() },
  });
  assert.equal(past.status, 422, JSON.stringify(past.body));

  const future = await api('PATCH', '/logistics/organization/availability', {
    token: org.token,
    body: { is_available: true, availability_expires_at: new Date(Date.now() + HOUR).toISOString() },
  });
  assert.equal(future.status, 200, JSON.stringify(future.body));
  assert.equal(future.body.organization.isAvailable, true);

  // Reaching the closing time flips the flag without touching the fleet.
  await api('PATCH', '/logistics/organization/vehicles', {
    token: org.token,
    body: { vehicle_type: 'motorcycle', total_quantity: 2, available_quantity: 2, capacity_category: 'small', starting_price_kobo: 250000 },
  });
  const fleetBefore = await vehicles(org.token);
  await api('PATCH', '/logistics/organization/availability', {
    token: org.token,
    body: { is_available: true, availability_expires_at: new Date(Date.now() + 40).toISOString() },
  });
  await new Promise((resolve) => setTimeout(resolve, 60));

  const profile = await api('GET', '/logistics/organization', { token: org.token });
  assert.equal(profile.body.organization.isAvailable, false, 'the closing time elapsed');
  const fleetAfter = await vehicles(org.token);
  assert.equal(fleetAfter[0].available_quantity, fleetBefore[0].available_quantity, 'closing leaves the fleet alone');
});

test('spec 15 — matching removes providers that cannot serve the route', async () => {
  const owner = await createBusinessOwner();
  await api('PUT', '/business/location', {
    token: owner.token,
    body: { address: '1 Market Road', city: 'Warri', state: 'Delta', country: 'Nigeria' },
  });

  // Covers the destination but not the business pickup city.
  const wrongPickup = await makeOrganization({ city: 'Sapele' });
  // Covers neither.
  const nowhereNear = await makeOrganization({ city: 'Benin City' });

  const matched = await api('GET', '/logistics/providers?destination_city=Warri', { token: owner.token });
  assert.equal(matched.status, 200, JSON.stringify(matched.body));
  const ids = matched.body.providers.map((provider) => provider.organization.id);
  assert.ok(!ids.includes(wrongPickup.organization.id), 'a provider that cannot pick up is dropped');
  assert.ok(!ids.includes(nowhereNear.organization.id), 'a provider that cannot deliver is dropped');

  // A provider covering both ends of the route is kept.
  const onRoute = await makeOrganization({ city: 'Warri' });
  const withBoth = await api('GET', '/logistics/providers?destination_city=Warri', { token: owner.token });
  assert.ok(
    withBoth.body.providers.some((provider) => provider.organization.id === onRoute.organization.id),
    'a provider covering pickup and destination is offered',
  );
});

test('spec 15 — capacity and mode suitability narrow the match', async () => {
  const owner = await createBusinessOwner();
  await api('PUT', '/business/location', {
    token: owner.token,
    body: { address: '1 Market Road', city: 'Warri', state: 'Delta', country: 'Nigeria' },
  });
  const org = await makeOrganization();

  const matched = async (query) => {
    const res = await api('GET', `/logistics/providers?destination_city=Warri&${query}`, { token: owner.token });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    return res.body.providers.some((entry) => entry.organization.id === org.organization.id);
  };

  assert.equal(await matched('package_size=small'), true, 'a small-capacity motorcycle accepts a small package');
  assert.equal(await matched('package_size=very_large'), false, 'spec 25 — a small motorcycle cannot take a very large order');
  assert.equal(await matched('preferred_mode=car'), false, 'a motorcycle provider is not offered for a car request');
});

test('spec 14 and 17 — an active rider is offered to the business and dropped once inactive', async () => {
  const owner = await createBusinessOwner();
  await api('PUT', '/business/location', {
    token: owner.token,
    body: { address: '1 Market Road', city: 'Warri', state: 'Delta', country: 'Nigeria' },
  });
  await makeOrganization({ city: 'Warri' });

  const { session } = await createUser({ role: 'rider', full_name: 'Ada Rider' });
  const riderToken = session.access_token;
  assert.equal((await api('POST', '/logistics/rider', { token: riderToken, body: RIDER_PROFILE })).status, 201);
  assert.equal(
    (await api('POST', '/logistics/rider/areas', { token: riderToken, body: { city: 'Warri' } })).status,
    201,
  );
  assert.equal(
    (await api('POST', '/logistics/rider/modes', {
      token: riderToken,
      body: { mode: 'motorcycle', capacity_category: 'small', rate_kobo: 150000, is_primary: true, active: true },
    })).status,
    201,
  );
  assert.equal(
    (await api('PATCH', '/logistics/rider/availability', { token: riderToken, body: { is_available: true } })).status,
    200,
  );

  const search = async () => {
    const res = await api('GET', '/logistics/providers?destination_city=Warri', { token: owner.token });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    return res.body.riders.some((entry) => entry.rider.userId === session.user.id);
  };

  assert.equal(await search(), true, 'spec 14 — the active rider is visible when the business searches');
  assert.equal(
    (await api('PATCH', '/logistics/rider/availability', { token: riderToken, body: { is_available: false } })).status,
    200,
  );
  assert.equal(await search(), false, 'spec 17 — the inactive rider is no longer offered');

  const back = await api('PATCH', '/logistics/rider/availability', { token: riderToken, body: { is_available: true } });
  assert.equal(back.status, 200);
  assert.ok(back.body.rider.availabilityExpiresAt, 'spec 17 — going active always schedules an automatic closing time');
});

test('spec 15 — matches are ranked by state, then town, then distance', async () => {
  const owner = await createBusinessOwner();
  await api('PUT', '/business/location', {
    token: owner.token,
    body: { address: '1 Market Road', city: 'Ikeja', state: 'Lagos', country: 'Nigeria', latitude: 6.6, longitude: 3.35 },
  });

  // Same town but a different state — still served, ranked behind Lagos.
  const delta = await makeOrganization({ city: 'Ikeja', state: 'Delta', name: 'Delta Move' });
  // Same state; one close to the business, one far away.
  const far = await makeOrganization({ city: 'Ikeja', state: 'Lagos', latitude: 6.61, longitude: 3.35, name: 'Far Move' });
  const near = await makeOrganization({ city: 'Ikeja', state: 'Lagos', latitude: 6.6005, longitude: 3.3505, name: 'Near Move' });

  const res = await api('GET', '/logistics/providers?destination_city=Ikeja', { token: owner.token });
  assert.equal(res.status, 200, JSON.stringify(res.body));
  const order = res.body.providers.map((provider) => provider.organization.name);
  const rank = (name) => order.indexOf(name);

  assert.ok(rank('Near Move') >= 0, 'the near Lagos provider is offered');
  assert.ok(rank('Near Move') < rank('Far Move'), 'same state, so distance breaks the tie');
  assert.ok(rank('Far Move') < rank('Delta Move'), 'a provider in the business state outranks another state');
});

test('spec 47 — a logistics account cannot reach business or catalog endpoints', async () => {
  const { session } = await createUser({ role: 'logistics_partner' });
  const token = session.access_token;

  for (const route of ['/business', '/products', '/customers', '/transactions', '/dashboard/summary']) {
    const res = await api('GET', route, { token });
    assert.ok(res.status >= 400 && res.status < 500, `${route} must be refused, got ${res.status}`);
    assert.match(JSON.stringify(res.body), /business|permission|not available/i);
  }
});

test('spec 47 — a rider sees only its own requests, not another rider\'s', async () => {
  const org = await makeOrganization();
  const owner = await createBusinessOwner();
  const sale = await deliverySale(owner);

  const requested = await api('POST', '/logistics/requests', {
    token: owner.token,
    body: { transaction_id: sale.id, organization_id: org.organization.id, package_size: 'small' },
  });
  const requestId = requested.body.deliveryRequest.id;

  const riderA = await createUser({ role: 'rider', full_name: 'Michael Rider' });
  const riderACreated = await api('POST', '/logistics/rider', { token: riderA.session.access_token, body: RIDER_PROFILE });
  assert.equal(riderACreated.status, 201, JSON.stringify(riderACreated.body));
  const attached = await api('PATCH', '/logistics/organization/riders', {
    token: org.token,
    body: { rider_user_id: riderA.session.user.id },
  });
  assert.equal(attached.status, 200, JSON.stringify(attached.body));
  await api('PATCH', `/logistics/requests/${requestId}/assign`, {
    token: org.token,
    body: { rider_id: attached.body.rider.id },
  });

  const riderB = await createUser({ role: 'rider', full_name: 'David Rider' });
  await api('POST', '/logistics/rider', { token: riderB.session.access_token, body: RIDER_PROFILE });

  const forB = await api('GET', '/logistics/requests', { token: riderB.session.access_token });
  assert.equal(forB.status, 200, JSON.stringify(forB.body));
  assert.equal(forB.body.deliveryRequests.length, 0, 'an uninvited rider sees no delivery work');

  const forA = await api('GET', '/logistics/requests', { token: riderA.session.access_token });
  assert.ok(forA.body.deliveryRequests.some((entry) => entry.id === requestId), 'the assigned rider sees it');
});

test('spec 17 — a rider extends availability by 30 minutes and by an hour', async () => {
  const { session } = await createUser({ role: 'rider', full_name: 'Michael Rider' });
  const token = session.access_token;
  const created = await api('POST', '/logistics/rider', { token, body: RIDER_PROFILE });
  assert.equal(created.status, 201, JSON.stringify(created.body));

  const base = new Date(Date.now() + 8 * 60_000).toISOString();
  const start = await api('PATCH', '/logistics/rider/availability', {
    token,
    body: { is_available: true, availability_expires_at: base },
  });
  assert.equal(start.status, 200, JSON.stringify(start.body));
  const initialExpiry = new Date(start.body.rider.availabilityExpiresAt).getTime();

  const halfHour = await api('POST', '/logistics/rider/availability/extend', { token, body: { minutes: 30 } });
  assert.equal(halfHour.status, 200, JSON.stringify(halfHour.body));
  const afterHalf = new Date(halfHour.body.rider.availabilityExpiresAt).getTime();
  assert.ok(Math.abs(afterHalf - initialExpiry - 30 * 60_000) < 2000, 'spec 17 — +30 minutes adds half an hour');

  const hour = await api('POST', '/logistics/rider/availability/extend', { token, body: { minutes: 60 } });
  assert.equal(hour.status, 200, JSON.stringify(hour.body));
  assert.ok(
    Math.abs(new Date(hour.body.rider.availabilityExpiresAt).getTime() - afterHalf - 60 * 60_000) < 2000,
    'spec 17 — +1 hour adds an hour',
  );
});

test('spec 17 — extending without being available is refused', async () => {
  const { session } = await createUser({ role: 'rider', full_name: 'Idle Rider' });
  const token = session.access_token;
  await api('POST', '/logistics/rider', { token, body: RIDER_PROFILE });

  const res = await api('POST', '/logistics/rider/availability/extend', { token, body: { minutes: 30 } });
  assert.equal(res.status, 400, JSON.stringify(res.body));
});

test("spec 17 — a rider plans today's hours on activation and can re-plan mid-shift", async () => {
  const { session } = await createUser({ role: 'rider', full_name: 'Planned Rider' });
  const token = session.access_token;
  await api('POST', '/logistics/rider', { token, body: RIDER_PROFILE });

  const start = await api('PATCH', '/logistics/rider/availability', {
    token,
    body: { is_available: true, planned_hours: 4 },
  });
  assert.equal(start.status, 200, JSON.stringify(start.body));
  assert.equal(start.body.rider.plannedHours, 4, 'the chosen plan is kept on the profile');
  assert.ok(
    Math.abs(new Date(start.body.rider.availabilityExpiresAt).getTime() - Date.now() - 4 * HOUR) < 3_000,
    'spec 17 — the closing time comes from the plan',
  );

  const replan = await api('PATCH', '/logistics/rider/availability', {
    token,
    body: { is_available: true, planned_hours: 8 },
  });
  assert.equal(replan.status, 200, JSON.stringify(replan.body));
  assert.equal(replan.body.rider.plannedHours, 8);
  assert.ok(
    Math.abs(new Date(replan.body.rider.availabilityExpiresAt).getTime() - new Date(replan.body.rider.availabilityStartedAt).getTime() - 8 * HOUR) < 3_000,
    'spec 17 — re-planning measures the plan from the current time',
  );

  const shrink = await api('PATCH', '/logistics/rider/availability', {
    token,
    body: { is_available: true, planned_hours: 1 },
  });
  assert.equal(shrink.status, 200, JSON.stringify(shrink.body));
  assert.ok(
    new Date(shrink.body.rider.availabilityExpiresAt).getTime() <= Date.now() + 3 * 3_600_000,
    'spec 17 — trimming the plan pulls the closing time in',
  );
});

test('spec 17 — asking for a closing time derives the kept plan', async () => {
  const { session } = await createUser({ role: 'rider', full_name: 'Until Rider' });
  const token = session.access_token;
  await api('POST', '/logistics/rider', { token, body: RIDER_PROFILE });

  const closes = new Date(Date.now() + 3 * HOUR + 10 * 60_000).toISOString();
  const start = await api('PATCH', '/logistics/rider/availability', {
    token,
    body: { is_available: true, availability_expires_at: closes },
  });
  assert.equal(start.status, 200, JSON.stringify(start.body));
  assert.equal(start.body.rider.plannedHours, 3, 'the plan is derived from the requested closing time');

  const replan = await api('PATCH', '/logistics/rider/availability', {
    token,
    body: { is_available: true, availability_expires_at: new Date(Date.now() + 5 * HOUR).toISOString() },
  });
  assert.equal(replan.status, 200, JSON.stringify(replan.body));
  assert.equal(replan.body.rider.plannedHours, 5, 're-planning with an exact time recomputes the plan from the current time');
  assert.notEqual(
    replan.body.rider.availabilityStartedAt,
    start.body.rider.availabilityStartedAt,
    're-planning with an exact time restarts the shift from the current time',
  );
});

test('spec 16 — an organization sets its planned hours when going active', async () => {
  const org = await makeOrganization();
  const set = await api('PATCH', '/logistics/organization/availability', {
    token: org.token,
    body: { is_available: true, planned_hours: 6 },
  });
  assert.equal(set.status, 200, JSON.stringify(set.body));
  assert.equal(set.body.organization.plannedHours, 6, 'the plan is kept on the organization');
  assert.ok(
    Math.abs(new Date(set.body.organization.availabilityExpiresAt).getTime() - Date.now() - 6 * HOUR) < 3_000,
    'spec 16 — the plan drives the closing time',
  );
});

test('spec 17 — a rider adds and removes time from an active shift', async () => {
  const { session } = await createUser({ role: 'rider', full_name: 'Trimming Rider' });
  const token = session.access_token;
  await api('POST', '/logistics/rider', { token, body: RIDER_PROFILE });

  const start = await api('PATCH', '/logistics/rider/availability', {
    token,
    body: { is_available: true, planned_hours: 4 },
  });
  const plan = new Date(start.body.rider.availabilityExpiresAt).getTime();

  const add = await api('POST', '/logistics/rider/availability/extend', { token, body: { minutes: 30 } });
  assert.equal(add.status, 200, JSON.stringify(add.body));
  assert.ok(
    Math.abs(new Date(add.body.rider.availabilityExpiresAt).getTime() - plan - 30 * 60_000) < 2_000,
    'spec 17 — adding stretches the closing time',
  );

  const trim = await api('POST', '/logistics/rider/availability/extend', { token, body: { minutes: -90 } });
  assert.equal(trim.status, 200, JSON.stringify(trim.body));
  assert.ok(
    Math.abs(new Date(trim.body.rider.availabilityExpiresAt).getTime() - plan - 30 * 60_000 + 90 * 60_000) < 2_000,
    'spec 17 — trimming pulls the closing time back',
  );
  assert.equal(trim.body.rider.isAvailable, true, 'trimming short of the end keeps the shift live');
});

test('spec 17 — trimming away the whole shift closes it', async () => {
  const { session } = await createUser({ role: 'rider', full_name: 'Early Quitter' });
  const token = session.access_token;
  await api('POST', '/logistics/rider', { token, body: RIDER_PROFILE });
  await api('PATCH', '/logistics/rider/availability', {
    token,
    body: { is_available: true, availability_expires_at: new Date(Date.now() + 10 * 60_000).toISOString() },
  });

  const done = await api('POST', '/logistics/rider/availability/extend', { token, body: { minutes: -60 } });
  assert.equal(done.status, 200, JSON.stringify(done.body));
  assert.equal(done.body.rider.isAvailable, false, 'removing more than the remainder ends the shift');
  assert.equal(done.body.rider.availabilityExpiresAt, null);
  assert.equal(done.body.rider.plannedHours, null);
});

test('spec 17 — a zero-minute adjustment is refused', async () => {
  const { session } = await createUser({ role: 'rider', full_name: 'No-Op Rider' });
  const token = session.access_token;
  await api('POST', '/logistics/rider', { token, body: RIDER_PROFILE });

  const res = await api('POST', '/logistics/rider/availability/extend', { token, body: { minutes: 0 } });
  assert.equal(res.status, 422, JSON.stringify(res.body));
});

test('spec 18 — availability and current delivery state are separate flags', async () => {
  const org = await makeOrganization();
  const owner = await createBusinessOwner();
  const sale = await deliverySale(owner);

  const requested = await api('POST', '/logistics/requests', {
    token: owner.token,
    body: { transaction_id: sale.id, organization_id: org.organization.id, package_size: 'small' },
  });
  const requestId = requested.body.deliveryRequest.id;
  await api('PATCH', `/logistics/requests/${requestId}/assign`, { token: org.token, body: {} });
  await api('PATCH', `/logistics/requests/${requestId}/status`, { token: org.token, body: { status: 'picked_up' } });
  await api('PATCH', `/logistics/requests/${requestId}/status`, { token: org.token, body: { status: 'in_transit' } });

  await api('PATCH', '/logistics/organization/availability', { token: org.token, body: { is_available: false } });

  const profile = await api('GET', '/logistics/organization', { token: org.token });
  assert.equal(profile.body.organization.isAvailable, false, 'availability: inactive');

  const list = await api('GET', '/logistics/requests', { token: org.token });
  const active = list.body.deliveryRequests.find((entry) => entry.id === requestId);
  assert.ok(active, 'the delivery is still owned by the organization');
  assert.equal(active.status, 'in_transit', 'existing delivery: still in transit');
});

test('spec 21 and 45 — published, quoted and accepted prices are all retained', async () => {
  const org = await makeOrganization();
  const owner = await createBusinessOwner();
  const sale = await deliverySale(owner);

  const priced = await api('POST', '/logistics/organization/pricing', {
    token: org.token,
    body: { destination: 'Warri', price_kobo: 250000 },
  });
  assert.equal(priced.status, 201, JSON.stringify(priced.body));

  const requested = await api('POST', '/logistics/requests', {
    token: owner.token,
    body: { transaction_id: sale.id, organization_id: org.organization.id, package_size: 'small' },
  });
  assert.equal(requested.status, 201, JSON.stringify(requested.body));
  const requestId = requested.body.deliveryRequest.id;
  assert.equal(
    requested.body.deliveryRequest.publishedPriceKobo,
    250000,
    'the published area price is carried onto the request',
  );

  const quoted = await api('PATCH', `/logistics/requests/${requestId}/quote`, {
    token: org.token,
    body: { quoted_price_kobo: 300000 },
  });
  assert.equal(quoted.status, 200, JSON.stringify(quoted.body));
  assert.equal(quoted.body.deliveryRequest.quotedPriceKobo, 300000, 'spec 21 — the order-specific quote');
  assert.equal(quoted.body.deliveryRequest.acceptedPriceKobo, null);

  const accepted = await api('PATCH', `/logistics/requests/${requestId}/accept-quote`, { token: owner.token });
  assert.equal(accepted.status, 200, JSON.stringify(accepted.body));
  assert.equal(accepted.body.deliveryRequest.acceptedPriceKobo, 300000, 'spec 45 — the accepted price');
  assert.equal(accepted.body.deliveryRequest.publishedPriceKobo, 250000, 'the published price is not overwritten');
});

test('spec 30 — a delivered order is confirmed with the customer OTP', async () => {
  const org = await makeOrganization();
  const owner = await createBusinessOwner();
  const sale = await deliverySale(owner);

  const requested = await api('POST', '/logistics/requests', {
    token: owner.token,
    body: { transaction_id: sale.id, organization_id: org.organization.id, package_size: 'small' },
  });
  const requestId = requested.body.deliveryRequest.id;
  for (const status of ['accepted', 'picked_up', 'in_transit', 'delivered']) {
    const step = await api('PATCH', `/logistics/requests/${requestId}/status`, { token: org.token, body: { status } });
    assert.equal(step.status, 200, `${status}: ${JSON.stringify(step.body)}`);
  }

  const otp = await api('POST', `/logistics/requests/${requestId}/otp`, { token: org.token, body: {} });
  assert.equal(otp.status, 201, JSON.stringify(otp.body));
  assert.match(otp.body.developmentOtp, /^\d{6}$/, 'the dev seam returns the 6-digit code');

  const wrong = await api('POST', `/logistics/requests/${requestId}/confirm`, {
    token: owner.token,
    body: { method: 'otp', otp: wrongOf(otp.body.developmentOtp) },
  });
  assert.ok(wrong.status >= 400, `a wrong OTP must be refused: ${wrong.status}`);

  const right = await api('POST', `/logistics/requests/${requestId}/confirm`, {
    token: owner.token,
    body: { method: 'otp', otp: otp.body.developmentOtp },
  });
  assert.equal(right.status, 201, JSON.stringify(right.body));

  const saleAfter = await api('GET', `/transactions/${sale.id}`, { token: owner.token });
  assert.equal(saleAfter.body.transaction.deliveryStatus, 'delivered');
  assert.equal(saleAfter.body.transaction.completionStatus, 'open', 'spec 11 — confirmation is not completion');
});

/** A 6-digit code that is guaranteed not to match the one that was issued. */
function wrongOf(code) {
  return code === '000000' ? '111111' : '000000';
}

test('spec 31 — a failed delivery keeps its reason and can be retried', async () => {
  const org = await makeOrganization();
  const owner = await createBusinessOwner();
  const sale = await deliverySale(owner);

  const requested = await api('POST', '/logistics/requests', {
    token: owner.token,
    body: { transaction_id: sale.id, organization_id: org.organization.id, package_size: 'small' },
  });
  const requestId = requested.body.deliveryRequest.id;
  for (const status of ['accepted', 'picked_up', 'in_transit']) {
    await api('PATCH', `/logistics/requests/${requestId}/status`, { token: org.token, body: { status } });
  }

  const withoutReason = await api('PATCH', `/logistics/requests/${requestId}/status`, {
    token: org.token,
    body: { status: 'failed' },
  });
  assert.equal(withoutReason.status, 422, 'spec 31 — a failure needs a reason');

  const failed = await api('PATCH', `/logistics/requests/${requestId}/status`, {
    token: org.token,
    body: { status: 'failed', failure_reason: 'Wrong address' },
  });
  assert.equal(failed.status, 200, JSON.stringify(failed.body));
  assert.equal(failed.body.deliveryRequest.failureReason, 'Wrong address');

  const events = await api('GET', `/logistics/requests/${requestId}/events`, { token: owner.token });
  assert.ok(
    events.body.events.some((entry) => entry.eventType === 'failed'),
    'the failed attempt stays in history (spec 31)',
  );

  const retried = await api('POST', `/logistics/requests/${requestId}/retry`, { token: owner.token });
  assert.equal(retried.status, 200, JSON.stringify(retried.body));
  assert.equal(retried.body.deliveryRequest.status, 'requested');
  assert.equal(retried.body.deliveryRequest.failureReason, null);

  const afterRetry = await api('GET', `/logistics/requests/${requestId}/events`, { token: owner.token });
  assert.ok(
    afterRetry.body.events.some((entry) => entry.eventType === 'failed'),
    'the original failure is never deleted from history',
  );
});

test('spec 27 — delivery requests raise notifications for the right people', async () => {
  const org = await makeOrganization();
  const owner = await createBusinessOwner();
  const sale = await deliverySale(owner);

  const requested = await api('POST', '/logistics/requests', {
    token: owner.token,
    body: { transaction_id: sale.id, organization_id: org.organization.id, package_size: 'small' },
  });
  const requestId = requested.body.deliveryRequest.id;

  const providerInbox = await api('GET', '/logistics/notifications', { token: org.token });
  assert.equal(providerInbox.status, 200, JSON.stringify(providerInbox.body));
  assert.ok(
    providerInbox.body.notifications.some((entry) => entry.kind === 'delivery_requested'),
    'the provider is told about new work',
  );

  await api('PATCH', `/logistics/requests/${requestId}/status`, { token: org.token, body: { status: 'accepted' } });
  const ownerInbox = await api('GET', '/logistics/notifications', { token: owner.token });
  assert.ok(
    ownerInbox.body.notifications.some((entry) => entry.kind === 'delivery_accepted'),
    'the business is told its request was accepted',
  );
});

test('spec 26 — the organization sees its own riders and their active jobs', async () => {
  const org = await makeOrganization();
  const owner = await createBusinessOwner();
  const sale = await deliverySale(owner);

  const rider = await createUser({ role: 'rider', full_name: 'Michael Rider' });
  await api('POST', '/logistics/rider', { token: rider.session.access_token, body: RIDER_PROFILE });
  await api('PATCH', '/logistics/organization/riders', {
    token: org.token,
    body: { rider_user_id: rider.session.user.id },
  });

  const before = await api('GET', '/logistics/organization/riders', { token: org.token });
  assert.equal(before.body.riders.length, 1);
  assert.equal(before.body.riders[0].activeJobs, 0, 'an idle rider has no active jobs');

  const requested = await api('POST', '/logistics/requests', {
    token: owner.token,
    body: { transaction_id: sale.id, organization_id: org.organization.id, package_size: 'small' },
  });
  await api('PATCH', `/logistics/requests/${requested.body.deliveryRequest.id}/assign`, {
    token: org.token,
    body: { rider_id: before.body.riders[0].id },
  });

  const after = await api('GET', '/logistics/organization/riders', { token: org.token });
  assert.equal(after.body.riders[0].activeJobs, 1, 'spec 26 — assigned work shows as an active job');
});

test('spec 28 and 53 — the delivery detail names both sides, their phones and the timeline, for participants only', async () => {
  const org = await makeOrganization();
  const owner = await createBusinessOwner('Sunrise Fabrics');

  const location = await api('PUT', '/business/location', {
    token: owner.token,
    body: { address: '1 Market Road', area: 'Market Quarter', city: 'Warri', state: 'Delta', country: 'Nigeria' },
  });
  assert.equal(location.status, 200, JSON.stringify(location.body));

  const customer = await api('POST', '/customers', {
    token: owner.token,
    body: { name: 'Ada Obi', phone: '+2348011111111', email: 'ada@example.com' },
  });
  assert.equal(customer.status, 201, JSON.stringify(customer.body));

  const sale = await api('POST', '/transactions', {
    token: owner.token,
    body: {
      delivery_required: true,
      delivery_address: '2 Airport Road, Warri',
      customer_id: customer.body.customer.id,
      items: [{ name: 'Dress', quantity: 1, unit_price_kobo: 300000 }],
    },
  });
  assert.equal(sale.status, 201, JSON.stringify(sale.body));

  const requested = await api('POST', '/logistics/requests', {
    token: owner.token,
    body: { transaction_id: sale.body.transaction.id, organization_id: org.organization.id, package_size: 'small' },
  });
  assert.equal(requested.status, 201, JSON.stringify(requested.body));
  const requestId = requested.body.deliveryRequest.id;

  const rider = await createUser({ role: 'rider', full_name: 'Michael Rider' });
  await api('POST', '/logistics/rider', { token: rider.session.access_token, body: RIDER_PROFILE });
  const attached = await api('PATCH', '/logistics/organization/riders', {
    token: org.token,
    body: { rider_user_id: rider.session.user.id },
  });
  assert.equal(attached.status, 200, JSON.stringify(attached.body));
  const assigned = await api('PATCH', `/logistics/requests/${requestId}/assign`, {
    token: org.token,
    body: { rider_id: attached.body.rider.id },
  });
  assert.equal(assigned.status, 200, JSON.stringify(assigned.body));

  const detail = await api('GET', `/logistics/requests/${requestId}`, { token: owner.token });
  assert.equal(detail.status, 200, JSON.stringify(detail.body));
  const payload = detail.body.deliveryRequest;
  assert.equal(payload.business.name, 'Sunrise Fabrics', 'spec 28 — the business at the pickup point is named');
  assert.equal(
    payload.business.phone,
    owner.business.phone,
    'the business contact travels with the request so the rider can call the shop',
  );
  assert.equal(payload.customer.name, 'Ada Obi', 'spec 28 — the receiving customer is named');
  assert.equal(payload.customer.phone, '+2348011111111', 'spec 28 — the customer phone is on the delivery, not on a separate screen');
  assert.equal(payload.pickup.city, 'Warri');
  assert.equal(payload.pickup.area, 'Market Quarter', 'the pickup location is what the owner typed: city, area and state');
  assert.equal(payload.pickup.state, 'Delta');
  assert.equal(payload.destination.address, '2 Airport Road, Warri');
  assert.equal(payload.rider.name, 'Michael Rider');
  assert.ok(payload.totals.totalKobo > 0, 'the money on the order comes with it');
  assert.ok(payload.events.length >= 2, 'spec 53 — how the delivery got here is on the timeline');
  assert.ok(payload.events.some((entry) => entry.eventType === 'requested'), 'the timeline starts with the request');
  assert.ok(payload.events.some((entry) => entry.eventType === 'assigned'), 'and carries on with the assignment');

  const forRider = await api('GET', `/logistics/requests/${requestId}`, { token: rider.session.access_token });
  assert.equal(forRider.status, 200, 'the assigned rider can open the same breakdown');
  assert.equal(forRider.body.deliveryRequest.customer.phone, '+2348011111111');

  const forOrg = await api('GET', `/logistics/requests/${requestId}`, { token: org.token });
  assert.equal(forOrg.status, 200, 'the organization can open it too');

  const strangerRider = await createUser({ role: 'rider', full_name: 'David Rider' });
  await api('POST', '/logistics/rider', { token: strangerRider.session.access_token, body: RIDER_PROFILE });
  const intruder = await api('GET', `/logistics/requests/${requestId}`, { token: strangerRider.session.access_token });
  assert.equal(intruder.status, 404, 'spec 47 — someone outside the delivery gets nothing, not even a 403');

  const otherBusiness = await createBusinessOwner('Other Store');
  const outside = await api('GET', `/logistics/requests/${requestId}`, { token: otherBusiness.token });
  assert.equal(outside.status, 404, 'another business cannot read this delivery');
});

test('spec 6 — the organization sees its earnings and completed delivery history', async () => {
  const org = await makeOrganization();
  const owner = await createBusinessOwner();
  const sale = await deliverySale(owner);
  await api('POST', '/logistics/organization/pricing', { token: org.token, body: { destination: 'Warri', price_kobo: 250000 } });
  const requested = await api('POST', '/logistics/requests', {
    token: owner.token,
    body: { transaction_id: sale.id, organization_id: org.organization.id, package_size: 'small' },
  });
  assert.equal(requested.status, 201, JSON.stringify(requested.body));
  const requestId = requested.body.deliveryRequest.id;
  const vehicle = (await vehicles(org.token))[0];

  const assigned = await api('PATCH', `/logistics/requests/${requestId}/assign`, {
    token: org.token,
    body: { vehicle_id: vehicle.id },
  });
  assert.equal(assigned.status, 200, JSON.stringify(assigned.body));

  for (const status of ['picked_up', 'in_transit', 'delivered']) {
    const step = await api('PATCH', `/logistics/requests/${requestId}/status`, { token: org.token, body: { status } });
    assert.equal(step.status, 200, `${status}: ${JSON.stringify(step.body)}`);
  }

  const earnings = await api('GET', '/logistics/organization/earnings', { token: org.token });
  assert.equal(earnings.status, 200, JSON.stringify(earnings.body));
  assert.equal(earnings.body.earningsKobo, 250000, 'one completed delivery at the published motorcycle price');
  assert.equal(earnings.body.history.length, 1);
  assert.equal(earnings.body.history[0].businessName, 'Test Store');
  assert.equal(earnings.body.history[0].amountKobo, 250000);

  const ownerEarnings = await api('GET', '/logistics/organization/earnings', { token: owner.token });
  assert.equal(ownerEarnings.status, 403, 'a business cannot open an organization earnings ledger');
});

test('spec 6 — a rider carries a delivery and sees that money in their ledger', async () => {
  const org = await makeOrganization();
  const owner = await createBusinessOwner();
  const sale = await deliverySale(owner);

  const rider = await createUser({ role: 'rider', full_name: 'Michael Rider' });
  await api('POST', '/logistics/rider', { token: rider.session.access_token, body: RIDER_PROFILE });
  const riderId = (await api('GET', '/logistics/rider', { token: rider.session.access_token })).body.rider.id;
  await api('PATCH', '/logistics/organization/riders', {
    token: org.token,
    body: { rider_user_id: rider.session.user.id },
  });
  await api('POST', '/logistics/organization/pricing', { token: org.token, body: { destination: 'Warri', price_kobo: 250000 } });

  const requested = await api('POST', '/logistics/requests', {
    token: owner.token,
    body: { transaction_id: sale.id, organization_id: org.organization.id, package_size: 'small' },
  });
  const requestId = requested.body.deliveryRequest.id;

  const assigned = await api('PATCH', `/logistics/requests/${requestId}/assign`, {
    token: org.token,
    body: { rider_id: riderId, vehicle_id: (await vehicles(org.token))[0].id },
  });
  assert.equal(assigned.status, 200, JSON.stringify(assigned.body));

  for (const status of ['picked_up', 'in_transit', 'delivered']) {
    const step = await api('PATCH', `/logistics/requests/${requestId}/status`, { token: org.token, body: { status } });
    assert.equal(step.status, 200, `${status}: ${JSON.stringify(step.body)}`);
  }

  const earnings = await api('GET', '/logistics/rider/earnings', { token: rider.session.access_token });
  assert.equal(earnings.status, 200, JSON.stringify(earnings.body));
  assert.equal(earnings.body.earningsKobo, 250000);
  assert.equal(earnings.body.history.length, 1);
  assert.equal(earnings.body.history[0].riderName, 'Michael Rider');
});

