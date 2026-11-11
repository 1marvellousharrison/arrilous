import test, { describe } from 'node:test';
import assert from 'node:assert/strict';
import { api, baseUrl, createBusinessOwner, uniquePhone } from './helpers.js';

/**
 * Digital products (0025_digital_products.sql).
 *
 * A digital listing sells an asset — a pasted link, an uploaded file, or both.
 * It never has stock, never needs a delivery address, and its past buyers keep
 * the exact link/file that was on the product when they paid.
 */

const FILE_TEXT = 'the digital guide contents';
const FILE_BASE64 = Buffer.from(FILE_TEXT).toString('base64');

async function addProduct(owner, overrides = {}) {
  const res = await api('POST', '/products', {
    token: owner.token,
    body: {
      name: 'E-book',
      price_kobo: 500000,
      ...overrides,
    },
  });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.product;
}

async function createSale(owner, items, extra = {}) {
  const res = await api('POST', '/transactions', {
    token: owner.token,
    body: { items, ...extra },
  });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.transaction;
}

describe('digital products — catalog', () => {
  test('a link-only digital product has unlimited stock and no shelf warning', async () => {
    const owner = await createBusinessOwner('Digital Link Store');
    const product = await addProduct(owner, {
      kind: 'digital',
      digital_url: 'https://example.com/ebook',
      digital_instructions: 'Open the link and enter code ABC.',
      stock_quantity: 12,
    });

    assert.equal(product.kind, 'digital');
    assert.equal(product.stockQuantity, 0, 'digital stock is always unlimited');
    assert.equal(product.digitalUrl, 'https://example.com/ebook');
    assert.equal(product.digitalInstructions, 'Open the link and enter code ABC.');
    assert.equal(product.hasDigitalFile, false);

    const list = await api('GET', '/products', { token: owner.token });
    assert.equal(list.body.products[0].kind, 'digital');

    const dashboard = await api('GET', '/dashboard/summary', { token: owner.token });
    assert.equal(dashboard.body.lowStock.count, 0, 'digital lines never raise a stock alert');
  });

  test('an uploaded file is stored against the product', async () => {
    const owner = await createBusinessOwner('Digital File Store');
    const product = await addProduct(owner, {
      kind: 'digital',
      digital_file: {
        file_name: 'guide.txt',
        mime_type: 'text/plain',
        data_base64: FILE_BASE64,
      },
    });

    assert.equal(product.hasDigitalFile, true);
    assert.equal(product.digitalFileName, 'guide.txt');
    assert.equal(product.digitalUrl, null);
  });

  test('a digital product needs a link, a file, or both', async () => {
    const owner = await createBusinessOwner('Digital Empty Store');
    const res = await api('POST', '/products', {
      token: owner.token,
      body: { name: 'Nothing here', price_kobo: 1000, kind: 'digital' },
    });
    assert.equal(res.status, 422, JSON.stringify(res.body));
  });

  test('a digital product cannot be restocked', async () => {
    const owner = await createBusinessOwner('Digital Restock Store');
    const product = await addProduct(owner, {
      kind: 'digital',
      digital_url: 'https://example.com/asset',
    });
    const res = await api('POST', `/products/${product.id}/restock`, {
      token: owner.token,
      body: { quantity: 3 },
    });
    assert.equal(res.status, 400, JSON.stringify(res.body));
  });

  test('switching a digital product back to physical clears the asset', async () => {
    const owner = await createBusinessOwner('Digital Switch Store');
    const product = await addProduct(owner, {
      kind: 'digital',
      digital_url: 'https://example.com/asset',
      digital_file: {
        file_name: 'guide.txt',
        mime_type: 'text/plain',
        data_base64: FILE_BASE64,
      },
    });

    const res = await api('PATCH', `/products/${product.id}`, {
      token: owner.token,
      body: { kind: 'physical', stock_quantity: 4 },
    });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.product.kind, 'physical');
    assert.equal(res.body.product.digitalUrl, null);
    assert.equal(res.body.product.hasDigitalFile, false);
    assert.equal(res.body.product.stockQuantity, 4);
  });
});

