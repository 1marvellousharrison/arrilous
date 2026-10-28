import express from 'express';
import crypto from 'node:crypto';
import { queryOne, queryAll, run } from '../db/index.js';
import { requireAuth } from '../middleware/auth.js';
import { requireBusiness } from '../middleware/business.js';
import { badRequest, notFound } from '../lib/errors.js';

export const aiRouter = express.Router();
aiRouter.use(requireAuth, requireBusiness);

function now() {
  return new Date().toISOString();
}

aiRouter.get('/chat', async (req, res) => {
  const messages = await queryAll(
    'SELECT * FROM ai_chat_messages WHERE business_id = ? ORDER BY created_at ASC LIMIT 200',
    req.business.id
  );
  res.json({
    messages: messages.map((m) => ({
      id: m.id,
      role: m.role,
      messageType: m.message_type,
      content: m.content,
      metadata: m.metadata_json ? JSON.parse(m.metadata_json) : null,
      orderImportId: m.order_import_id,
      createdAt: m.created_at,
    })),
  });
});

aiRouter.post('/import', async (req, res) => {
  const { imageDataUrl, imageUrl, source = 'screenshot' } = req.body || {};
  if (!imageDataUrl && !imageUrl) {
    throw badRequest('Upload an image to import an order.');
  }

  const importId = crypto.randomUUID();
  await run(
    'INSERT INTO order_imports (id, business_id, user_id, source, image_url, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, \'processing\', ?, ?)',
    importId,
    req.business.id,
    req.auth.userId,
    source,
    imageDataUrl || imageUrl,
    now(),
    now()
  );

  await run(
    'INSERT INTO ai_chat_messages (id, business_id, user_id, order_import_id, role, message_type, content, metadata_json, created_at) VALUES (?, ?, ?, ?, \'user\', \'image\', ?, ?, ?)',
    crypto.randomUUID(),
    req.business.id,
    req.auth.userId,
    importId,
    'Uploaded a screenshot/photo for order import',
    JSON.stringify({ image: imageDataUrl || imageUrl }),
    now()
  );

  const extracted = await extractOrderFromImage(imageDataUrl || imageUrl);

  const missingFields = [];
  if (!extracted.customerName && !extracted.customerPhone) {
    missingFields.push('customer_detail');
  }
  if (!extracted.items || extracted.items.length === 0) {
    missingFields.push('products');
  }
  if (extracted.deliveryRequired) {
    if (!extracted.deliveryFeeKobo || extracted.deliveryFeeKobo <= 0) {
      missingFields.push('delivery_fee');
    }
    if (!extracted.deliveryAddress) {
      missingFields.push('delivery_address');
    }
  }

  await run(
    'UPDATE order_imports SET status = ?, extracted_customer_name = ?, extracted_customer_phone = ?, items_json = ?, delivery_required = ?, delivery_address = ?, delivery_fee_kobo = ?, discount_kobo = ?, missing_fields_json = ?, updated_at = ? WHERE id = ?',
    missingFields.length > 0 ? 'review' : 'extracted',
    extracted.customerName || null,
    extracted.customerPhone || null,
    JSON.stringify(extracted.items || []),
    extracted.deliveryRequired ? 1 : 0,
    extracted.deliveryAddress || null,
    extracted.deliveryFeeKobo || null,
    extracted.discountKobo || 0,
    JSON.stringify(missingFields),
    now(),
    importId
  );

  const assistantMsg = missingFields.length > 0
    ? `I've extracted what I could from the image. Some required details are missing:\n- ${missingFields.map(f => missingFieldLabel(f)).join('\n- ')}\n\nI've created an incomplete order draft. Please provide the missing details to complete it.`
    : `I've extracted the order details from the image. Review and confirm to create the transaction.`;

  await run(
    'INSERT INTO ai_chat_messages (id, business_id, user_id, order_import_id, role, message_type, content, metadata_json, created_at) VALUES (?, ?, ?, ?, \'assistant\', \'order_draft\', ?, ?, ?)',
    crypto.randomUUID(),
    req.business.id,
    req.auth.userId,
    importId,
    assistantMsg,
    JSON.stringify({
      draft: extracted,
      missingFields,
      importId,
      incomplete: missingFields.length > 0,
    }),
    now()
  );

  if (missingFields.length > 0) {
    for (const field of missingFields) {
      const nid = crypto.randomUUID();
      await run(
        'INSERT INTO notifications (id, business_id, user_id, order_import_id, type, title, message, severity, created_at) VALUES (?, ?, ?, ?, \'order_import_incomplete\', ?, ?, \'warning\', ?)',
        nid,
        req.business.id,
        req.auth.userId,
        importId,
        'Incomplete order from image',
        `Missing required detail: ${missingFieldLabel(field)}. Order draft created but needs completion.`,
        now()
      );
    }
  }

  const imp = await queryOne('SELECT * FROM order_imports WHERE id = ?', importId);
  res.status(201).json({
    import: formatImport(imp),
    messages: await getRecentMessages(req.business.id),
  });
});

