import test, { describe } from 'node:test';
import assert from 'node:assert/strict';
import { api, createBusinessOwner } from './helpers.js';
import { matchCatalogItems, nameScore } from '../src/routes/ai.js';

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

describe('screenshot import - catalog matching', () => {
  test('scores an extracted word against the product name', () => {
    assert.equal(nameScore('adidas', 'Adidas Sneakers'), 0.9);
    assert.equal(nameScore('Adidas Sneakers', 'Adidas Sneakers'), 1);
    assert.equal(nameScore('adidas sneaker', 'Adidas Sneakers'), 0.9);
    assert.equal(nameScore('cement bag', 'Adidas Sneakers'), 0);
    assert.equal(nameScore('', 'Adidas Sneakers'), 0);
  });

  test('fills the catalog price for a known product', async () => {
    const owner = await createBusinessOwner('Shoe Store');
    const product = await addProduct(owner);

    const [item] = await matchCatalogItems(owner.business.id, [
      { name: 'adidas', quantity: 2, unit_price_kobo: null },
    ]);

    assert.equal(item.product_id, product.id);
    assert.equal(item.name, 'Adidas Sneakers');
    assert.equal(item.unit_price_kobo, 2500000);
    assert.equal(item.matched_price_kobo, 2500000);
    assert.equal(item.quantity, 2);
    assert.ok(item.match_confidence >= 0.6);
  });

  test('leaves an unknown product unpriced for the owner to set', async () => {
    const owner = await createBusinessOwner('Unknown Store');
    await addProduct(owner);

    const [item] = await matchCatalogItems(owner.business.id, [
      { name: 'cement bag', quantity: 1, unit_price_kobo: null },
    ]);

    assert.equal(item.product_id, null);
    assert.equal(item.unit_price_kobo, null);
    assert.equal(item.matched_price_kobo, null);
    assert.equal(item.match_confidence, 0);
  });

  test('never matches a product from another business', async () => {
    const owner = await createBusinessOwner('Mine');
    const other = await createBusinessOwner('Theirs');
    await addProduct(other);

    const [item] = await matchCatalogItems(owner.business.id, [
      { name: 'adidas', quantity: 1, unit_price_kobo: null },
    ]);

    assert.equal(item.product_id, null);
  });
});
