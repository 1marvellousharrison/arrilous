import express from 'express';
import crypto from 'node:crypto';
import { queryOne, run } from '../db/index.js';
import { requireAuth } from '../middleware/auth.js';
import { requireBusiness, findBusinessForUser } from '../middleware/business.js';
import { conflict, validationFailed } from '../lib/errors.js';
import {
  businessCreateSchema,
  businessUpdateSchema,
  locationSchema,
  toFieldErrors,
} from '../lib/validators.js';

export const businessRouter = express.Router();

function parse(schema, payload) {
  const result = schema.safeParse(payload ?? {});
  if (!result.success) throw validationFailed(toFieldErrors(result.error));
  return result.data;
}

export function publicBusiness(row) {
  if (!row) return null;
  return {
    id: row.id,
    ownerUserId: row.owner_user_id,
    businessName: row.business_name,
    businessCategory: row.business_category,
    businessDescription: row.business_description,
    phone: row.phone,
    email: row.email,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function publicLocation(row) {
  if (!row) return null;
  return {
    id: row.id,
    businessId: row.business_id,
    address: row.address,
    city: row.city,
    state: row.state,
    country: row.country,
    latitude: row.latitude,
    longitude: row.longitude,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function businessWithLocation(business) {
  if (!business) return null;
  const location = queryOne(
    'SELECT * FROM business_locations WHERE business_id = ?',
    business.id
  );
  return { ...publicBusiness(business), location: publicLocation(location) };
}

function createBusiness(userId, body) {
  if (findBusinessForUser(userId)) {
    throw conflict('This account already has a business profile.', 'business_exists');
  }
  const id = crypto.randomUUID();
  run(
    `INSERT INTO businesses (id, owner_user_id, business_name, business_category,
                             business_description, phone, email)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    id,
    userId,
    body.business_name,
    body.business_category ?? null,
    body.business_description ?? null,
    body.phone ?? null,
    body.email ?? null
  );
  return queryOne('SELECT * FROM businesses WHERE id = ?', id);
}

function upsertLocation(businessId, body) {
  const now = new Date().toISOString();
  const existing = queryOne(
    'SELECT id FROM business_locations WHERE business_id = ?',
    businessId
  );

  if (existing) {
    run(
      `UPDATE business_locations
          SET address = ?, city = ?, state = ?, country = ?,
              latitude = ?, longitude = ?, updated_at = ?
        WHERE business_id = ?`,
      body.address,
      body.city ?? null,
      body.state ?? null,
      body.country ?? null,
      body.latitude ?? null,
      body.longitude ?? null,
      now,
      businessId
    );
  } else {
    run(
      `INSERT INTO business_locations
         (id, business_id, address, city, state, country, latitude, longitude)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      crypto.randomUUID(),
      businessId,
      body.address,
      body.city ?? null,
      body.state ?? null,
      body.country ?? null,
      body.latitude ?? null,
      body.longitude ?? null
    );
  }

  return queryOne('SELECT * FROM business_locations WHERE business_id = ?', businessId);
}

// The caller's own business, or null before setup. The client uses this to
// decide whether to send a new owner through business setup.
businessRouter.get('/', requireAuth, (req, res) => {
  res.json({ business: businessWithLocation(findBusinessForUser(req.auth.userId)) });
});

businessRouter.post('/', requireAuth, (req, res) => {
  const body = parse(businessCreateSchema, req.body);
  const business = createBusiness(req.auth.userId, body);
  res.status(201).json({ business: businessWithLocation(business) });
});

businessRouter.patch('/', requireAuth, requireBusiness, (req, res) => {
  const body = parse(businessUpdateSchema, req.body);
  const columns = {
    business_name: 'business_name',
    business_category: 'business_category',
    business_description: 'business_description',
    phone: 'phone',
    email: 'email',
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
    values.push(new Date().toISOString(), req.business.id);
    run(`UPDATE businesses SET ${assignments.join(', ')} WHERE id = ?`, ...values);
  }

  res.json({
    business: businessWithLocation(
      queryOne('SELECT * FROM businesses WHERE id = ?', req.business.id)
    ),
  });
});

businessRouter.get('/location', requireAuth, requireBusiness, (req, res) => {
  const location = queryOne(
    'SELECT * FROM business_locations WHERE business_id = ?',
    req.business.id
  );
  res.json({ location: publicLocation(location) });
});

// Upsert: the owner can review and re-confirm a location as often as needed.
businessRouter.put('/location', requireAuth, requireBusiness, (req, res) => {
  const body = parse(locationSchema, req.body);
  res.json({ location: publicLocation(upsertLocation(req.business.id, body)) });
});