function missingFieldLabel(f) {
  switch (f) {
    case 'customer_detail': return 'Customer detail (name or phone number)';
    case 'products': return 'Product/amount details';
    case 'delivery_fee': return 'Delivery fee (required since delivery was mentioned)';
    case 'delivery_address': return 'Delivery address (required since delivery was mentioned)';
    default: return f;
  }
}

async function extractOrderFromImage(imageData) {
  return {
    customerName: null,
    customerPhone: null,
    items: [],
    deliveryRequired: false,
    deliveryAddress: null,
    deliveryFeeKobo: null,
    discountKobo: 0,
    notes: null,
  };
}

function formatImport(row) {
  return {
    id: row.id,
    source: row.source,
    status: row.status,
    customerName: row.extracted_customer_name,
    customerPhone: row.extracted_customer_phone,
    items: row.items_json ? JSON.parse(row.items_json) : [],
    deliveryRequired: !!row.delivery_required,
    deliveryAddress: row.delivery_address,
    deliveryFeeKobo: row.delivery_fee_kobo,
    discountKobo: row.discount_kobo,
    missingFields: row.missing_fields_json ? JSON.parse(row.missing_fields_json) : [],
    transactionId: row.transaction_id,
    createdAt: row.created_at,
  };
}

async function getRecentMessages(businessId) {
  const messages = await queryAll('SELECT * FROM ai_chat_messages WHERE business_id = ? ORDER BY created_at DESC LIMIT 50', businessId);
  return messages.reverse().map((m) => ({
    id: m.id,
    role: m.role,
    messageType: m.message_type,
    content: m.content,
    metadata: m.metadata_json ? JSON.parse(m.metadata_json) : null,
    orderImportId: m.order_import_id,
    createdAt: m.created_at,
  }));
}

aiRouter.get('/imports', async (req, res) => {
  const imports = await queryAll('SELECT * FROM order_imports WHERE business_id = ? ORDER BY created_at DESC', req.business.id);
  res.json({ imports: imports.map(formatImport) });
});

