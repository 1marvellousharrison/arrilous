import express from 'express';
import crypto from 'node:crypto';
import { queryOne, queryAll, run, transaction } from '../db/index.js';
import { requireAuth } from '../middleware/auth.js';
import { requireBusiness } from '../middleware/business.js';
import { badRequest, notFound } from '../lib/errors.js';
import { recordCreation } from '../lib/history.js';
import { addAppNotification } from '../lib/notifications.js';
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
  const image = imageDataUrl || imageUrl;
  if (!image) {
    throw badRequest('Upload an image to import an order.');
  }

  // Re-uploading the same picture while its draft is still open used to create
  // a second draft (and a second extraction). Keep one draft per image for a
  // short window so a retry after a timeout is harmless.
  const since = new Date(Date.now() - 15 * 60 * 1000).toISOString();
  const duplicate = await queryOne(
    `SELECT oi.*, t.transaction_number
       FROM order_imports oi
       LEFT JOIN transactions t ON t.id = oi.transaction_id
      WHERE oi.business_id = ? AND oi.image_url = ?
        AND oi.status IN ('processing', 'extracted', 'review')
        AND oi.created_at >= ?
      ORDER BY oi.created_at DESC LIMIT 1`,
    req.business.id,
    image,
    since
  );
  if (duplicate) {
    return res.status(200).json({
      import: formatImport(duplicate),
      processing: duplicate.status === 'processing',
      deduplicated: true,
    });
  }

  const importId = crypto.randomUUID();
  const createdAt = now();
  await run(
    'INSERT INTO order_imports (id, business_id, user_id, source, image_url, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, \'processing\', ?, ?)',
    importId,
    req.business.id,
    req.auth.userId,
    source,
    image,
    createdAt,
    createdAt
  );

  await run(
    'INSERT INTO ai_chat_messages (id, business_id, user_id, order_import_id, role, message_type, content, metadata_json, created_at) VALUES (?, ?, ?, ?, \'user\', \'image\', ?, ?, ?)',
    crypto.randomUUID(),
    req.business.id,
    req.auth.userId,
    importId,
    'Uploaded a screenshot/photo for order import',
    JSON.stringify({ image }),
    createdAt
  );

  const importRow = await queryOne(
    `SELECT oi.*, t.transaction_number
       FROM order_imports oi
       LEFT JOIN transactions t ON t.id = oi.transaction_id
      WHERE oi.id = ?`,
    importId
  );

  // Reading a photo can take longer than a mobile HTTP request is willing to
  // wait (and a cold Render instance adds its own delay). Answer as soon as the
  // draft is queued, then let the client poll it. Holding the request open was
  // what produced "cannot reach the server" while the extraction still finished
  // in the background.
  res.status(202).json({ import: formatImport(importRow), processing: true });

  setImmediate(() => {
    processImport({
      importId,
      businessId: req.business.id,
      userId: req.auth.userId,
      image,
    }).catch(async (error) => {
      console.error('Screenshot import failed:', error?.message || error);
      const failedAt = now();
      try {
        await run(
          "UPDATE order_imports SET status = 'failed', updated_at = ? WHERE id = ? AND status <> 'completed'",
          failedAt,
          importId
        );
        // An error the user can act on belongs in the bell, not only in the
        // server log. Without this the import sat at "processing" until the
        // client gave up, with nothing explaining why.
        await addAppNotification({
          businessId: req.business.id,
          userId: req.auth.userId,
          importId,
          type: 'import_failed',
          title: 'Screenshot import failed',
          message:
            'We could not read that screenshot. Try another photo or record the sale manually.',
          severity: 'error',
          createdAt: failedAt,
        });
      } catch (notifyError) {
        console.error(
          'Could not record the import failure:',
          notifyError?.message || notifyError
        );
      }
    });
  });
});

