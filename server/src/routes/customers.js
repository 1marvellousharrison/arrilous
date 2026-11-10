import express from 'express';
import crypto from 'node:crypto';
import { queryOne, queryAll, run } from '../db/index.js';
import { requireAuth } from '../middleware/auth.js';
import { requireBusiness, requireOwner } from '../middleware/business.js';
import { notFound, validationFailed } from '../lib/errors.js';
import {
  customerCreateSchema,
  customerUpdateSchema,
  customerListQuerySchema,
  toFieldErrors,
} from '../lib/validators.js';

export const customerRouter = express.Router();

function parse(schema, payload) {
  const result = schema.safeParse(payload ?? {});
  if (!result.success) throw validationFailed(toFieldErrors(result.error));
  return result.data;
}

export function publicCustomer(row) {
  return {
    id: row.id,
    businessId: row.business_id,
    name: row.name,
    phone: row.phone,
    email: row.email,
    notes: row.notes,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export async function publicCustomerDetail(row, { staffUserId = null } = {}) {
  const stats = staffUserId
    ? await queryOne(
        `SELECT COUNT(*) AS transaction_count,
                COALESCE(SUM(total_kobo), 0) AS total_spent_kobo
           FROM transactions
          WHERE customer_id = ? AND created_by_user_id = ?`,
        row.id,
        staffUserId
      )
    : await queryOne(
        `SELECT COUNT(*) AS transaction_count,
                COALESCE(SUM(total_kobo), 0) AS total_spent_kobo
           FROM transactions WHERE customer_id = ?`,
        row.id
      );
  return {
    ...publicCustomer(row),
    transactionCount: stats?.transaction_count ?? 0,
    totalSpentKobo: stats?.total_spent_kobo ?? 0,
  };
}

/**
 * SQL that decides whether a staff may see a customer: the ones they registered
 * themselves, plus anyone they have actually served. `c` must be the customers
 * alias, and the caller binds the staff's user id twice.
 */
export const STAFF_CUSTOMER_VISIBILITY = `(
  c.created_by_user_id = ?
  OR EXISTS (
    SELECT 1 FROM transactions t
     WHERE t.customer_id = c.id
       AND t.business_id = c.business_id
       AND t.created_by_user_id = ?
  )
)`;

/** The staff's user id when the caller is a staff, otherwise null (the owner). */
function customerScope(req) {
  return req.staff ? req.auth.userId : null;
}

async function findOwnedCustomer(businessId, customerId, { staffUserId = null } = {}) {
  const row = await queryOne(
    'SELECT * FROM customers WHERE id = ? AND business_id = ?',
    customerId,
    businessId
  );
  if (!row) throw notFound('That customer does not exist.');

  // A staff reaching for a customer they have not served (or registered) gets
  // the same 404 as a stranger, so the record's existence is not leaked.
  if (staffUserId && row.created_by_user_id !== staffUserId) {
    const served = await queryOne(
      `SELECT 1 AS served FROM transactions
        WHERE customer_id = ? AND business_id = ? AND created_by_user_id = ?
        LIMIT 1`,
      customerId,
      businessId,
      staffUserId
    );
    if (!served) throw notFound('That customer does not exist.');
  }

  return row;
}


customerRouter.use(requireAuth, requireBusiness);

customerRouter.get('/', async (req, res) => {
  const query = parse(customerListQuerySchema, req.query);
  const staffId = customerScope(req);
  const where = ['c.business_id = ?'];
  const params = [req.business.id];

  // Stats and the list itself use the same audience: an owner sees the whole
  // customer book, a staff sees only the customers they registered or served.
  const selectParams = [];
  const statScope = staffId ? ' AND t2.created_by_user_id = ?' : '';
  if (staffId) selectParams.push(staffId, staffId);

  if (query.search) {
    where.push('(c.name ILIKE ? OR COALESCE(c.phone, \'\') ILIKE ? OR COALESCE(c.email, \'\') ILIKE ?)');
    const like = `%${query.search}%`;
    params.push(like, like, like);
  }

  if (staffId) {
    where.push(STAFF_CUSTOMER_VISIBILITY);
    params.push(staffId, staffId);
  }

  const rows = await queryAll(
    `SELECT c.*,
            (SELECT COUNT(*) FROM transactions t2
              WHERE t2.customer_id = c.id${statScope}) AS transaction_count,
            (SELECT COALESCE(SUM(t2.total_kobo), 0) FROM transactions t2
              WHERE t2.customer_id = c.id${statScope}) AS total_spent_kobo
       FROM customers c
      WHERE ${where.join(' AND ')}
      ORDER BY lower(c.name) ASC`,
    ...selectParams,
    ...params
  );

  res.json({
    customers: rows.map((row) => ({ ...publicCustomer(row), transactionCount: row.transaction_count, totalSpentKobo: row.total_spent_kobo })),
  });
});

customerRouter.post('/', async (req, res) => {
  const body = parse(customerCreateSchema, req.body);
  const id = crypto.randomUUID();
  await run(
    `INSERT INTO customers (id, business_id, name, phone, email, notes, created_by_user_id)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    id,
    req.business.id,
    body.name,
    body.phone,
    body.email ?? null,
    body.notes ?? null,
    req.auth.userId
  );
  res.status(201).json({
    customer: await publicCustomerDetail(
      await queryOne('SELECT * FROM customers WHERE id = ?', id),
      { staffUserId: customerScope(req) }
    ),
  });
});

customerRouter.get('/:id', async (req, res) => {
  const staffId = customerScope(req);
  const customer = await findOwnedCustomer(req.business.id, req.params.id, {
    staffUserId: staffId,
  });
  const transactionScope = staffId ? ' AND created_by_user_id = ?' : '';
  res.json({
    customer: await publicCustomerDetail(customer, { staffUserId: staffId }),
    transactions: (await queryAll(
      `SELECT id, transaction_number, source, total_kobo, order_status, payment_status,
              delivery_status, completion_status, created_at
         FROM transactions
        WHERE customer_id = ?${transactionScope}
        ORDER BY created_at DESC LIMIT 50`,
      ...(staffId ? [customer.id, staffId] : [customer.id])
    )).map((row) => ({
      id: row.id,
      transactionNumber: row.transaction_number,
      source: row.source,
      totalKobo: row.total_kobo,
      orderStatus: row.order_status,
      paymentStatus: row.payment_status,
      deliveryStatus: row.delivery_status,
      completionStatus: row.completion_status,
      createdAt: row.created_at,
    })),
  });
});

customerRouter.patch('/:id', requireOwner, async (req, res) => {
  const existing = await findOwnedCustomer(req.business.id, req.params.id);
  const body = parse(customerUpdateSchema, req.body);

  const columns = {
    name: 'name',
    phone: 'phone',
    email: 'email',
    notes: 'notes',
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
    await run(`UPDATE customers SET ${assignments.join(', ')} WHERE id = ?`, ...values);
  }

  res.json({
    customer: await publicCustomerDetail(
      await queryOne('SELECT * FROM customers WHERE id = ?', existing.id)
    ),
  });
});
