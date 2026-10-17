import test, { describe } from 'node:test';
import assert from 'node:assert/strict';
import { api, createBusinessOwner, createUser } from './helpers.js';

async function addProduct(owner, overrides = {}) {
  const res = await api('POST', '/products', {
    token: owner.token,
    body: {
      name: 'Indomie 50 packs',
      category: 'Noodles',
      price_kobo: 1500000,
      stock_quantity: 20,
      ...overrides,
    },
  });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.product;
}

describe('phase 3 — product catalog', () => {
  test('adds a product and returns money in kobo', async () => {
    const owner = await createBusinessOwner('Noodle Store');
    const product = await addProduct(owner);

    assert.equal(product.name, 'Indomie 50 packs');
    assert.equal(product.priceKobo, 1500000);
    assert.equal(product.stockQuantity, 20);
    assert.equal(product.active, true);
  });

  test('accepts a readable price and normalises it to kobo', async () => {
    const owner = await createBusinessOwner('Readable Prices');
    const res = await api('POST', '/products', {
      token: owner.token,
      body: { name: 'Rice 50kg', price_kobo: '25000.50' },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.product.priceKobo, 2500050);
  });

  test('rejects a price with sub-cent precision', async () => {
    const owner = await createBusinessOwner('Sloppy Prices');
    const res = await api('POST', '/products', {
      token: owner.token,
      body: { name: 'Broken Price', price_kobo: '100.005' },
    });

    assert.equal(res.status, 422);
    assert.ok(res.body.error.details.some((d) => d.field === 'price_kobo'));
  });

  test('stores a product photo given as an image data URL', async () => {
    const owner = await createBusinessOwner('Photo Store');
    const png =
      'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP478oAAAOLAUV+7IS+AAAAAElFTkSuQmCC';

    const created = await api('POST', '/products', {
      token: owner.token,
      body: { name: 'Photo Rice', price_kobo: 100, image_url: png },
    });
    assert.equal(created.status, 201);
    assert.equal(created.body.product.imageUrl, png);

    const patched = await api('PATCH', `/products/${created.body.product.id}`, {
      token: owner.token,
      body: { image_url: png },
    });
    assert.equal(patched.status, 200);
    assert.equal(patched.body.product.imageUrl, png);
  });

  test('refuses a product photo that is not an image data URL', async () => {
    const owner = await createBusinessOwner('Bad Photo Store');
    const res = await api('POST', '/products', {
      token: owner.token,
      body: {
        name: 'Bad Photo',
        price_kobo: 100,
        image_url: 'https://example.com/photo.png',
      },
    });

    assert.equal(res.status, 422);
    assert.ok(res.body.error.details.some((d) => d.field === 'image_url'));
  });

  test('rejects a negative price and a fractional quantity', async () => {
    const owner = await createBusinessOwner('Bad Numbers');

    const negative = await api('POST', '/products', {
      token: owner.token,
      body: { name: 'Negative', price_kobo: -100 },
    });
    assert.equal(negative.status, 422);

    const fractional = await api('POST', '/products', {
      token: owner.token,
      body: { name: 'Fractional', price_kobo: 100, stock_quantity: 2.5 },
    });
    assert.equal(fractional.status, 422);
  });

  test('requires a name', async () => {
    const owner = await createBusinessOwner('Nameless');
    const res = await api('POST', '/products', {
      token: owner.token,
      body: { price_kobo: 5000 },
    });

    assert.equal(res.status, 422);
    assert.ok(res.body.error.details.some((d) => d.field === 'name'));
  });

  test('searches by name and by SKU', async () => {
    const owner = await createBusinessOwner('Search Store');
    await addProduct(owner, { name: 'Indomie 50 packs', sku: 'IND-50' });
    await addProduct(owner, { name: 'Gari 2kg', sku: 'GAR-2', category: 'Swallow' });

    const byName = await api('GET', '/products?search=indomie', { token: owner.token });
    assert.equal(byName.body.products.length, 1);
    assert.equal(byName.body.products[0].name, 'Indomie 50 packs');

    const bySku = await api('GET', '/products?search=GAR-2', { token: owner.token });
    assert.equal(bySku.body.products.length, 1);
    assert.equal(bySku.body.products[0].name, 'Gari 2kg');
  });

  test('filters by category and lists the categories in use', async () => {
    const owner = await createBusinessOwner('Category Store');
    await addProduct(owner, { name: 'Indomie 50 packs', category: 'Noodles' });
    await addProduct(owner, { name: 'Gari 2kg', category: 'Swallow' });
    await addProduct(owner, { name: 'Vegetable Oil', category: 'Swallow' });

    const filtered = await api('GET', '/products?category=Swallow', { token: owner.token });
    assert.equal(filtered.body.products.length, 2);

    const categories = await api('GET', '/products/categories', { token: owner.token });
    assert.deepEqual(categories.body.categories, ['Noodles', 'Swallow']);
  });

  test('archives a product and hides it by default', async () => {
    const owner = await createBusinessOwner('Archiving Store');
    const product = await addProduct(owner, { name: 'Seasonal Gift Box' });

    const archived = await api(`POST`, `/products/${product.id}/archive`, { token: owner.token });
    assert.equal(archived.status, 200);
    assert.equal(archived.body.product.active, false);

    const visible = await api('GET', '/products', { token: owner.token });
    assert.equal(visible.body.products.length, 0);

    const withArchived = await api('GET', '/products?include_archived=true', { token: owner.token });
    assert.equal(withArchived.body.products.length, 1);
  });

  test('restores an archived product', async () => {
    const owner = await createBusinessOwner('Restoring Store');
    const product = await addProduct(owner, { name: 'Back In Stock' });
    await api('POST', `/products/${product.id}/archive`, { token: owner.token });

    const res = await api('POST', `/products/${product.id}/restore`, { token: owner.token });
    assert.equal(res.status, 200);
    assert.equal(res.body.product.active, true);
  });

  test('updates price and stock', async () => {
    const owner = await createBusinessOwner('Updating Store');
    const product = await addProduct(owner);

    const res = await api('PATCH', `/products/${product.id}`, {
      token: owner.token,
      body: { price_kobo: '1750.25', stock_quantity: 5 },
    });

    assert.equal(res.status, 200);
    // "1750.25" is naira typed by a human: ₦1,750.25 is 175025 kobo.
    assert.equal(res.body.product.priceKobo, 175025);
    assert.equal(res.body.product.stockQuantity, 5);
  });

  test('refuses a duplicate SKU inside the same business', async () => {
    const owner = await createBusinessOwner('Sku Store');
    await addProduct(owner, { name: 'First', sku: 'DUP-1' });

    const res = await api('POST', '/products', {
      token: owner.token,
      body: { name: 'Second', price_kobo: 100, sku: 'DUP-1' },
    });

    assert.equal(res.status, 409);
    assert.equal(res.body.error.code, 'sku_taken');
  });

  test('the same SKU is allowed in a different business', async () => {
    const first = await createBusinessOwner('First Business');
    const second = await createBusinessOwner('Second Business');
    await addProduct(first, { name: 'First', sku: 'SHARED-1' });

    const res = await api('POST', '/products', {
      token: second.token,
      body: { name: 'Second', price_kobo: 100, sku: 'SHARED-1' },
    });

    assert.equal(res.status, 201);
  });

  test('one business cannot see or edit another business\'s product', async () => {
    const owner = await createBusinessOwner('Real Store');
    const intruder = await createBusinessOwner('Thief Store');
    const product = await addProduct(owner, { name: 'Secret Item' });

    const list = await api('GET', '/products', { token: intruder.token });
    assert.equal(list.body.products.length, 0);

    const read = await api('GET', `/products/${product.id}`, { token: intruder.token });
    assert.equal(read.status, 404);

    const write = await api('PATCH', `/products/${product.id}`, {
      token: intruder.token,
      body: { price_kobo: 1 },
    });
    assert.equal(write.status, 404);

    const remove = await api('DELETE', `/products/${product.id}`, { token: intruder.token });
    assert.equal(remove.status, 404);

    const archive = await api('POST', `/products/${product.id}/archive`, { token: intruder.token });
    assert.equal(archive.status, 404);
  });

  test('requires a business profile before touching the catalog', async () => {
    const { session } = await createUser();
    const res = await api('GET', '/products', { token: session.access_token });
    assert.equal(res.status, 404);
  });
});