/// Reads a queued screenshot, matches its items to the catalog and records the
/// result as a chat draft. Runs after the upload response has been sent.
async function processImport({ importId, businessId, userId, image }) {
  const extracted = await extractOrderFromImage(image);
  extracted.items = await matchCatalogItems(businessId, extracted.items || []);

  // The owner may delete the draft while the model is still reading it. Do not
  // write a result (or a chat message pointing at a missing draft) in that case.
  const stillExists = await queryOne('SELECT id FROM order_imports WHERE id = ?', importId);
  if (!stillExists) return;

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

  const updatedAt = now();
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
    updatedAt,
    importId
  );

  const itemCount = (extracted.items || []).length;
  const summary = itemCount === 1 ? '1 item' : `${itemCount} items`;
  const assistantMsg = missingFields.length > 0
    ? `Extracted ${summary}. Still missing: ${missingFields.map(missingFieldLabel).join(', ')}.`
    : `Extracted ${summary}. Review and confirm to create the order.`;

  await run(
    'INSERT INTO ai_chat_messages (id, business_id, user_id, order_import_id, role, message_type, content, metadata_json, created_at) VALUES (?, ?, ?, ?, \'assistant\', \'order_draft\', ?, ?, ?)',
    crypto.randomUUID(),
    businessId,
    userId,
    importId,
    assistantMsg,
    JSON.stringify({
      draft: extracted,
      missingFields,
      importId,
      incomplete: missingFields.length > 0,
    }),
    updatedAt
  );

  if (missingFields.length > 0) {
    // One notification per import, not one per missing field: a single order
    // should not flood the bell.
    await run(
      'INSERT INTO notifications (id, business_id, user_id, order_import_id, type, title, message, severity, created_at) VALUES (?, ?, ?, ?, \'order_import_incomplete\', ?, ?, \'warning\', ?)',
      crypto.randomUUID(),
      businessId,
      userId,
      importId,
      'Order draft needs details',
      `Missing: ${missingFields.map(missingFieldLabel).join(', ')}.`,
      updatedAt
    );
  }
}

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
  "deliveryFee": number or null,
  "discount": number or null,
  "items": [
    { "name": "string", "quantity": 1, "price": number or null }
  ],
  "totalAmount": number or null
}

Rules:
- customerName: the buyer's name ("Mr Ben", "Chinedu", etc.). Never the shop name.
- phoneNumber: the buyer's Nigerian mobile number only, written as 11 local digits ("0803 731 1300") or "+234" plus 10 digits. If the number is longer, shorter, or belongs to the shop, use null.
- deliveryAddress: only a real street/area/city address. If the text only says delivery is wanted, leave null and set wantsDelivery true.
- wantsDelivery: true whenever the order mentions delivery, dispatch, rider, "send am", "bring it", "wants delivery", or gives an address.
- deliveryFee: the delivery/dispatch/rider fee in naira when the order states one ("delivery 2k" -> 2000, "dispatch 1500" -> 1500). If only the order total is written, leave null.
- discount: the discount amount in naira if the order mentions one ("Discount of 2000" -> 2000). Otherwise null.
- items: every product mentioned. "2 adidas" -> name "adidas", quantity 2. Quantity defaults to 1. price is the unit price in naira ONLY when a price is actually written; if no price appears use null, never 0.
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
    signal: AbortSignal.timeout(20000),
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

  // The model chain is a fallback, not a queue: stop after a minute so a
  // single unavailable model cannot hold an import for several minutes.
  const deadline = Date.now() + 60000;
  let lastError = null;
  for (const model of models) {
    if (Date.now() > deadline) break;
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

      const discountKobo = toKoboFromPrice(parsed.discount) || 0;
      const totalKobo = toKoboFromPrice(parsed.totalAmount);
      let deliveryFeeKobo = toKoboFromPrice(
        parsed.deliveryFee ?? parsed.delivery_fee ?? parsed.shippingFee
      );

      // When the slip writes a total but not the rider fee, the difference
      // between the priced items and the total is the fee. Only trust it when
      // every item actually carried a price.
      if (wantsDelivery && (!deliveryFeeKobo || deliveryFeeKobo <= 0) && totalKobo) {
        const itemsKobo = items.reduce(
          (sum, it) => sum + (it.unit_price_kobo || 0) * (it.quantity || 1),
          0
        );
        if (itemsKobo > 0) {
          const inferred = totalKobo - (itemsKobo - discountKobo);
          if (inferred > 0) deliveryFeeKobo = inferred;
        }
      }

      return {
        customerName: parsed.customerName || null,
        customerPhone: normalizeNigerianPhone(
          parsed.phoneNumber || parsed.phone || parsed.customerPhone
        ),
        items,
        deliveryRequired: wantsDelivery,
        deliveryAddress: parsed.deliveryAddress || null,
        deliveryFeeKobo,
        discountKobo,
        totalKobo,
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
    transactionNumber: row.transaction_number ?? null,
    createdAt: row.created_at,
  };
}

