import express from 'express';
import crypto from 'node:crypto';
import { queryOne, queryAll, run } from '../db/index.js';
import { requireAuth } from '../middleware/auth.js';
import { requireBusiness, requireOwner } from '../middleware/business.js';
import { conflict, notFound, validationFailed, badRequest } from '../lib/errors.js';
import {
  productCreateSchema,
  productUpdateSchema,
  productListQuerySchema,
  toFieldErrors,
} from '../lib/validators.js';

export const productRouter = express.Router();

function parse(schema, payload) {
  const result = schema.safeParse(payload ?? {});
  if (!result.success) throw validationFailed(toFieldErrors(result.error));
  return result.data;
}

export function publicProduct(row) {
  return {
    id: row.id,
    businessId: row.business_id,
    name: row.name,
    description: row.description,
    category: row.category,
    priceKobo: row.price_kobo,
    sku: row.sku,
    stockQuantity: row.stock_quantity,
    imageUrl: row.image_url,
    active: Boolean(row.active),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function findOwnedProduct(businessId, productId) {
  const row = await queryOne(
    'SELECT * FROM products WHERE id = ? AND business_id = ?',
    productId,
    businessId
  );
  // Scoping the lookup by business_id is what stops one business reading
  // another's catalog by guessing a product id.
  if (!row) throw notFound('That product does not exist.');
  return row;
}

async function assertSkuAvailable(businessId, sku, exceptId) {
  if (!sku) return;
  const clash = await queryOne(
    'SELECT id FROM products WHERE business_id = ? AND sku = ? AND id IS DISTINCT FROM ?',
    businessId,
    sku,
    exceptId ?? null
  );
  if (clash) throw conflict('Another product already uses this SKU.', 'sku_taken');
}

productRouter.use(requireAuth, requireBusiness);

// GET /api/v1/products — search + category filter, archived hidden by default.
productRouter.get('/', async (req, res) => {
  const query = parse(productListQuerySchema, req.query);
  const where = ['business_id = ?'];
  const params = [req.business.id];

  if (!query.include_archived) where.push('active = 1');
  if (query.search) {
    where.push('(name ILIKE ? OR COALESCE(sku, \'\') ILIKE ?)');
    const like = `%${query.search}%`;
    params.push(like, like);
  }
  if (query.category) {
    where.push('category = ?');
    params.push(query.category);
  }

  const rows = await queryAll(
    `SELECT * FROM products WHERE ${where.join(' AND ')}
      ORDER BY active DESC, lower(name) ASC`,
    ...params
  );
  res.json({ products: rows.map(publicProduct) });
});

productRouter.get('/categories', async (req, res) => {
  const rows = await queryAll(
    `SELECT DISTINCT category FROM products
      WHERE business_id = ? AND active = 1 AND category IS NOT NULL
      ORDER BY category ASC`,
    req.business.id
  );
  res.json({ categories: rows.map((row) => row.category) });
});

productRouter.post('/', requireOwner, async (req, res) => {
  const body = parse(productCreateSchema, req.body);
  await assertSkuAvailable(req.business.id, body.sku, null);

  const id = crypto.randomUUID();
  await run(
    `INSERT INTO products (id, business_id, name, description, category,
                           price_kobo, sku, stock_quantity, image_url)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    id,
    req.business.id,
    body.name,
    body.description ?? null,
    body.category ?? null,
    body.price_kobo,
    body.sku ?? null,
    body.stock_quantity,
    body.image_url ?? null
  );
  res.status(201).json({ product: publicProduct(await findOwnedProduct(req.business.id, id)) });
});

productRouter.get('/:id', async (req, res) => {
  res.json({ product: publicProduct(await findOwnedProduct(req.business.id, req.params.id)) });
});

productRouter.patch('/:id', requireOwner, async (req, res) => {
  const existing = await findOwnedProduct(req.business.id, req.params.id);
  const body = parse(productUpdateSchema, req.body);
  if (body.sku !== undefined) await assertSkuAvailable(req.business.id, body.sku, existing.id);

  const columns = {
    name: 'name',
    description: 'description',
    category: 'category',
    price_kobo: 'price_kobo',
    sku: 'sku',
    stock_quantity: 'stock_quantity',
    image_url: 'image_url',
  };

  const assignments = [];
  const values = [];
  for (const [key, column] of Object.entries(columns)) {
    if (body[key] !== undefined) {
      assignments.push(`${column} = ?`);
      values.push(body[key]);
    }
  }

  if (assignments.length > 0) {
    assignments.push('updated_at = ?');
    values.push(new Date().toISOString(), existing.id);
    await run(`UPDATE products SET ${assignments.join(', ')} WHERE id = ?`, ...values);
  }

  res.json({ product: publicProduct(await findOwnedProduct(req.business.id, existing.id)) });
});

// Archive rather than delete: transaction items reference this row, and Phase 3
// requires history to survive catalog changes.
productRouter.post('/:id/archive', requireOwner, async (req, res) => {
  const existing = await findOwnedProduct(req.business.id, req.params.id);
  await run(
    'UPDATE products SET active = 0, updated_at = ? WHERE id = ?',
    new Date().toISOString(),
    existing.id
  );
  res.json({ product: publicProduct(await findOwnedProduct(req.business.id, existing.id)) });
});

productRouter.post('/:id/restore', requireOwner, async (req, res) => {
  const existing = await findOwnedProduct(req.business.id, req.params.id);
  await run(
    'UPDATE products SET active = 1, updated_at = ? WHERE id = ?',
    new Date().toISOString(),
    existing.id
  );
  res.json({ product: publicProduct(await findOwnedProduct(req.business.id, existing.id)) });
});

productRouter.delete('/:id', requireOwner, async (req, res) => {
  const existing = await findOwnedProduct(req.business.id, req.params.id);
  const used = await queryOne(
    'SELECT id FROM transaction_items WHERE product_id = ? LIMIT 1',
    existing.id
  );
  if (used) {
    throw badRequest(
      'This product is used in past transactions, so it can only be archived.',
      [{ field: 'active', message: 'Archive it instead to keep the history.' }]
    );
  }
  await run('DELETE FROM products WHERE id = ?', existing.id);
  res.json({ status: 'success' });
});
