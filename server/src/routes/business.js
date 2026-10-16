import express from 'express';
import crypto from 'node:crypto';
import { queryOne, run } from '../db/index.js';
import { requireAuth } from '../middleware/auth.js';
import { requireBusinessOwner, requireBusiness, requireOwner, findBusinessForUser } from '../middleware/business.js';
import { conflict, validationFailed } from '../lib/errors.js';
import { generateBusinessCode } from '../lib/staff.js';
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
    logoUrl: row.logo_url,
    businessCode: row.business_code ?? null,
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
    area: row.area,
    state: row.state,
    country: row.country,
    latitude: row.latitude,
    longitude: row.longitude,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export async function businessWithLocation(business) {
  if (!business) return null;
  const location = await queryOne(
    'SELECT * FROM business_locations WHERE business_id = ?',
    business.id
  );
  return { ...publicBusiness(business), location: publicLocation(location) };
}

async function createBusiness(userId, body) {
  if (await findBusinessForUser(userId)) {
    throw conflict('This account already has a business profile.', 'business_exists');
  }
  const id = crypto.randomUUID();
  // The stable prefix every staff code is built from, snapshotted once so a
  // later rename never invalidates a staff's permanent login.
  const businessCode = await generateBusinessCode(body.business_name);
  await run(
    `INSERT INTO businesses (id, owner_user_id, business_name, business_category,
                             business_description, phone, email, logo_url, business_code)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    id,
    userId,
    body.business_name,
    body.business_category ?? null,
    body.business_description ?? null,
    body.phone ?? null,
    body.email ?? null,
    body.logo_url ?? null,
    businessCode
  );
  return await queryOne('SELECT * FROM businesses WHERE id = ?', id);
}

async function upsertLocation(businessId, body) {
  const now = new Date().toISOString();
  const existing = await queryOne(
    'SELECT id FROM business_locations WHERE business_id = ?',
    businessId
  );

  if (existing) {
    await run(
      `UPDATE business_locations
          SET address = ?, city = ?, area = ?, state = ?, country = ?,
              latitude = ?, longitude = ?, updated_at = ?
        WHERE business_id = ?`,
      body.address,
      body.city ?? null,
      body.area ?? null,
      body.state ?? null,
      body.country ?? null,
      body.latitude ?? null,
      body.longitude ?? null,
      now,
      businessId
    );
  } else {
    await run(
      `INSERT INTO business_locations
         (id, business_id, address, city, area, state, country, latitude, longitude)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      crypto.randomUUID(),
      businessId,
      body.address,
      body.city ?? null,
      body.area ?? null,
      body.state ?? null,
      body.country ?? null,
      body.latitude ?? null,
      body.longitude ?? null
    );
  }

  return await queryOne('SELECT * FROM business_locations WHERE business_id = ?', businessId);
}

// The caller's own business, or null before setup. The client uses this to
// decide whether to send a new owner through business setup.
businessRouter.get('/', requireAuth, requireBusinessOwner, async (req, res) => {
  const business = await findBusinessForUser(req.auth.userId);
  res.json({ business: await businessWithLocation(business) });
});

businessRouter.post('/', requireAuth, requireBusinessOwner, async (req, res) => {
  const body = parse(businessCreateSchema, req.body);
  const business = await createBusiness(req.auth.userId, body);
  res.status(201).json({ business: await businessWithLocation(business) });
});

businessRouter.patch('/', requireAuth, requireBusiness, requireOwner, async (req, res) => {
  const body = parse(businessUpdateSchema, req.body);
  const columns = {
    business_name: 'business_name',
    business_category: 'business_category',
    business_description: 'business_description',
    phone: 'phone',
    email: 'email',
    logo_url: 'logo_url',
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
    await run(`UPDATE businesses SET ${assignments.join(', ')} WHERE id = ?`, ...values);
  }

  res.json({
    business: await businessWithLocation(
      await queryOne('SELECT * FROM businesses WHERE id = ?', req.business.id)
    ),
  });
});

businessRouter.get('/location', requireAuth, requireBusiness, requireOwner, async (req, res) => {
  const location = await queryOne(
    'SELECT * FROM business_locations WHERE business_id = ?',
    req.business.id
  );
  res.json({ location: publicLocation(location) });
});

// Upsert: the owner can review and re-confirm a location as often as needed.
// Responds with both shapes: `location` on its own for the location screen, and
// the whole `business` (with the location nested) so a single write can refresh
// the client's cached profile. Every other business write returns `business`,
// and the Flutter client adopts that shape to avoid a redundant refetch.
businessRouter.put('/location', requireAuth, requireBusiness, requireOwner, async (req, res) => {
  const body = parse(locationSchema, req.body);
  const location = await upsertLocation(req.business.id, body);
  res.json({
    business: await businessWithLocation(req.business),
    location: publicLocation(location),
  });
});