function publicCustomerLite(row) {
  if (!row) return null;
  return {
    id: row.id,
    name: row.name,
    phone: row.phone ?? null,
    address: row.address ?? null,
  };
}

const HONORIFICS = new Set([
  'mr', 'mrs', 'miss', 'ms', 'dr', 'chief', 'alhaji', 'alhaja', 'engr', 'sir', 'madam',
]);

/// "0803 731 1300", "+2348037311300" and "2348037311300" are the same phone.
function normalizePhone(value) {
  const digits = String(value ?? '').replace(/\D/g, '');
  if (!digits) return '';
  if (digits.startsWith('234') && digits.length >= 13) return `0${digits.slice(3)}`;
  if (digits.length === 10) return `0${digits}`;
  return digits;
}

/// Picks the first valid Nigerian mobile number out of a value and returns it
/// as E.164 ("+2348037311300"). Returns null for landlines, short codes and
/// anything that is not a complete 10-digit mobile number.
export function normalizeNigerianPhone(value) {
  const raw = String(value ?? '').trim();
  if (!raw) return null;
  const digits = raw.replace(/\D/g, '');
  if (!digits) return null;

  let national = null;
  if (digits.startsWith('234') && digits.length >= 13) {
    national = digits.slice(3, 13);
  } else if (digits.startsWith('0') && digits.length >= 11) {
    national = digits.slice(1, 11);
  } else if (digits.length >= 10) {
    national = digits.slice(0, 10);
  }

  if (national && /^[789]\d{9}$/.test(national)) return `+234${national}`;

  // A screenshot may put the number beside other digits (prices, quantities).
  const match = digits.match(/[789]\d{9}/);
  return match ? `+234${match[0]}` : null;
}

/// The E.164 form the rest of the app stores ("+2348037311300"), so a customer
/// created from a screenshot looks like one created from the customer screen.
function toE164(value) {
  return normalizeNigerianPhone(value);
}

/// Compares names without case, punctuation or honorifics, so "Mr Ben" and
/// "ben" are the same customer while "Ben" and "Ben Okafor" stay distinct.
function namesMatch(a, b) {
  const tokens = (value) =>
    normalizeName(value)
      .split(' ')
      .filter((token) => token && !HONORIFICS.has(token));
  const left = tokens(a);
  const right = tokens(b);
  if (!left.length || !right.length) return false;
  return left.join(' ') === right.join(' ');
}

/**
 * Finds a customer the owner already saved. Phone wins over name because a
 * number is unique in practice while two customers can share a name.
 */
export async function findExistingCustomer(businessId, { name, phone } = {}) {
  const phoneKey = normalizePhone(phone);
  const rows = await queryAll(
    'SELECT id, name, phone, address FROM customers WHERE business_id = ?',
    businessId
  );

  if (phoneKey) {
    const byPhone = rows.find((row) => normalizePhone(row.phone) === phoneKey);
    if (byPhone) return { customer: byPhone, matchedBy: 'phone' };
  }
  if (name) {
    const byName = rows.find((row) => namesMatch(row.name, name));
    if (byName) return { customer: byName, matchedBy: 'name' };
  }
  return { customer: null, matchedBy: null };
}

/**
 * Reuses the saved customer when one matches and fills in whatever the
 * screenshot did not show. Only blank fields are filled, so an import can
 * never overwrite details the owner already typed.
 */
async function resolveCustomer(businessId, { name, phone, address }) {
  const cleanName = (name ?? '').trim();
  const cleanPhone = (phone ?? '').trim();
  const cleanAddress = (address ?? '').trim();
  const { customer, matchedBy } = await findExistingCustomer(businessId, {
    name: cleanName,
    phone: cleanPhone,
  });

  if (customer) {
    const nextPhone = customer.phone || toE164(cleanPhone);
    const nextAddress = customer.address || cleanAddress || null;
    if ((!customer.phone && cleanPhone) || (!customer.address && cleanAddress)) {
      await run(
        'UPDATE customers SET phone = ?, address = ?, updated_at = ? WHERE id = ?',
        nextPhone,
        nextAddress,
        now(),
        customer.id
      );
    }
    return {
      id: customer.id,
      name: customer.name,
      phone: nextPhone,
      address: nextAddress,
      matchedBy,
    };
  }

  const id = crypto.randomUUID();
  const storedPhone = toE164(cleanPhone);
  // customers.name is NOT NULL and at least two characters, so an order that
  // only carried a phone number is stored under that number.
  const fallback = cleanPhone || 'Walk-in customer';
  const finalName = (cleanName.length >= 2 ? cleanName : fallback).slice(0, 160);
  await run(
    'INSERT INTO customers (id, business_id, name, phone, address, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
    id,
    businessId,
    finalName,
    storedPhone,
    cleanAddress || null,
    now(),
    now()
  );
  return { id, name: finalName, phone: storedPhone, address: cleanAddress || null, matchedBy: null };
}

