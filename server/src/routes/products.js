import express from 'express';
import crypto from 'node:crypto';
import { queryOne, queryAll, run } from '../db/index.js';
import { requireAuth } from '../middleware/auth.js';
import { requireBusiness, requireOwner } from '../middleware/business.js';
import { conflict, notFound, validationFailed, badRequest } from '../lib/errors.js';
import {
  DIGITAL_FILE_MAX_BYTES,
  productCreateSchema,
  productUpdateSchema,
  productRestockSchema,
  productListQuerySchema,
  toFieldErrors,
} from '../lib/validators.js';
import {
  actorDisplayName,
  safeAddAppNotification,
  syncLowStockNotifications,
} from '../lib/notifications.js';

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
    // Digital listings carry the asset the buyer will receive. The file bytes
    // stay out of this payload; the public delivery page streams them.
    kind: row.kind ?? 'physical',
    digitalUrl: row.digital_url ?? null,
    digitalInstructions: row.digital_instructions ?? null,
    digitalFileName: row.digital_file_name ?? null,
    hasDigitalFile: Boolean(row.digital_file_id),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

// One product projection everywhere, so the file name shown on the form is
// available without a second lookup per row.
const PRODUCT_SELECT = `
  SELECT p.*, df.file_name AS digital_file_name
    FROM products p
    LEFT JOIN digital_files df ON df.id = p.digital_file_id`;

async function findOwnedProduct(businessId, productId) {
  const row = await queryOne(
    `${PRODUCT_SELECT} WHERE p.id = ? AND p.business_id = ?`,
    productId,
    businessId
  );
  // Scoping the lookup by business_id is what stops one business reading
  // another's catalog by guessing a product id.
  if (!row) throw notFound('That product does not exist.');
  return row;
}

/**
 * Decodes an uploaded digital asset and enforces the cap on its real size.
 * Base64 inflates by ~4/3, so checking the string length alone would let a
 * file that decodes past the limit through.
 */
function decodeDigitalFile(file) {
  const data = file.data_base64;
  const bytes = Buffer.from(data, 'base64');
  if (bytes.length === 0) {
    throw validationFailed([
      { field: 'digital_file', message: 'The file has no content.' },
    ]);
  }
  if (bytes.length > DIGITAL_FILE_MAX_BYTES) {
    throw validationFailed([
      { field: 'digital_file', message: 'The file is larger than 6 MB.' },
    ]);
  }
  return { data, bytes: bytes.length };
}

async function storeDigitalFile(businessId, file) {
  const decoded = decodeDigitalFile(file);
  const id = crypto.randomUUID();
  await run(
    `INSERT INTO digital_files
       (id, business_id, file_name, mime_type, size_bytes, data_base64)
     VALUES (?, ?, ?, ?, ?, ?)`,
    id,
    businessId,
    file.file_name,
    file.mime_type || 'application/octet-stream',
    decoded.bytes,
    decoded.data
  );
  return id;
}

/**
 * Deletes an orphaned upload. A file still referenced by a product (the current
 * asset) or by a transaction item (a past buyer's snapshot) must survive, so
 * replacing a product file never destroys what someone already bought.
 */
async function pruneDigitalFile(fileId) {
  if (!fileId) return;
  const product = await queryOne(
    'SELECT id FROM products WHERE digital_file_id = ? LIMIT 1',
    fileId
  );
  if (product) return;
  const item = await queryOne(
    'SELECT id FROM transaction_items WHERE digital_file_id = ? LIMIT 1',
    fileId
  );
  if (item) return;
  await run('DELETE FROM digital_files WHERE id = ?', fileId);
}