aiRouter.post('/imports/:id/complete', async (req, res) => {
  const imp = await queryOne('SELECT * FROM order_imports WHERE id = ? AND business_id = ?', req.params.id, req.business.id);
  if (!imp) throw notFound('Import not found');

  const { customer_id, customer_name, customer_phone, items, delivery_required, delivery_address, delivery_fee_kobo, discount_kobo = 0, notes } = req.body || {};

  if ((!customer_id && !customer_name && !customer_phone)) {
    throw badRequest('Customer detail (name or phone) is required.');
  }
  if (!items || items.length === 0) {
    throw badRequest('Product/amount details are required.');
  }
  if (delivery_required) {
    if (!delivery_fee_kobo || delivery_fee_kobo <= 0) {
      throw badRequest('Delivery fee is required when delivery is requested.');
    }
    if (!delivery_address) {
      throw badRequest('Delivery address is required when delivery is requested.');
    }
  }

  const businessId = req.business.id;
  let finalCustomerId = customer_id || null;

  if (!finalCustomerId && (customer_name || customer_phone)) {
    if (customer_phone) {
      const existing = await queryOne('SELECT id FROM customers WHERE business_id = ? AND phone = ?', businessId, customer_phone);
      if (existing) finalCustomerId = existing.id;
    }
    if (!finalCustomerId && customer_name) {
      const custId = crypto.randomUUID();
      await run(
        'INSERT INTO customers (id, business_id, name, phone, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        custId, businessId, customer_name, customer_phone || null, now(), now()
      );
      finalCustomerId = custId;
    }
  }

  const resolvedItems = [];
  for (const it of items) {
    if (it.product_id) {
      const product = await queryOne('SELECT * FROM products WHERE id = ? AND business_id = ?', it.product_id, businessId);
      if (product && product.active) {
        resolvedItems.push({
          productId: product.id,
          name: product.name,
          imageUrl: product.image_url,
          unitPriceKobo: product.price_kobo,
          quantity: it.quantity || 1,
          subtotalKobo: product.price_kobo * (it.quantity || 1),
        });
      }
    } else if (it.name && it.unit_price_kobo) {
      resolvedItems.push({
        productId: null,
        name: it.name,
        imageUrl: null,
        unitPriceKobo: it.unit_price_kobo,
        quantity: it.quantity || 1,
        subtotalKobo: it.unit_price_kobo * (it.quantity || 1),
      });
    }
  }

  if (resolvedItems.length === 0) throw badRequest('Valid items are required.');

  const subtotal = resolvedItems.reduce((s, i) => s + i.subtotalKobo, 0);
  const fee = delivery_required ? (delivery_fee_kobo || 0) : 0;
  const disc = discount_kobo || 0;
  if (disc > subtotal) throw badRequest('Discount cannot exceed subtotal.');
  const total = subtotal + fee - disc;

  const year = new Date().getUTCFullYear();
  const count = await queryOne('SELECT COUNT(*) AS total FROM transactions WHERE business_id = ?', businessId);
  const txnNumber = `TXN-${year}-${String((count?.total ?? 0) + 1).padStart(5, '0')}`;
  const txnId = crypto.randomUUID();

  await run(
    'INSERT INTO transactions (id, business_id, customer_id, transaction_number, source, subtotal_kobo, discount_kobo, delivery_fee_kobo, total_kobo, notes, delivery_address, created_by_user_id, created_at, updated_at) VALUES (?, ?, ?, ?, \'screenshot\', ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    txnId, businessId, finalCustomerId, txnNumber, subtotal, disc, fee, total, notes || null, delivery_address || null, req.auth.userId, now(), now()
  );

  for (const it of resolvedItems) {
    await run(
      'INSERT INTO transaction_items (id, transaction_id, product_id, product_name_snapshot, image_url, quantity, unit_price_kobo, subtotal_kobo, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      crypto.randomUUID(), txnId, it.productId, it.name, it.imageUrl, it.quantity, it.unitPriceKobo, it.subtotalKobo, now()
    );
  }

  await run(
    'INSERT INTO transaction_statuses (transaction_id, order_status, payment_status, delivery_status, completion_status) VALUES (?, \'pending\', \'unpaid\', ?, \'open\')',
    txnId, delivery_required ? 'pending' : 'not_required'
  );

  await run('UPDATE order_imports SET status = \'completed\', transaction_id = ?, updated_at = ? WHERE id = ?', txnId, now(), imp.id);

  await run(
    'INSERT INTO ai_chat_messages (id, business_id, user_id, order_import_id, role, message_type, content, metadata_json, created_at) VALUES (?, ?, ?, ?, \'assistant\', \'action\', ?, ?, ?)',
    crypto.randomUUID(), req.business.id, req.auth.userId, imp.id,
    'Order created from image import (incomplete details were filled in).',
    JSON.stringify({ transactionId: txnId, incomplete: false }),
    now()
  );

  res.json({ transactionId: txnId, message: 'Order created from import' });
});

export default aiRouter;