aiRouter.delete('/imports/:id', async (req, res) => {
  const imp = await queryOne(
    'SELECT * FROM order_imports WHERE id = ? AND business_id = ?',
    req.params.id,
    req.business.id
  );
  if (!imp) throw notFound('Import not found');

  // A draft that became a sale is a recorded transaction and must stay. The
  // chat messages and notification cascade with the import row.
  if (imp.transaction_id || imp.status === 'completed') {
    throw badRequest('This draft has already become a sale and cannot be deleted.');
  }

  await run('DELETE FROM order_imports WHERE id = ?', imp.id);
  res.status(204).end();
});

aiRouter.get('/imports', async (req, res) => {
  const imports = await queryAll(
    `SELECT oi.*, t.transaction_number
       FROM order_imports oi
       LEFT JOIN transactions t ON t.id = oi.transaction_id
      WHERE oi.business_id = ?
      ORDER BY oi.created_at DESC`,
    req.business.id
  );
  res.json({ imports: imports.map(formatImport) });
});

aiRouter.get('/imports/:id', async (req, res) => {
  const imp = await queryOne(
    `SELECT oi.*, t.transaction_number
       FROM order_imports oi
       LEFT JOIN transactions t ON t.id = oi.transaction_id
      WHERE oi.id = ? AND oi.business_id = ?`,
    req.params.id,
    req.business.id
  );
  if (!imp) throw notFound('Import not found');

  // The review screen uses this to pre-fill details the owner already saved.
  const { customer, matchedBy } = await findExistingCustomer(req.business.id, {
    name: imp.extracted_customer_name,
    phone: imp.extracted_customer_phone,
  });

  res.json({
    import: formatImport(imp),
    customer: publicCustomerLite(customer),
    matchedBy,
  });
});

aiRouter.get('/customers/match', async (req, res) => {
  const name = typeof req.query.name === 'string' ? req.query.name : '';
  const phone = typeof req.query.phone === 'string' ? req.query.phone : '';
  if (!name.trim() && !phone.trim()) {
    return res.json({ customer: null, matchedBy: null });
  }
  const { customer, matchedBy } = await findExistingCustomer(req.business.id, { name, phone });
  res.json({ customer: publicCustomerLite(customer), matchedBy });
});