function assertDigitalAsset(kind, digitalUrl, digitalFileId, path = 'digital_url') {
  if (kind !== 'digital') return;
  if (digitalUrl || digitalFileId) return;
  throw validationFailed([
    {
      field: path,
      message: 'Add a download link, upload a file, or both.',
    },
  ]);
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
  const where = ['p.business_id = ?'];
  const params = [req.business.id];

  if (!query.include_archived) where.push('p.active = 1');
  if (query.search) {
    where.push('(p.name ILIKE ? OR COALESCE(p.sku, \'\') ILIKE ?)');
    const like = `%${query.search}%`;
    params.push(like, like);
  }
  if (query.category) {
    where.push('p.category = ?');
    params.push(query.category);
  }

  const rows = await queryAll(
    `${PRODUCT_SELECT} WHERE ${where.join(' AND ')}
      ORDER BY p.active DESC, lower(p.name) ASC`,
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

  const kind = body.kind ?? 'physical';
  const digitalFileId = body.digital_file
    ? await storeDigitalFile(req.business.id, body.digital_file)
    : null;
  const digitalUrl = kind === 'digital' ? body.digital_url ?? null : null;
  assertDigitalAsset(kind, digitalUrl, digitalFileId);

  const id = crypto.randomUUID();
  await run(
    `INSERT INTO products (id, business_id, name, description, category,
                           price_kobo, sku, stock_quantity, image_url, kind,
                           digital_url, digital_instructions, digital_file_id)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    id,
    req.business.id,
    body.name,
    body.description ?? null,
    body.category ?? null,
    body.price_kobo,
    body.sku ?? null,
    // Digital stock is unlimited by design; keeping the column at zero also
    // keeps it out of the shelf warning.
    kind === 'digital' ? 0 : body.stock_quantity,
    body.image_url ?? null,
    kind,
    digitalUrl,
    kind === 'digital' ? body.digital_instructions ?? null : null,
    digitalFileId
  );
  // A product created already below the line is an alert from its first day.
  await syncLowStockNotifications(req.business.id);
  res.status(201).json({ product: publicProduct(await findOwnedProduct(req.business.id, id)) });
});

productRouter.get('/:id', async (req, res) => {
  res.json({ product: publicProduct(await findOwnedProduct(req.business.id, req.params.id)) });
});

productRouter.patch('/:id', requireOwner, async (req, res) => {
  const existing = await findOwnedProduct(req.business.id, req.params.id);
  const body = parse(productUpdateSchema, req.body);
  if (body.sku !== undefined) await assertSkuAvailable(req.business.id, body.sku, existing.id);

  const kind = body.kind ?? existing.kind ?? 'physical';

  // A new upload replaces the current asset; clearing removes it; otherwise the
  // existing file stays. The old upload is pruned only after the row no longer
  // points at it and no past buyer's snapshot needs it. Switching to physical
  // discards any asset, because a shelf product has nothing to download.
  let previousFileId = null;
  let digitalFileId = existing.digital_file_id ?? null;
  if (kind === 'digital') {
    if (body.digital_file) {
      previousFileId = digitalFileId;
      digitalFileId = await storeDigitalFile(req.business.id, body.digital_file);
    } else if (body.clear_digital_file) {
      previousFileId = digitalFileId;
      digitalFileId = null;
    }
  } else if (digitalFileId) {
    previousFileId = digitalFileId;
    digitalFileId = null;
  }

  const digitalUrl = kind === 'digital'
    ? (body.digital_url !== undefined ? body.digital_url : existing.digital_url ?? null)
    : null;
  const digitalInstructions = kind === 'digital'
    ? (body.digital_instructions !== undefined
        ? body.digital_instructions
        : existing.digital_instructions ?? null)
    : null;
  assertDigitalAsset(kind, digitalUrl, digitalFileId);

  const updates = {
    kind,
    digital_url: digitalUrl,
    digital_instructions: digitalInstructions,
    digital_file_id: digitalFileId,
  };
  const simpleColumns = ['name', 'description', 'category', 'price_kobo', 'sku', 'image_url'];
  for (const key of simpleColumns) {
    if (body[key] !== undefined) updates[key] = body[key];
  }
  if (kind === 'digital') {
    // A digital listing never has a shelf count, even if the client sent one.
    updates.stock_quantity = 0;
  } else if (body.stock_quantity !== undefined) {
    updates.stock_quantity = body.stock_quantity;
  }

  const assignments = [];
  const values = [];
  for (const [column, value] of Object.entries(updates)) {
    assignments.push(`${column} = ?`);
    values.push(value);
  }
  assignments.push('updated_at = ?');
  values.push(new Date().toISOString(), existing.id);
  await run(`UPDATE products SET ${assignments.join(', ')} WHERE id = ?`, ...values);
  // Restocking clears the open alert; dropping below the line raises one.
  await syncLowStockNotifications(req.business.id);
  if (previousFileId && previousFileId !== digitalFileId) {
    await pruneDigitalFile(previousFileId);
  }

  res.json({ product: publicProduct(await findOwnedProduct(req.business.id, existing.id)) });
});

/**
 * Restock adds units to the shelf. The owner types how many arrived, not a new
 * total, so the server does the arithmetic and a product at 40 becoming "add 12"
 * ends at 52 without the owner having to remember the old figure.
 *
 * The increment happens in one UPDATE, so two restocks racing each other both
 * land instead of one overwriting the other.
 */
productRouter.post('/:id/restock', requireOwner, async (req, res) => {
  const body = parse(productRestockSchema, req.body);
  const existing = await findOwnedProduct(req.business.id, req.params.id);
  if ((existing.kind ?? 'physical') === 'digital') {
    throw badRequest('Digital products have unlimited stock, so there is nothing to restock.');
  }

  await run(
    `UPDATE products
        SET stock_quantity = stock_quantity + ?, updated_at = ?
      WHERE id = ?`,
    body.quantity,
    new Date().toISOString(),
    existing.id
  );
  // More stock usually clears the warning; the sync decides that from the new
  // figure rather than the client guessing.
  await syncLowStockNotifications(req.business.id);
  const updated = await findOwnedProduct(req.business.id, existing.id);
  const actorName = await actorDisplayName(req.auth.userId);
  await safeAddAppNotification({
    businessId: req.business.id,
    productId: updated.id,
    actorUserId: req.auth.userId,
    type: 'restock',
    title: `Restocked ${updated.name}`,
    message:
      `${body.quantity} ${body.quantity === 1 ? 'unit' : 'units'} added${actorName ? ` by ${actorName}` : ''} · ` +
      `${updated.stock_quantity} now in stock`,
    severity: 'success',
  });
  res.json({ product: publicProduct(updated) });
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
  // An archived product is not on the shelf, so it should not keep shouting.
  await syncLowStockNotifications(req.business.id);
  res.json({ product: publicProduct(await findOwnedProduct(req.business.id, existing.id)) });
});

productRouter.post('/:id/restore', requireOwner, async (req, res) => {
  const existing = await findOwnedProduct(req.business.id, req.params.id);
  await run(
    'UPDATE products SET active = 1, updated_at = ? WHERE id = ?',
    new Date().toISOString(),
    existing.id
  );
  // Restoring a low product puts it back on the shelf and back on the alert.
  await syncLowStockNotifications(req.business.id);
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
  if (existing.digital_file_id) await pruneDigitalFile(existing.digital_file_id);
  await syncLowStockNotifications(req.business.id);
  res.json({ status: 'success' });
});
