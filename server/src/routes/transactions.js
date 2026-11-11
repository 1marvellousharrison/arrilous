import express from 'express';
import crypto from 'node:crypto';
import { queryOne, queryAll, run, transaction } from '../db/index.js';
import { requireAuth } from '../middleware/auth.js';
import { requireBusiness } from '../middleware/business.js';
import { notFound, badRequest, forbidden, validationFailed } from '../lib/errors.js';
import { creditSaleToWallet } from '../lib/wallet.js';
import {
  transactionCreateSchema,
  transactionListQuerySchema,
  statusUpdateSchema,
  digitalDeliverSchema,
  toFieldErrors,
} from '../lib/validators.js';
import {
  assertTransition,
  assertStatusCombination,
  publicStatuses,
} from '../lib/statuses.js';
import {
  currentAxes,
  historyFor,
  recordCreation,
  recordNote,
  recordStatusDiff,
} from '../lib/history.js';
import {
  actorDisplayName,
  nairaText,
  safeAddAppNotification,
} from '../lib/notifications.js';
import { STAFF_CUSTOMER_VISIBILITY } from './customers.js';
import { publicSaleUrl } from './public.js';
import { emailService } from '../services/email.js';

export const transactionRouter = express.Router();

function parse(schema, payload) {
  const result = schema.safeParse(payload ?? {});
  if (!result.success) throw validationFailed(toFieldErrors(result.error));
  return result.data;
}

const STATUS_LABELS = {
  order: 'Order',
  payment: 'Payment',
  delivery: 'Delivery',
  completion: 'Completion',
};

function statusChangeText(changed) {
  return changed
    .map(
      (entry) =>
        `${STATUS_LABELS[entry.type] ?? entry.type} ${entry.from ?? '—'} → ${entry.to}`
    )
    .join(', ');
}

export function publicTransaction(row, { items = null } = {}) {
  const payload = {
    id: row.id,
    businessId: row.business_id,
    customerId: row.customer_id,
    transactionNumber: row.transaction_number,
    source: row.source,
    subtotalKobo: row.subtotal_kobo,
    discountKobo: row.discount_kobo,
    deliveryFeeKobo: row.delivery_fee_kobo,
    totalKobo: row.total_kobo,
    notes: row.notes,
    deliveryAddress: row.delivery_address,
    createdByUserId: row.created_by_user_id ?? null,
    // Digital sales carry the token for the buyer's public page. It is scoped
    // to this business's authenticated view; the public route is the only place
    // it is served without a login.
    publicToken: row.public_token ?? null,
    digitalDeliveryEmail: row.digital_delivery_email ?? null,
    digitalDeliveredAt: row.digital_delivered_at ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    ...publicStatuses(row),
  };
  if (items) payload.items = items;
  return payload;
}

export function publicItem(row) {
  return {
    id: row.id,
    transactionId: row.transaction_id,
    productId: row.product_id,
    name: row.product_name_snapshot,
    imageUrl: row.image_url,
    quantity: row.quantity,
    unitPriceKobo: row.unit_price_kobo,
    subtotalKobo: row.subtotal_kobo,
    // A snapshot of the asset at the moment of sale. Editing the product later
    // cannot change what this buyer receives.
    isDigital: Boolean(row.is_digital),
    digitalUrl: row.digital_url ?? null,
    digitalInstructions: row.digital_instructions ?? null,
    digitalFileName: row.digital_file_name ?? null,
    hasDigitalFile: Boolean(row.digital_file_id),
  };
}

/**
 * Loads a transaction scoped to the business, and — when the caller is a staff —
 * also to that staff's own sales. A staff reaching for a colleague's sale gets
 * the same 404 as a stranger, so the record's existence is not even leaked.
 */
