import express from 'express';
import crypto from 'node:crypto';
import { queryOne, queryAll, run } from '../db/index.js';
import { requireAuth } from '../middleware/auth.js';
import { requireBusiness } from '../middleware/business.js';
import { badRequest, notFound } from '../lib/errors.js';
import { config } from '../config.js';

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
  extracted.items = await matchCatalogItems(req.business.id, extracted.items || []);

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

function parseGeminiJson(text) {
  if (!text) return null;
  let cleaned = text.trim();
  // Strip markdown code fences if present
  cleaned = cleaned.replace(/^```json\s*/i, '').replace(/^```\s*/i, '').replace(/\s*```$/i, '');
  try {
    return JSON.parse(cleaned);
  } catch (err) {
    // Try to extract JSON object
    const match = cleaned.match(/\{[\s\S]*\}/);
    if (match) {
      try {
        return JSON.parse(match[0]);
      } catch {
        return null;
      }
    }
    return null;
  }
}

function toKoboFromPrice(price) {
  if (price === null || price === undefined || price === '') return null;
  if (typeof price === 'number') {
    // Assume naira value if reasonable, or already in kobo - better treat as naira-like decimal? But our schema uses kobo in DB
    // Try to detect: if small (e.g., 500) likely naira? Or just store as number * 100 if it's a simple decimal
    // Default: treat as naira and convert to kobo
    return Math.round(price * 100);
  }
  const str = String(price).replace(/[^0-9.]/g, '');
  if (!str) return null;
  const num = Number.parseFloat(str);
  if (Number.isNaN(num)) return null;
  return Math.round(num * 100);
}

const EMPTY_EXTRACTION = {
  customerName: null,
  customerPhone: null,
  items: [],
  deliveryRequired: false,
  deliveryAddress: null,
  deliveryFeeKobo: null,
  discountKobo: 0,
  totalKobo: null,
  notes: null,
};

const EXTRACTION_PROMPT = `You are an expert at reading Nigerian order screenshots: WhatsApp chats, receipts, invoices and handwritten order slips.

Return STRICTLY VALID JSON only. No markdown, no code fences, no commentary.

{
  "customerName": "string or null",
  "phoneNumber": "string or null",
  "deliveryAddress": "string or null",
  "wantsDelivery": true or false,
  "discount": number or null,
  "items": [
    { "name": "string", "quantity": 1, "price": number or null }
  ],
  "totalAmount": number or null
}

Rules:
- customerName: the buyer's name ("Mr Ben", "Chinedu", etc.). Never the shop name.
- phoneNumber: any Nigerian phone number, keep every digit (e.g. "08037311300").
- deliveryAddress: only a real street/area/city address. If the text only says delivery is wanted, leave null and set wantsDelivery true.
- wantsDelivery: true whenever the order mentions delivery, dispatch, rider, "send am", "bring it", "wants delivery", or gives an address.
- discount: the discount amount in naira if the order mentions one ("Discount of 2000" -> 2000). Otherwise null.
- items: every product mentioned. "2 adidas" -> name "adidas", quantity 2. Quantity defaults to 1. price is the unit price ONLY when a price is actually written; if no price appears use null, never 0.
- totalAmount: the final total in naira only when written. Otherwise null.
- Never invent values. Use null for anything not visible.`;

async function callGeminiRest(apiKey, model, imageDataUrl) {
  const mimeType = imageDataUrl.startsWith('data:image/png')
    ? 'image/png'
    : imageDataUrl.startsWith('data:image/webp')
      ? 'image/webp'
      : 'image/jpeg';
  const data = imageDataUrl.includes(',') ? imageDataUrl.split(',')[1] : imageDataUrl;
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [
        {
          role: 'user',
          parts: [{ text: EXTRACTION_PROMPT }, { inlineData: { mimeType, data } }],
        },
      ],
      generationConfig: { temperature: 0, responseMimeType: 'application/json' },
    }),
    signal: AbortSignal.timeout(45000),
  });
  const text = await res.text();
  let payload;
  try {
    payload = JSON.parse(text);
  } catch {
    throw new Error(`Gemini returned non-JSON (${res.status})`);
  }
  if (!res.ok || payload.error) {
    const err = new Error(payload?.error?.message || `Gemini HTTP ${res.status}`);
    err.status = res.status;
    throw err;
  }
  return (payload.candidates?.[0]?.content?.parts || [])
    .map((p) => p.text)
    .join('');
}

async function extractOrderFromImage(imageData) {
  const apiKey = config.integrations?.gemini?.apiKey || process.env.GEMINI_API_KEY;
  if (!apiKey) {
    console.warn('GEMINI_API_KEY is not set; screenshot extraction is disabled.');
    return EMPTY_EXTRACTION;
  }

  // Newer models are retired for new keys without notice, so try a chain.
  const configured = config.integrations?.gemini?.model;
  const models = [
    configured,
    'gemini-3.5-flash',
    'gemini-3.6-flash',
    'gemini-3.7-flash',
    'gemini-3.8-flash',
    'gemini-flash-latest',
  ].filter((m, i, all) => m && all.indexOf(m) === i);

  let lastError = null;
  for (const model of models) {
    try {
      const text = await callGeminiRest(apiKey, model, imageData);
      const parsed = parseGeminiJson(text);
      if (!parsed) {
        lastError = new Error(`Gemini (${model}) returned unparsable JSON`);
        continue;
      }

      const items = Array.isArray(parsed.items)
        ? parsed.items
            .map((it) => ({
              name: it.name || it.productName || null,
              quantity: Number(it.quantity) || 1,
              unit_price_kobo: toKoboFromPrice(it.price),
              product_id: null,
            }))
            .filter((it) => it.name)
        : [];

      const wantsDelivery =
        parsed.wantsDelivery === true ||
        parsed.deliveryRequired === true ||
        !!parsed.deliveryAddress;

      return {
        customerName: parsed.customerName || null,
        customerPhone:
          parsed.phoneNumber || parsed.phone || parsed.customerPhone || null,
        items,
        deliveryRequired: wantsDelivery,
        deliveryAddress: parsed.deliveryAddress || null,
        deliveryFeeKobo: toKoboFromPrice(parsed.deliveryFee),
        discountKobo: toKoboFromPrice(parsed.discount) || 0,
        totalKobo: toKoboFromPrice(parsed.totalAmount),
        notes: parsed.notes || null,
      };
    } catch (e) {
      lastError = e;
      console.warn(`Gemini extraction with ${model} failed:`, e?.message || e);
    }
  }

  console.error('Gemini extraction failed for every model:', lastError?.message || lastError);
  return EMPTY_EXTRACTION;
}

/// Strips case, punctuation and spacing so "Adidas Sneakers" and "adidas
/// sneaker" compare as the same words.
function normalizeName(value) {
  return String(value ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function singular(word) {
  return word.length > 3 && word.endsWith('s') ? word.slice(0, -1) : word;
}

export function nameScore(extractedName, productName) {
  const a = normalizeName(extractedName);
  const b = normalizeName(productName);
  if (!a || !b) return 0;
  if (a === b) return 1;

  const aTokens = a.split(' ').map(singular);
  const bTokens = b.split(' ').map(singular);

  // Every extracted word appears in the product name ("adidas" -> "Adidas
  // Sneakers"), which is the common case for a chat order.
  const contained = aTokens.every((t) => bTokens.includes(t));
  if (contained) return 0.9;

  // The product name sits inside the extracted text.
  if (a.includes(b) || b.includes(a)) return 0.85;

  const overlap = aTokens.filter((t) => bTokens.includes(t)).length;
  const ratio = overlap / Math.max(aTokens.length, bTokens.length);
  return ratio >= 0.5 ? 0.5 + ratio / 2 : 0;
}

/// Matches extracted line items to the shop's own catalog so a known product
/// brings its real price instead of a guessed or missing one.
export async function matchCatalogItems(businessId, items) {
  if (!items.length) return items;

  const products = await queryAll(
    'SELECT id, name, price_kobo, image_url, stock_quantity FROM products WHERE business_id = ? AND active = 1',
    businessId
  );
  if (!products.length) {
    return items.map((it) => ({
      ...it,
      product_id: null,
      matched_name: null,
      matched_price_kobo: null,
      match_confidence: 0,
    }));
  }

  return items.map((item) => {
    let best = null;
    let bestScore = 0;
    for (const product of products) {
      const score = nameScore(item.name, product.name);
      if (score > bestScore) {
        bestScore = score;
        best = product;
      }
    }

    if (!best || bestScore < 0.6) {
      return {
        ...item,
        product_id: null,
        matched_name: null,
        matched_price_kobo: null,
        match_confidence: Number(bestScore.toFixed(2)),
      };
    }

    return {
      ...item,
      // The catalog is the source of truth for both the name and the price.
      name: best.name,
      product_id: best.id,
      matched_name: best.name,
      matched_price_kobo: best.price_kobo,
      unit_price_kobo: best.price_kobo,
      match_confidence: Number(bestScore.toFixed(2)),
      stock_quantity: best.stock_quantity,
    };
  });
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
    } else if (it.name) {
      // A line may arrive without a price when the screenshot did not show
      // one. Keep it so the owner can price it during review instead of losing
      // the product from the draft.
      const unitPriceKobo = Number(it.unit_price_kobo ?? it.unitPriceKobo ?? 0) || 0;
      const quantity = Number(it.quantity) || 1;
      resolvedItems.push({
        productId: null,
        name: it.name,
        imageUrl: null,
        unitPriceKobo,
        quantity,
        subtotalKobo: unitPriceKobo * quantity,
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
