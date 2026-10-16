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
    address: row.address,
    notes: row.notes,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export async function publicCustomerDetail(row) {
  const stats = await queryOne(
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

async function findOwnedCustomer(businessId, customerId) {
  const row = await queryOne(
    'SELECT * FROM customers WHERE id = ? AND business_id = ?',
    customerId,
    businessId
  );
  if (!row) throw notFound('That customer does not exist.');
  return row;
}

customerRouter.use(requireAuth, requireBusiness);

customerRouter.get('/', async (req, res) => {
  const query = parse(customerListQuerySchema, req.query);
  const where = ['c.business_id = ?'];
  const params = [req.business.id];

  if (query.search) {
    where.push('(c.name ILIKE ? OR COALESCE(c.phone, \'\') ILIKE ? OR COALESCE(c.email, \'\') ILIKE ?)');
    const like = `%${query.search}%`;
    params.push(like, like, like);
  }

  const rows = await queryAll(
    `SELECT c.*,
            (SELECT COUNT(*) FROM transactions t WHERE t.customer_id = c.id) AS transaction_count,
            (SELECT COALESCE(SUM(t.total_kobo), 0) FROM transactions t WHERE t.customer_id = c.id) AS total_spent_kobo
       FROM customers c
      WHERE ${where.join(' AND ')}
      ORDER BY lower(c.name) ASC`,
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
    `INSERT INTO customers (id, business_id, name, phone, email, address, notes)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    id,
    req.business.id,
    body.name,
    body.phone ?? null,
    body.email ?? null,
    body.address ?? null,
    body.notes ?? null
  );
  res.status(201).json({
    customer: await publicCustomerDetail(await queryOne('SELECT * FROM customers WHERE id = ?', id)),
  });
});

customerRouter.get('/:id', async (req, res) => {
  const customer = await findOwnedCustomer(req.business.id, req.params.id);
  res.json({
    customer: await publicCustomerDetail(customer),
    transactions: (await queryAll(
      `SELECT id, transaction_number, source, total_kobo, order_status, payment_status,
              delivery_status, completion_status, created_at
         FROM transactions WHERE customer_id = ? ORDER BY created_at DESC LIMIT 50`,
      customer.id
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
    address: 'address',
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
