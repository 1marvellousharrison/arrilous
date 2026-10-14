import test, { describe } from 'node:test';
import assert from 'node:assert/strict';
import { api, createUser, createBusinessOwner, uniquePhone } from './helpers.js';

describe('phase 1 — business profile', () => {
  test('a new owner sees no business until setup completes', async () => {
    const { session } = await createUser();
    const res = await api('GET', '/business', { token: session.access_token });

    assert.equal(res.status, 200);
    assert.equal(res.body.business, null);
  });

  test('creates the profile from the signed-in owner, ignoring any owner id sent', async () => {
    const owner = await createUser();
    const other = await createUser();
    const res = await api('POST', '/business', {
      token: owner.session.access_token,
      body: {
        business_name: '  Ada Provisions  ',
        business_category: 'Groceries',
        business_description: 'Fresh provisions and household goods.',
        phone: uniquePhone(),
        owner_user_id: other.session.user.id,
      },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.business.businessName, 'Ada Provisions');
    assert.equal(res.body.business.ownerUserId, owner.session.user.id);
    assert.notEqual(res.body.business.ownerUserId, other.session.user.id);
    assert.equal(res.body.business.location, null);
  });

  test('rejects a profile with no name, and reports the field', async () => {
    const { session } = await createUser();
    const res = await api('POST', '/business', {
      token: session.access_token,
      body: { business_category: 'Groceries' },
    });

    assert.equal(res.status, 422);
    assert.ok(res.body.error.details.some((d) => d.field === 'business_name'));
  });

  test('allows exactly one business per owner', async () => {
    const owner = await createBusinessOwner('First Shop');
    const res = await api('POST', '/business', {
      token: owner.token,
      body: {
        business_name: 'Second Shop',
        business_category: 'Groceries',
        business_description: 'A second shop that must not exist.',
        phone: uniquePhone(),
      },
    });

    assert.equal(res.status, 409);
    assert.equal(res.body.error.code, 'business_exists');
  });

  test('requires a phone, a category and a description when creating a profile', async () => {
    const { session } = await createUser();
    const res = await api('POST', '/business', {
      token: session.access_token,
      body: { business_name: 'Incomplete Shop' },
    });

    assert.equal(res.status, 422);
    const fields = res.body.error.details.map((detail) => detail.field);
    assert.ok(fields.includes('phone'), 'a phone number is part of the business profile');
    assert.ok(fields.includes('business_category'), 'a category is part of the business profile');
    assert.ok(fields.includes('business_description'), 'what the shop sells is part of the business profile');
  });

  test('updates only the fields that were sent', async () => {
    const owner = await createBusinessOwner('Original Name');
    const res = await api('PATCH', '/business', {
      token: owner.token,
      body: { business_description: 'We sell provisions weekly.' },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.business.businessName, 'Original Name');
    assert.equal(res.body.business.businessDescription, 'We sell provisions weekly.');
  });

  test('blocks a non-business role from the profile endpoints', async () => {
    const { session } = await createUser({ role: 'rider' });
    const res = await api('POST', '/business', {
      token: session.access_token,
      body: { business_name: 'Should Not Work' },
    });

    assert.equal(res.status, 403);
  });

  test('blocks an owner without a business from editing one', async () => {
    const { session } = await createUser();
    const res = await api('PATCH', '/business', {
      token: session.access_token,
      body: { business_name: 'Missing Profile' },
    });

    assert.equal(res.status, 404);
  });

  test('requires authentication', async () => {
    const res = await api('GET', '/business');
    assert.equal(res.status, 401);
  });
});

describe('phase 1 — business logo', () => {
  // A real 1x1 PNG, so the assertion exercises the same data-URL shape the
  // client sends rather than a made-up string.
  const PNG =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP478oAAAOLAUV+7IS+AAAAAElFTkSuQmCC';

  test('a profile starts with no logo', async () => {
    const owner = await createBusinessOwner('Logo-less Store');
    const res = await api('GET', '/business', { token: owner.token });

    assert.equal(res.status, 200);
    assert.equal(res.body.business.logoUrl, null);
  });

  test('stores a logo image with the profile and returns it', async () => {
    const { session } = await createUser();
    const res = await api('POST', '/business', {
      token: session.access_token,
      body: {
        business_name: 'Marked Store',
        business_category: 'Groceries',
        business_description: 'We sell provisions.',
        phone: uniquePhone(),
        logo_url: PNG,
      },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.business.logoUrl, PNG);
  });

  test('updates and clears the logo', async () => {
    const owner = await createBusinessOwner('Swapping Store');

    const saved = await api('PATCH', '/business', {
      token: owner.token,
      body: { logo_url: PNG },
    });
    assert.equal(saved.status, 200);
    assert.equal(saved.body.business.logoUrl, PNG);

    const cleared = await api('PATCH', '/business', {
      token: owner.token,
      body: { logo_url: null },
    });
    assert.equal(cleared.status, 200);
    assert.equal(cleared.body.business.logoUrl, null);
  });

  test('refuses a logo that is not an image data URL', async () => {
    const owner = await createBusinessOwner('Text Logo');
    const res = await api('PATCH', '/business', {
      token: owner.token,
      body: { logo_url: 'https://example.com/logo.png' },
    });

    assert.equal(res.status, 422);
    assert.ok(res.body.error.details.some((d) => d.field === 'logo_url'));
  });
});

describe('phase 2 — business location', () => {
  test('starts empty, then saves a manual address', async () => {
    const owner = await createBusinessOwner('Located Store');

    const before = await api('GET', '/business/location', { token: owner.token });
    assert.equal(before.status, 200);
    assert.equal(before.body.location, null);

    const res = await api('PUT', '/business/location', {
      token: owner.token,
      body: { address: '12 Allen Avenue', area: 'Allen Hill', city: 'Ikeja', state: 'Lagos', country: 'Nigeria' },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.location.address, '12 Allen Avenue');
    assert.equal(res.body.location.area, 'Allen Hill', 'the area the shop sits in travels with the address');
    assert.equal(res.body.location.city, 'Ikeja');
    assert.equal(res.body.location.state, 'Lagos');
    assert.equal(res.body.location.latitude, null);
  });

  test('the write also returns the refreshed business so the client can cache it', async () => {
    // The Flutter client adopts `business` from every write (it throws
    // malformed_response otherwise), so a location save has to carry it too.
    const owner = await createBusinessOwner('Contract Store');
    const res = await api('PUT', '/business/location', {
      token: owner.token,
      body: { address: '22 Awolowo Road', city: 'Ikoyi', latitude: 6.4541, longitude: 3.4347 },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.business.businessName, 'Contract Store');
    assert.equal(res.body.business.location.address, '22 Awolowo Road');
    assert.equal(res.body.business.location.latitude, 6.4541);
    // Top-level location stays for the location screen itself.
    assert.equal(res.body.location.address, '22 Awolowo Road');
  });

  test('stores coordinates when the device supplied them', async () => {
    const owner = await createBusinessOwner('GPS Store');
    const res = await api('PUT', '/business/location', {
      token: owner.token,
      body: { address: 'Plot 5, Guzape', latitude: 9.0579, longitude: 7.4895 },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.location.latitude, 9.0579);
    assert.equal(res.body.location.longitude, 7.4895);
  });

  test('refuses half a coordinate pair', async () => {
    const owner = await createBusinessOwner('Half GPS');
    const res = await api('PUT', '/business/location', {
      token: owner.token,
      body: { address: 'Somewhere', latitude: 9.05 },
    });

    assert.equal(res.status, 422);
  });

  test('rejects out-of-range coordinates', async () => {
    const owner = await createBusinessOwner('Bad GPS');
    const res = await api('PUT', '/business/location', {
      token: owner.token,
      body: { address: 'Somewhere', latitude: 120, longitude: 7.4 },
    });

    assert.equal(res.status, 422);
  });

  test('updating the location replaces the previous one instead of duplicating', async () => {
    const owner = await createBusinessOwner('Moving Store');
    await api('PUT', '/business/location', {
      token: owner.token,
      body: { address: 'Old Address' },
    });
    const res = await api('PUT', '/business/location', {
      token: owner.token,
      body: { address: 'New Address', city: 'Yaba', area: 'Akoka' },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.location.address, 'New Address');

    const read = await api('GET', '/business/location', { token: owner.token });
    assert.equal(read.body.location.city, 'Yaba');
    assert.equal(read.body.location.area, 'Akoka', 'the area is replaced with the rest of the address');
  });

  test('rejects an empty address', async () => {
    const owner = await createBusinessOwner('Addressless');
    const res = await api('PUT', '/business/location', {
      token: owner.token,
      body: { address: '  ' },
    });

    assert.equal(res.status, 422);
    assert.ok(res.body.error.details.some((d) => d.field === 'address'));
  });

  test('one owner cannot read another owner\'s location', async () => {
    const owner = await createBusinessOwner('Private Store');
    const intruder = await createBusinessOwner('Nosy Store');
    const saved = await api('PUT', '/business/location', {
      token: owner.token,
      body: { address: 'Secret Address' },
    });
    const locationId = saved.body.location.id;

    const res = await api('GET', '/business/location', { token: intruder.token });
    assert.equal(res.body.location, null);

    // There is no route that accepts a location id, so the id cannot be replayed.
    const replay = await api('GET', `/business/location/${locationId}`, { token: intruder.token });
    assert.equal(replay.status, 404);
  });
});