describe('digital products — sales', () => {
  test('an all-digital cart ignores delivery and snapshots the asset', async () => {
    const owner = await createBusinessOwner('Digital Sale Store');
    const product = await addProduct(owner, {
      kind: 'digital',
      digital_url: 'https://example.com/v1',
    });

    const sale = await createSale(
      owner,
      [{ product_id: product.id, quantity: 1 }],
      { delivery_required: true, delivery_address: '1 Test Street' }
    );

    assert.equal(sale.deliveryRequired, false, 'digital goods are never delivered');
    assert.equal(sale.deliveryStatus, 'not_required');
    assert.equal(sale.deliveryAddress, null);
    assert.equal(sale.items[0].isDigital, true);
    assert.equal(sale.items[0].digitalUrl, 'https://example.com/v1');
    assert.ok(sale.publicToken, 'a digital sale gets a public page token');
    assert.ok(sale.publicUrl.includes(sale.publicToken));

    // Editing the product later must not rewrite what this buyer bought.
    await api('PATCH', `/products/${product.id}`, {
      token: owner.token,
      body: { digital_url: 'https://example.com/v2' },
    });
    const detail = await api('GET', `/transactions/${sale.id}`, { token: owner.token });
    assert.equal(detail.body.transaction.items[0].digitalUrl, 'https://example.com/v1');
  });

  test('a mixed cart only requires delivery for the physical line', async () => {
    const owner = await createBusinessOwner('Mixed Sale Store');
    const digital = await addProduct(owner, {
      kind: 'digital',
      digital_url: 'https://example.com/asset',
      name: 'Digital asset',
    });
    const physical = await addProduct(owner, {
      name: 'Cotton shirt',
      price_kobo: 100000,
      stock_quantity: 5,
    });

    const sale = await createSale(
      owner,
      [
        { product_id: digital.id, quantity: 1 },
        { product_id: physical.id, quantity: 1 },
      ],
      { delivery_required: true, delivery_address: '12 Market Road' }
    );

    assert.equal(sale.deliveryRequired, true);
    assert.equal(sale.deliveryStatus, 'pending');
    assert.equal(sale.deliveryAddress, '12 Market Road');
    assert.equal(sale.items.filter((item) => item.isDigital).length, 1);
  });

  test('an all-physical sale still requires an address when delivery is on', async () => {
    const owner = await createBusinessOwner('Physical Sale Store');
    const physical = await addProduct(owner, {
      name: 'Sneakers',
      price_kobo: 2500000,
      stock_quantity: 3,
    });

    const res = await api('POST', '/transactions', {
      token: owner.token,
      body: {
        delivery_required: true,
        items: [{ product_id: physical.id, quantity: 1 }],
      },
    });
    assert.equal(res.status, 400, JSON.stringify(res.body));
  });
});

describe('digital products — public delivery', () => {
  test('the page is gated on payment and the file downloads only after it is paid', async () => {
    const owner = await createBusinessOwner('Digital Public Store');
    const product = await addProduct(owner, {
      kind: 'digital',
      digital_url: 'https://example.com/paid-asset',
      digital_instructions: 'Use it wisely.',
      digital_file: {
        file_name: 'guide.txt',
        mime_type: 'text/plain',
        data_base64: FILE_BASE64,
      },
    });

    const sale = await createSale(owner, [{ product_id: product.id, quantity: 1 }]);

    let page = await fetch(sale.publicUrl);
    let html = await page.text();
    assert.equal(page.status, 200);
    assert.match(html, /not been confirmed/i);
    assert.doesNotMatch(html, /paid-asset/, 'an unpaid page never leaks the asset');

    await api('PATCH', `/transactions/${sale.id}/statuses`, {
      token: owner.token,
      body: { paymentStatus: 'paid' },
    });

    page = await fetch(sale.publicUrl);
    html = await page.text();
    assert.equal(page.status, 200);
    assert.match(html, /E-book/);
    assert.match(html, /https:\/\/example\.com\/paid-asset/);
    assert.match(html, /Use it wisely\./);

    const file = await fetch(`${sale.publicUrl}/items/${sale.items[0].id}/file`);
    assert.equal(file.status, 200);
    assert.equal(file.headers.get('content-type'), 'text/plain');
    assert.match(file.headers.get('content-disposition'), /guide\.txt/);
    assert.equal(await file.text(), FILE_TEXT);

    const unknown = await fetch(
      `${baseUrl()}/public/sales/not-a-real-token-000000000000`
    );
    assert.equal(unknown.status, 404);
  });

  test('an unpaid file request is refused even with the right token and item', async () => {
    const owner = await createBusinessOwner('Digital Gate Store');
    const product = await addProduct(owner, {
      kind: 'digital',
      digital_file: {
        file_name: 'guide.txt',
        mime_type: 'text/plain',
        data_base64: FILE_BASE64,
      },
    });
    const sale = await createSale(owner, [{ product_id: product.id, quantity: 1 }]);

    const file = await fetch(`${sale.publicUrl}/items/${sale.items[0].id}/file`);
    assert.equal(file.status, 404);
  });
});

describe('digital products — email delivery', () => {
  test('email is refused before payment and shares the public link after it', async () => {
    const owner = await createBusinessOwner('Digital Email Store');
    const customer = (
      await api('POST', '/customers', {
        token: owner.token,
        body: {
          name: 'Digital Buyer',
          phone: uniquePhone(),
          email: 'buyer@example.com',
        },
      })
    ).body.customer;
    const product = await addProduct(owner, {
      kind: 'digital',
      digital_url: 'https://example.com/asset',
    });
    const sale = await createSale(owner, [{ product_id: product.id, quantity: 1 }], {
      customer_id: customer.id,
    });

    const early = await api('POST', `/transactions/${sale.id}/deliver`, {
      token: owner.token,
    });
    assert.equal(early.status, 400, JSON.stringify(early.body));

    await api('PATCH', `/transactions/${sale.id}/statuses`, {
      token: owner.token,
      body: { paymentStatus: 'paid' },
    });

    const sent = await api('POST', `/transactions/${sale.id}/deliver`, {
      token: owner.token,
    });
    assert.equal(sent.status, 200, JSON.stringify(sent.body));
    assert.equal(sent.body.email, 'buyer@example.com');
    assert.equal(sent.body.emailSent, false, 'no provider is configured in tests');
    assert.ok(sent.body.publicUrl.includes(sale.publicToken));
    assert.match(sent.body.message, /public link/i);

    const detail = await api('GET', `/transactions/${sale.id}`, { token: owner.token });
    assert.equal(detail.body.transaction.digitalDeliveryEmail, 'buyer@example.com');
  });
});