async function findOwnedTransaction(businessId, transactionId, { staffUserId = null } = {}) {
  const row = staffUserId
    ? await queryOne(
        'SELECT * FROM transactions WHERE id = ? AND business_id = ? AND created_by_user_id = ?',
        transactionId,
        businessId,
        staffUserId
      )
    : await queryOne(
        'SELECT * FROM transactions WHERE id = ? AND business_id = ?',
        transactionId,
        businessId
      );
  if (!row) throw notFound('That transaction does not exist.');
  return row;
}

/** The staff's user id when the caller is a staff, otherwise null (the owner). */
function transactionScope(req) {
  return req.staff ? req.auth.userId : null;
}

async function itemsFor(transactionId) {
  return (await queryAll(
    `SELECT ti.*, df.file_name AS digital_file_name
       FROM transaction_items ti
       LEFT JOIN digital_files df ON df.id = ti.digital_file_id
      WHERE ti.transaction_id = ?
      ORDER BY ti.created_at ASC`,
    transactionId
  )).map(publicItem);
}

async function nextTransactionNumber(businessId) {
  const count = await queryOne(
    'SELECT COUNT(*) AS total FROM transactions WHERE business_id = ?',
    businessId
  );
  const year = new Date().getUTCFullYear();
  return `TXN-${year}-${String((count?.total ?? 0) + 1).padStart(5, '0')}`;
}

/**
 * Phase 6 — resolves each line to a price the server trusts.
 *
 * A line that references a catalog product takes its name and price FROM THE
 * CATALOG, never from the payload: the client cannot sell a ₦1 shirt by sending
 * unit_price_kobo: 100. Ad-hoc lines (no product_id) are allowed and use the
 * caller's own name and price, which is how a one-off sale is recorded.
 */
async function resolveItems(businessId, rawItems) {
  return Promise.all(rawItems.map(async (item, index) => {
    if (item.product_id) {
      const product = await queryOne(
        'SELECT * FROM products WHERE id = ? AND business_id = ?',
        item.product_id,
        businessId
      );
      if (!product) {
        throw notFound(`Product for item ${index + 1} does not exist.`);
      }
      if (!product.active) {
        throw badRequest(
          `"${product.name}" is archived and cannot be added to a new transaction.`,
          [{ field: `items.${index}.product_id`, message: 'Choose an active product.' }]
        );
      }
      const unitPrice = product.price_kobo;
      return {
        productId: product.id,
        name: product.name,
        imageUrl: product.image_url,
        unitPriceKobo: unitPrice,
        quantity: item.quantity,
        subtotalKobo: unitPrice * item.quantity,
        isDigital: (product.kind ?? 'physical') === 'digital',
        digitalUrl: product.digital_url ?? null,
        digitalInstructions: product.digital_instructions ?? null,
        digitalFileId: product.digital_file_id ?? null,
      };
    }

    if (!item.name) {
      throw badRequest(
        `Item ${index + 1} needs either a product or a name.`,
        [{ field: `items.${index}.name`, message: 'Add a product or type a name.' }]
      );
    }
    const unitPrice = item.unit_price_kobo ?? 0;
    return {
      productId: null,
      name: item.name,
      imageUrl: null,
      unitPriceKobo: unitPrice,
      quantity: item.quantity,
      subtotalKobo: unitPrice * item.quantity,
      isDigital: false,
      digitalUrl: null,
      digitalInstructions: null,
      digitalFileId: null,
    };
  }));
}

transactionRouter.use(requireAuth, requireBusiness);

