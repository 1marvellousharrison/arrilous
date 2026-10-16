import express from 'express';
import crypto from 'node:crypto';
import { config } from '../config.js';
import { queryOne, run } from '../db/index.js';
import { requireAuth } from '../middleware/auth.js';
import { requireBusinessOwner, requireBusiness, requireOwner, requireBusinessEditToken, findBusinessForUser } from '../middleware/business.js';
import { rateLimit } from '../middleware/rateLimit.js';
import {
  conflict,
  validationFailed,
  tooManyRequests,
  badRequest,
  notFound,
  serviceUnavailable,
} from '../lib/errors.js';
import { randomDigits, sha256 } from '../lib/password.js';
import { signBusinessEditToken } from '../lib/jwt.js';
import { maskEmail } from '../lib/normalise.js';
import { emailService } from '../services/email.js';
import { generateBusinessCode } from '../lib/staff.js';
import {
  businessCreateSchema,
  businessUpdateSchema,
  locationSchema,
  verifyOtpSchema,
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

businessRouter.patch(
  '/',
  requireAuth,
  requireBusiness,
  requireOwner,
  requireBusinessEditToken(),
  async (req, res) => {
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
  }
);

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
businessRouter.put(
  '/location',
  requireAuth,
  requireBusiness,
  requireOwner,
  requireBusinessEditToken({ onlyWhenPresent: true }),
  async (req, res) => {
    const body = parse(locationSchema, req.body);
    const location = await upsertLocation(req.business.id, body);
    res.json({
      business: await businessWithLocation(req.business),
      location: publicLocation(location),
    });
  }
);

// ─────────────────────────────────────────────────────────────
// The owner-confirmation gate for editing an existing business.
//
// A code is emailed to the owner's account address; verifying it mints the
// short-lived token the profile and location writes demand. See
// docs/business-details-edit-otp.md.
// ─────────────────────────────────────────────────────────────

// POST /api/v1/business/edit-otp
businessRouter.post(
  '/edit-otp',
  requireAuth,
  requireBusiness,
  requireOwner,
  rateLimit({ keyPrefix: 'business-edit-otp', max: 10 }),
  async (req, res) => {
    const now = new Date();
    const cooldownUntil = new Date(
      now.getTime() - config.businessEdit.resendCooldownSeconds * 1000
    );

    const recent = await queryOne(
      `SELECT id FROM business_edit_otps
        WHERE business_id = ? AND created_at > ?
        ORDER BY created_at DESC LIMIT 1`,
      req.business.id,
      cooldownUntil.toISOString()
    );
    if (recent) {
      throw tooManyRequests(
        `Please wait ${config.businessEdit.resendCooldownSeconds} seconds before requesting another code.`
      );
    }

    const owner = await queryOne(
      'SELECT * FROM users WHERE id = ?',
      req.business.owner_user_id
    );
    if (!owner?.email) {
      throw badRequest('Add an email address to your account before editing your business details.');
    }

    const code = randomDigits(config.otp.length);
    const expiresAt = new Date(
      now.getTime() + config.businessEdit.ttlSeconds * 1000
    ).toISOString();
    const id = crypto.randomUUID();

    await run(
      `INSERT INTO business_edit_otps
         (id, business_id, user_id, code_hash, max_attempts, expires_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
      id,
      req.business.id,
      owner.id,
      sha256(`${owner.id}:${code}`),
      config.otp.maxAttempts,
      expiresAt
    );

    try {
      await emailService.sendBusinessEditCode({
        to: owner.email,
        code,
        ttlSeconds: config.businessEdit.ttlSeconds,
      });
    } catch {
      // A code nobody can receive must not linger as a usable challenge.
      await run('DELETE FROM business_edit_otps WHERE id = ?', id);
      throw serviceUnavailable(
        'We could not send your confirmation code right now. Please try again shortly.'
      );
    }

    res.status(201).json({
      status: 'success',
      challenge_id: id,
      channel: 'email',
      destination: maskEmail(owner.email),
      expires_at: expiresAt,
      ...(config.otp.exposeInResponse ? { dev_code: code } : {}),
    });
  }
);

// POST /api/v1/business/edit-otp/verify
businessRouter.post(
  '/edit-otp/verify',
  requireAuth,
  requireBusiness,
  requireOwner,
  rateLimit({ keyPrefix: 'business-edit-verify', max: 15 }),
  async (req, res) => {
    const body = parse(verifyOtpSchema, req.body);
    const challenge = await queryOne(
      'SELECT * FROM business_edit_otps WHERE id = ?',
      body.challenge_id
    );

    // The challenge is scoped to a business: a code minted for one owner can
    // never be spent against another.
    if (!challenge || challenge.business_id !== req.business.id) {
      throw notFound('This confirmation request is no longer valid.');
    }
    if (challenge.consumed_at) throw badRequest('This code has already been used.');
    if (challenge.attempts >= challenge.max_attempts) {
      throw tooManyRequests('Too many incorrect codes. Request a new one.');
    }
    if (new Date(challenge.expires_at).getTime() <= Date.now()) {
      throw badRequest('This code has expired. Request a new one.');
    }

    if (sha256(`${challenge.user_id}:${body.code}`) !== challenge.code_hash) {
      await run(
        'UPDATE business_edit_otps SET attempts = attempts + 1 WHERE id = ?',
        challenge.id
      );
      throw badRequest('Incorrect confirmation code.');
    }

    await run(
      'UPDATE business_edit_otps SET consumed_at = ? WHERE id = ?',
      new Date().toISOString(),
      challenge.id
    );

    const token = signBusinessEditToken(req.business.owner_user_id);
    res.json({
      status: 'success',
      edit_token: token.token,
      expires_at: token.expiresAt,
    });
  }
);