aiRouter.post('/imports/:id/complete', async (req, res) => {
  const imp = await queryOne('SELECT * FROM order_imports WHERE id = ? AND business_id = ?', req.params.id, req.business.id);
  if (!imp) throw notFound('Import not found');
  if (imp.transaction_id) {
    throw badRequest('This order was already created.');
  }

  const {
    customer_id,
    customer_name,
    customer_phone,
    items,
    delivery_required,
    delivery_address,
    delivery_fee_kobo = 0,
    discount_kobo = 0,
    notes,
  } = req.body || {};

  if (!customer_id && !(customer_name ?? '').trim() && !(customer_phone ?? '').trim()) {
    throw badRequest('Add the customer name or phone number.', [
      { field: 'customer_name', message: 'A customer name or phone is required.' },
    ]);
  }

  // Store the same E.164 shape every other screen uses. A number that is not a
  // complete Nigerian mobile is refused here instead of becoming a customer
  // with an unusable, over-long phone.
  const phoneInput = (customer_phone ?? '').trim();
  const phoneE164 = phoneInput ? normalizeNigerianPhone(phoneInput) : null;
  if (phoneInput && !phoneE164) {
    throw badRequest('Enter a valid Nigerian phone number.', [
      { field: 'customer_phone', message: 'Enter a valid Nigerian phone number.' },
    ]);
  }

  if (!Array.isArray(items) || items.length === 0) {
    throw badRequest('Add at least one product to the order.', [
      { field: 'items', message: 'The order has no items.' },
    ]);
  }
  if (delivery_required && !(delivery_address ?? '').trim()) {
    throw badRequest('Add the address this order should be delivered to.', [
      { field: 'delivery_address', message: 'A delivery address is required.' },
    ]);
  }

  const businessId = req.business.id;

  // A customer chosen on screen wins; otherwise the saved customer is reused
  // when the name or phone matches, and created only when nothing matches.
  let customer;
  if (customer_id) {
    const row = await queryOne(
      'SELECT id, name, phone, address FROM customers WHERE id = ? AND business_id = ?',
      customer_id,
      businessId
    );
    if (!row) throw notFound('That customer does not exist.');
    customer = { ...row, matchedBy: 'id' };
  } else {
    customer = await resolveCustomer(businessId, {
      name: customer_name,
      phone: phoneE164,
      address: delivery_required ? delivery_address : null,
    });
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
  const fee = delivery_required ? Math.round(Number(delivery_fee_kobo) || 0) : 0;
  const disc = Math.round(Number(discount_kobo) || 0);
  if (disc > subtotal) {
    throw badRequest('The discount cannot be more than the subtotal.', [
      { field: 'discount_kobo', message: 'Discount is larger than the items total.' },
    ]);
  }
  const total = subtotal + fee - disc;

  const year = new Date().getUTCFullYear();
  const count = await queryOne('SELECT COUNT(*) AS total FROM transactions WHERE business_id = ?', businessId);
  const txnNumber = `TXN-${year}-${String((count?.total ?? 0) + 1).padStart(5, '0')}`;
  const txnId = crypto.randomUUID();
  const deliveryStatus = delivery_required ? 'pending' : 'not_required';
  const createdAt = now();

  await transaction(async () => {
    await run(
      `INSERT INTO transactions
         (id, business_id, customer_id, transaction_number, source, subtotal_kobo,
          discount_kobo, delivery_fee_kobo, total_kobo, notes, delivery_required,
          delivery_address, order_status, payment_status, delivery_status,
          completion_status, created_by_user_id, created_at, updated_at)
       VALUES (?, ?, ?, ?, 'screenshot', ?, ?, ?, ?, ?, ?, ?, 'pending', 'unpaid', ?, 'open', ?, ?, ?)`,
      txnId,
      businessId,
      customer.id,
      txnNumber,
      subtotal,
      disc,
      fee,
      total,
      notes || null,
      delivery_required ? 1 : 0,
      delivery_required ? delivery_address : null,
      deliveryStatus,
      req.auth.userId,
      createdAt,
      createdAt
    );

    for (const it of resolvedItems) {
      await run(
        `INSERT INTO transaction_items
           (id, transaction_id, product_id, product_name_snapshot, image_url,
            quantity, unit_price_kobo, subtotal_kobo, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        crypto.randomUUID(),
        txnId,
        it.productId,
        it.name,
        it.imageUrl,
        it.quantity,
        it.unitPriceKobo,
        it.subtotalKobo,
        createdAt
      );
    }

    // The timeline opens with the sale, exactly as a manual transaction does.
    await recordCreation({
      transactionId: txnId,
      businessId,
      userId: req.auth.userId,
      order: 'pending',
      payment: 'unpaid',
      delivery: deliveryStatus,
      completion: 'open',
    });

    await run(
      'UPDATE order_imports SET status = \'completed\', transaction_id = ?, extracted_customer_id = ?, updated_at = ? WHERE id = ?',
      txnId,
      customer.id,
      now(),
      imp.id
    );

    await run(
      'INSERT INTO ai_chat_messages (id, business_id, user_id, order_import_id, role, message_type, content, metadata_json, created_at) VALUES (?, ?, ?, ?, \'assistant\', \'action\', ?, ?, ?)',
      crypto.randomUUID(),
      req.business.id,
      req.auth.userId,
      imp.id,
      `Order ${txnNumber} created.`,
      JSON.stringify({ transactionId: txnId, incomplete: false, customerId: customer.id }),
      now()
    );
  });

  res.json({
    transactionId: txnId,
    transactionNumber: txnNumber,
    customer: publicCustomerLite(customer),
    message: 'Order created',
  });
});

export default aiRouter;