// POST /api/v1/transactions
transactionRouter.post('/', async (req, res) => {
  const body = parse(transactionCreateSchema, req.body);
  const businessId = req.business.id;

  if (body.customer_id) {
    const staffId = req.staff ? req.auth.userId : null;
    const customer = staffId
      ? await queryOne(
          `SELECT c.id FROM customers c
            WHERE c.id = ? AND c.business_id = ? AND ${STAFF_CUSTOMER_VISIBILITY}`,
          body.customer_id,
          businessId,
          staffId,
          staffId
        )
      : await queryOne(
          'SELECT id FROM customers WHERE id = ? AND business_id = ?',
          body.customer_id,
          businessId
        );
    if (!customer) throw notFound('That customer does not exist.');
  }

  const items = await resolveItems(businessId, body.items);
  const subtotal = items.reduce((sum, item) => sum + item.subtotalKobo, 0);
  const hasDigital = items.some((item) => item.isDigital);
  const hasPhysical = items.some((item) => !item.isDigital);

  if (body.discount_kobo > subtotal) {
    throw badRequest('The discount cannot be more than the subtotal.', [
      { field: 'discount_kobo', message: 'Discount is larger than the items total.' },
    ]);
  }

  // Delivery only makes sense when something physical is in the cart. An
  // all-digital sale keeps its address and fee out of the record even if the
  // client left the switch on, so a digital order can never wait at a depot.
  const deliveryRequired = Boolean(body.delivery_required) && hasPhysical;
  if (deliveryRequired && !body.delivery_address) {
    throw badRequest('Add the address this order should be delivered to.', [
      { field: 'delivery_address', message: 'A delivery address is required.' },
    ]);
  }

  // Financial totals are computed here and only here.
  const deliveryFee = body.delivery_fee_kobo;
  const discount = body.discount_kobo;
  const total = subtotal + deliveryFee - discount;
  if (total < 0) {
    throw badRequest('The total cannot be negative.', [
      { field: 'discount_kobo', message: 'Discount is larger than the items total.' },
    ]);
  }

  const now = new Date().toISOString();
  const transactionId = crypto.randomUUID();
  const transactionNumber = await nextTransactionNumber(businessId);
  // Phase 7 defaults: pending / unpaid / not_required|pending / open.
  const deliveryStatus = deliveryRequired ? 'pending' : 'not_required';
  // The buyer's public page handle is minted once, only when there is a digital
  // asset to deliver. A walk-in physical sale never gets an unauthenticated link.
  const publicToken = hasDigital ? crypto.randomBytes(24).toString('base64url') : null;

  await transaction(async () => {
    await run(
      `INSERT INTO transactions
         (id, business_id, customer_id, transaction_number, source, subtotal_kobo,
          discount_kobo, delivery_fee_kobo, total_kobo, notes, delivery_required,
          delivery_address, order_status, payment_status, delivery_status,
          completion_status, created_by_user_id, public_token)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 'unpaid', ?, 'open', ?, ?)`,
      transactionId,
      businessId,
      body.customer_id ?? null,
      transactionNumber,
      body.source,
      subtotal,
      discount,
      deliveryFee,
      total,
      body.notes ?? null,
      deliveryRequired ? 1 : 0,
      deliveryRequired ? body.delivery_address ?? null : null,
      deliveryStatus,
      req.auth.userId,
      publicToken
    );

    for (const item of items) {
      await run(
        `INSERT INTO transaction_items
           (id, transaction_id, product_id, product_name_snapshot, image_url,
            quantity, unit_price_kobo, subtotal_kobo, is_digital, digital_url,
            digital_instructions, digital_file_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        crypto.randomUUID(),
        transactionId,
        item.productId,
        item.name,
        item.imageUrl ?? null,
        item.quantity,
        item.unitPriceKobo,
        item.subtotalKobo,
        item.isDigital ? 1 : 0,
        item.digitalUrl ?? null,
        item.digitalInstructions ?? null,
        item.digitalFileId ?? null
      );
    }

    // Phase 8 — the timeline opens inside the same transaction as the sale, so
    // a transaction can never exist without the history of how it was born.
    await recordCreation({
      transactionId,
      businessId,
      userId: req.auth.userId,
      order: 'pending',
      payment: 'unpaid',
      delivery: deliveryStatus,
      completion: 'open',
    });
  });

  // The owner sees every sale, including one a staff member records, and the
  // event names the staff so "who sold this?" is answered in the bell itself.
  const actorName = await actorDisplayName(req.auth.userId);
  await safeAddAppNotification({
    businessId,
    transactionId,
    actorUserId: req.auth.userId,
    type: 'sale_recorded',
    title: req.staff ? 'Staff recorded a sale' : 'New sale recorded',
    message: req.staff
      ? `${actorName ?? 'Staff'} recorded sale ${transactionNumber} · ${nairaText(total)}`
      : `Sale ${transactionNumber} recorded · ${nairaText(total)}`,
    severity: 'success',
  });

  const payload = publicTransaction(await findOwnedTransaction(businessId, transactionId), {
    items: await itemsFor(transactionId),
  });
  payload.publicUrl = publicSaleUrl(req, payload.publicToken);
  res.status(201).json({ transaction: payload });
});

transactionRouter.get('/', async (req, res) => {
  const query = parse(transactionListQuerySchema, req.query);
  const where = ['business_id = ?'];
  const params = [req.business.id];

  // A staff sees only the sales they personally recorded.
  const scopedStaffId = transactionScope(req);
  if (scopedStaffId) {
    where.push('created_by_user_id = ?');
    params.push(scopedStaffId);
  }

  const filterMap = {
    order_status: 'order_status',
    payment_status: 'payment_status',
    delivery_status: 'delivery_status',
    completion_status: 'completion_status',
    source: 'source',
    customer_id: 'customer_id',
  };
  for (const [key, column] of Object.entries(filterMap)) {
    if (query[key]) {
      where.push(`${column} = ?`);
      params.push(query[key]);
    }
  }
  // The owner dashboard's "Needs attention" rows open this list already
  // narrowed to exactly the sales they counted. A cancelled sale is left out
  // for the same reason the dashboard leaves it out of these counts: it did not
  // happen. `attention` is a named group because some groups span several
  // statuses, which one status filter cannot express.
  const attentionWhere = {
    awaiting_payment: "payment_status IN ('unpaid', 'payment_pending')",
    to_deliver: "delivery_status IN ('pending', 'accepted', 'picked_up')",
    on_road: "delivery_status = 'in_transit'",
    failures: "(payment_status = 'failed' OR delivery_status = 'failed')",
  };
  if (query.attention) {
    where.push(`order_status <> 'cancelled'`);
    where.push(attentionWhere[query.attention]);
  }
  if (query.search) {
    where.push('(transaction_number ILIKE ? OR COALESCE(notes, \'\') ILIKE ?)');
    const like = `%${query.search}%`;
    params.push(like, like);
  }
  // Phase 11 date range. The bounds are normalised to UTC ISO strings to match
  // how created_at is stored.
  if (query.from) {
    where.push('created_at >= ?');
    params.push(query.from.toISOString());
  }
  if (query.to) {
    where.push('created_at <= ?');
    params.push(query.to.toISOString());
  }

  const rows = await queryAll(
    `SELECT * FROM transactions WHERE ${where.join(' AND ')}
      ORDER BY created_at DESC LIMIT ? OFFSET ?`,
    ...params,
    query.limit,
    query.offset
  );

  res.json({ transactions: rows.map((row) => publicTransaction(row)) });
});

transactionRouter.get('/:id', async (req, res) => {
  const row = await findOwnedTransaction(req.business.id, req.params.id, {
    staffUserId: transactionScope(req),
  });
  const customer = row.customer_id
    ? await queryOne('SELECT * FROM customers WHERE id = ?', row.customer_id)
    : null;

  const transaction = publicTransaction(row, { items: await itemsFor(row.id) });
  transaction.publicUrl = publicSaleUrl(req, row.public_token);

  res.json({
    transaction,
    customer: customer
      ? { id: customer.id, name: customer.name, phone: customer.phone, email: customer.email }
      : null,
    // Phase 8 — the chronological timeline Phase 10 renders.
    history: await historyFor(row.id),
  });
});

// POST /api/v1/transactions/:id/deliver — emails a paid digital order.
transactionRouter.post('/:id/deliver', async (req, res) => {
  const body = parse(digitalDeliverSchema, req.body);
  const row = await findOwnedTransaction(req.business.id, req.params.id, {
    staffUserId: transactionScope(req),
  });

  const digitalItems = (await itemsFor(row.id)).filter((item) => item.isDigital);
  if (digitalItems.length === 0) {
    throw badRequest('This sale has no digital products to deliver.');
  }
  if (row.payment_status !== 'paid') {
    throw badRequest('Confirm payment before sending the digital products.', [
      { field: 'paymentStatus', message: 'Mark the sale as paid first.' },
    ]);
  }

  // Older digital sales (or a manually repaired row) may lack a token; mint one
  // on the way out rather than making the owner re-record the sale.
  let token = row.public_token;
  if (!token) {
    token = crypto.randomBytes(24).toString('base64url');
    await run('UPDATE transactions SET public_token = ? WHERE id = ?', token, row.id);
  }

  const customer = row.customer_id
    ? await queryOne('SELECT id, email FROM customers WHERE id = ?', row.customer_id)
    : null;
  const email = body.email ?? row.digital_delivery_email ?? customer?.email ?? null;
  if (!email) {
    throw validationFailed([
      {
        field: 'email',
        message: 'Add the email address the buyer should receive this at.',
      },
    ]);
  }

  const publicUrl = publicSaleUrl(req, token);
  let emailSent = false;
  let message;
  try {
    const result = await emailService.sendDigitalDelivery({
      to: email,
      businessName: req.business.business_name,
      transactionNumber: row.transaction_number,
      items: digitalItems,
      url: publicUrl,
    });
    emailSent = Boolean(result.delivered);
    message = emailSent
      ? `Sent to ${email}.`
      : 'Email is not configured on this server. Share the public link instead.';
  } catch {
    // A provider outage must not hide the link: the owner can still deliver by
    // copying the public URL, which is the same page the email points at.
    message = 'The email provider refused the message. Share the public link instead.';
  }

  const now = new Date().toISOString();
  await run(
    `UPDATE transactions
        SET digital_delivery_email = ?,
            digital_delivered_at = CASE WHEN ? = 1 THEN ? ELSE digital_delivered_at END,
            updated_at = ?
      WHERE id = ?`,
    email,
    emailSent ? 1 : 0,
    now,
    now,
    row.id
  );

  res.json({
    status: 'success',
    emailSent,
    email,
    publicUrl,
    message,
  });
});

// PATCH /api/v1/transactions/:id/statuses — Phase 7 + Phase 8 history.
transactionRouter.patch('/:id/statuses', async (req, res) => {
  const current = await findOwnedTransaction(req.business.id, req.params.id, {
    staffUserId: transactionScope(req),
  });
  const body = parse(statusUpdateSchema, req.body);
  let changed = [];

  // A staff may annotate a sale but never move its status. The client hides the
  // controls, but the API enforces it: only a note is accepted from a staff.
  const wantsStatusChange =
    body.orderStatus !== undefined ||
    body.paymentStatus !== undefined ||
    body.deliveryStatus !== undefined ||
    body.completionStatus !== undefined;
  if (req.staff && wantsStatusChange) {
    throw forbidden('Staff can add notes to a sale, but cannot change its status.');
  }

  const next = {
    orderStatus: body.orderStatus ?? current.order_status,
    paymentStatus: body.paymentStatus ?? current.payment_status,
    deliveryStatus: body.deliveryStatus ?? current.delivery_status,
    completionStatus: body.completionStatus ?? current.completion_status,
    deliveryRequired: Boolean(current.delivery_required),
  };

  if (body.orderStatus) assertTransition('order', current.order_status, body.orderStatus);
  if (body.paymentStatus) assertTransition('payment', current.payment_status, body.paymentStatus);
  if (body.deliveryStatus) assertTransition('delivery', current.delivery_status, body.deliveryStatus);
  if (body.completionStatus) {
    assertTransition('completion', current.completion_status, body.completionStatus);
  }

  // A cancelled order is frozen: nothing may keep moving except a refund of
  // money that was already taken, which is exactly what cancelling means.
  if (current.order_status === 'cancelled') {
    const frozen =
      (body.deliveryStatus && body.deliveryStatus !== current.delivery_status) ||
      (body.completionStatus && body.completionStatus !== current.completion_status) ||
      (body.paymentStatus &&
        body.paymentStatus !== current.payment_status &&
        body.paymentStatus !== 'refunded');
    if (frozen) {
      throw badRequest('A cancelled transaction cannot change delivery or completion.', [
        { field: 'orderStatus', message: 'Cancel is final; only a refund is still possible.' },
      ]);
    }
  }

  assertStatusCombination(next, {
    orderStatus: current.order_status,
    paymentStatus: current.payment_status,
    deliveryStatus: current.delivery_status,
    completionStatus: current.completion_status,
  });

  // A sale is credited to the owner's wallet exactly once, when its payment
  // first becomes 'paid'. The transition table makes this a one-way door, so
  // this guard and the ledger's unique reference keep a double credit impossible.
  const creditOnPaid =
    current.payment_status !== 'paid' && next.paymentStatus === 'paid';

  // The column update, its timeline entries and the wallet credit commit
  // together. If the write failed halfway the history would claim a change that
  // the columns do not show, which is exactly the kind of lie an audit trail
  // must not tell.
  await transaction(async () => {
    await run(
      `UPDATE transactions
          SET order_status = ?, payment_status = ?, delivery_status = ?,
              completion_status = ?, updated_at = ?
        WHERE id = ?`,
      next.orderStatus,
      next.paymentStatus,
      next.deliveryStatus,
      next.completionStatus,
      new Date().toISOString(),
      current.id
    );

    // Phase 8 — recordStatusDiff drops axes whose value did not actually move,
    // so re-sending the current status does not invent an event.
    changed = await recordStatusDiff({
      transactionId: current.id,
      businessId: req.business.id,
      userId: req.auth.userId,
      previous: currentAxes(current),
      next: {
        order: next.orderStatus,
        payment: next.paymentStatus,
        delivery: next.deliveryStatus,
        completion: next.completionStatus,
      },
      note: body.note ?? null,
    });

    // A note with no status move — a staff annotation, or an owner's plain note
    // — still belongs on the timeline. When a status did move, the note is
    // already carried on those entries, so it is not written twice.
    if (changed.length === 0 && body.note) {
      await recordNote({
        transactionId: current.id,
        businessId: req.business.id,
        userId: req.auth.userId,
        note: body.note,
      });
    }

    if (creditOnPaid) {
      await creditSaleToWallet(req.business, current);
    }
  });

  if (changed.length > 0) {
    const paid = changed.some(
      (entry) => entry.type === 'payment' && entry.to === 'paid'
    );
    const actorName = await actorDisplayName(req.auth.userId);
    const staffSuffix = req.staff && actorName ? ` by ${actorName}` : '';
    await safeAddAppNotification({
      businessId: req.business.id,
      transactionId: current.id,
      actorUserId: req.auth.userId,
      type: 'sale_status',
      title: paid
        ? `Payment received for ${current.transaction_number}`
        : `${current.transaction_number} updated${staffSuffix}`,
      message: statusChangeText(changed),
      severity: paid ? 'success' : 'info',
    });
  }

  res.json({
    transaction: publicTransaction(
      await findOwnedTransaction(req.business.id, current.id, {
        staffUserId: transactionScope(req),
      }),
      { items: await itemsFor(current.id) }
    ),
    changed,
  });
});
