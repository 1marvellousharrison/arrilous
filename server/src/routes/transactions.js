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

export const transactionRouter = express.Router();

function parse(schema, payload) {
  const result = schema.safeParse(payload ?? {});
  if (!result.success) throw validationFailed(toFieldErrors(result.error));
  return result.data;
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
    quantity: row.quantity,
    unitPriceKobo: row.unit_price_kobo,
    subtotalKobo: row.subtotal_kobo,
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
    'SELECT * FROM transaction_items WHERE transaction_id = ? ORDER BY created_at ASC',
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
        unitPriceKobo: unitPrice,
        quantity: item.quantity,
        subtotalKobo: unitPrice * item.quantity,
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
      unitPriceKobo: unitPrice,
      quantity: item.quantity,
      subtotalKobo: unitPrice * item.quantity,
    };
  }));
}

transactionRouter.use(requireAuth, requireBusiness);

// POST /api/v1/transactions
transactionRouter.post('/', async (req, res) => {
  const body = parse(transactionCreateSchema, req.body);
  const businessId = req.business.id;

  if (body.customer_id) {
    const customer = await queryOne(
      'SELECT id FROM customers WHERE id = ? AND business_id = ?',
      body.customer_id,
      businessId
    );
    if (!customer) throw notFound('That customer does not exist.');
  }

  const items = await resolveItems(businessId, body.items);
  const subtotal = items.reduce((sum, item) => sum + item.subtotalKobo, 0);

  if (body.discount_kobo > subtotal) {
    throw badRequest('The discount cannot be more than the subtotal.', [
      { field: 'discount_kobo', message: 'Discount is larger than the items total.' },
    ]);
  }
  if (body.delivery_required && !body.delivery_address) {
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
  const deliveryStatus = body.delivery_required ? 'pending' : 'not_required';

  await transaction(async () => {
    await run(
      `INSERT INTO transactions
         (id, business_id, customer_id, transaction_number, source, subtotal_kobo,
          discount_kobo, delivery_fee_kobo, total_kobo, notes, delivery_required,
          delivery_address, order_status, payment_status, delivery_status,
          completion_status, created_by_user_id)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 'unpaid', ?, 'open', ?)`,
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
      body.delivery_required ? 1 : 0,
      body.delivery_address ?? null,
      deliveryStatus,
      req.auth.userId
    );

    for (const item of items) {
      await run(
        `INSERT INTO transaction_items
           (id, transaction_id, product_id, product_name_snapshot, quantity,
            unit_price_kobo, subtotal_kobo)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        crypto.randomUUID(),
        transactionId,
        item.productId,
        item.name,
        item.quantity,
        item.unitPriceKobo,
        item.subtotalKobo
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

  res.status(201).json({
    transaction: publicTransaction(await findOwnedTransaction(businessId, transactionId), {
      items: await itemsFor(transactionId),
    }),
  });
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

  res.json({
    transaction: publicTransaction(row, { items: await itemsFor(row.id) }),
    customer: customer
      ? { id: customer.id, name: customer.name, phone: customer.phone, email: customer.email }
      : null,
    // Phase 8 — the chronological timeline Phase 10 renders.
    history: await historyFor(row.id),
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
