import express from 'express';
import crypto from 'node:crypto';
import { queryOne, queryAll, run } from '../db/index.js';
import { requireAuth } from '../middleware/auth.js';
import { requireBusiness } from '../middleware/business.js';
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

export function publicCustomerDetail(row) {
  const stats = queryOne(
    `SELECT COUNT(*) AS transaction_count,
            IFNULL(SUM(total_kobo), 0) AS total_spent_kobo
       FROM transactions WHERE customer_id = ?`,
    row.id
  );
  return {
    ...publicCustomer(row),
    transactionCount: stats?.transaction_count ?? 0,
    totalSpentKobo: stats?.total_spent_kobo ?? 0,
  };
}

function findOwnedCustomer(businessId, customerId) {
  const row = queryOne(
    'SELECT * FROM customers WHERE id = ? AND business_id = ?',
    customerId,
    businessId
  );
  if (!row) throw notFound('That customer does not exist.');
  return row;
}

customerRouter.use(requireAuth, requireBusiness);

customerRouter.get('/', (req, res) => {
  const query = parse(customerListQuerySchema, req.query);
  const where = ['c.business_id = ?'];
  const params = [req.business.id];

  if (query.search) {
    where.push('(c.name LIKE ? OR IFNULL(c.phone, \'\') LIKE ? OR IFNULL(c.email, \'\') LIKE ?)');
    const like = `%${query.search}%`;
    params.push(like, like, like);
  }

  const rows = queryAll(
    `SELECT c.*,
            (SELECT COUNT(*) FROM transactions t WHERE t.customer_id = c.id) AS transaction_count,
            (SELECT IFNULL(SUM(t.total_kobo), 0) FROM transactions t WHERE t.customer_id = c.id) AS total_spent_kobo
       FROM customers c
      WHERE ${where.join(' AND ')}
      ORDER BY c.name COLLATE NOCASE ASC`,
    ...params
  );

  res.json({
    customers: rows.map((row) => ({ ...publicCustomer(row), transactionCount: row.transaction_count, totalSpentKobo: row.total_spent_kobo })),
  });
});

customerRouter.post('/', (req, res) => {
  const body = parse(customerCreateSchema, req.body);
  const id = crypto.randomUUID();
  run(
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
    customer: publicCustomerDetail(queryOne('SELECT * FROM customers WHERE id = ?', id)),
  });
});

customerRouter.get('/:id', (req, res) => {
  const customer = findOwnedCustomer(req.business.id, req.params.id);
  res.json({
    customer: publicCustomerDetail(customer),
    transactions: queryAll(
      `SELECT id, transaction_number, source, total_kobo, order_status, payment_status,
              delivery_status, completion_status, created_at
         FROM transactions WHERE customer_id = ? ORDER BY created_at DESC LIMIT 50`,
      customer.id
    ).map((row) => ({
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

customerRouter.patch('/:id', (req, res) => {
  const existing = findOwnedCustomer(req.business.id, req.params.id);
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
    run(`UPDATE customers SET ${assignments.join(', ')} WHERE id = ?`, ...values);
  }

  res.json({
    customer: publicCustomerDetail(
      queryOne('SELECT * FROM customers WHERE id = ?', existing.id)
    ),
  });
});
