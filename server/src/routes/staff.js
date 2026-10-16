import express from 'express';
import crypto from 'node:crypto';
import { queryOne, queryAll, run, transaction } from '../db/index.js';
import { requireAuth } from '../middleware/auth.js';
import { requireBusiness, requireOwner } from '../middleware/business.js';
import { rateLimit } from '../middleware/rateLimit.js';
import { conflict, notFound, forbidden, validationFailed } from '../lib/errors.js';
import {
  staffCreateSchema,
  staffUpdateSchema,
  staffClaimSchema,
  staffActivateSchema,
  toFieldErrors,
} from '../lib/validators.js';
import {
  ensureBusinessCode,
  nextStaffCode,
  findStaffByCode,
  publicStaff,
} from '../lib/staff.js';
import { hashPassword, randomToken } from '../lib/password.js';
import { publicTransaction } from './transactions.js';

/**
 * Staff accounts (docs/staff-accounts.md).
 *
 * Two audiences share this router:
 *   * the owner, who adds / lists / disables staff and views each one's sales;
 *   * the staff themselves, who are not signed in yet and only reach the public
 *     claim and activate steps to redeem the code the owner handed them.
 *
 * The owner never sets or sees a staff password: adding a staff issues a code,
 * and the staff sets their own password at activation.
 */
export const staffRouter = express.Router();

function parse(schema, payload) {
  const result = schema.safeParse(payload ?? {});
  if (!result.success) throw validationFailed(toFieldErrors(result.error));
  return result.data;
}

const STAFF_SELECT = `
  SELECT sm.*, u.full_name, u.phone,
         (SELECT COUNT(*) FROM transactions t WHERE t.created_by_user_id = sm.user_id)
           AS sales_count
    FROM staff_members sm
    JOIN users u ON u.id = sm.user_id`;

async function findOwnedStaff(businessId, staffId) {
  const row = await queryOne(`${STAFF_SELECT} WHERE sm.id = ? AND sm.business_id = ?`, staffId, businessId);
  if (!row) throw notFound('That staff member does not exist.');
  return row;
}

// ─────────────────────────────────────────────────────────────
// Public: activation (the staff has no session yet)
// ─────────────────────────────────────────────────────────────

// POST /api/v1/staff/claim — step 1: does the code exist and is it unclaimed?
staffRouter.post(
  '/claim',
  rateLimit({ keyPrefix: 'staff-claim', max: 20 }),
  async (req, res) => {
    const body = parse(staffClaimSchema, req.body);
    const row = await findStaffByCode(body.staff_code);
    if (!row) {
      throw notFound('That staff code was not found. Check it with the business owner.');
    }
    if (row.status === 'disabled') throw forbidden('This staff code has been disabled.');
    if (row.status !== 'invited') {
      throw conflict('This code has already been activated. Sign in instead.', 'staff_code_claimed');
    }

    const business = await queryOne(
      'SELECT business_name FROM businesses WHERE id = ?',
      row.business_id
    );
    return res.json({
      staff: { fullName: row.full_name },
      business: { businessName: business?.business_name ?? null },
    });
  }
);

// POST /api/v1/staff/activate — step 2: set the name + password. No auto-login;
// the staff then signs in with code + password like anyone else.
staffRouter.post(
  '/activate',
  rateLimit({ keyPrefix: 'staff-activate', max: 20 }),
  async (req, res) => {
    const body = parse(staffActivateSchema, req.body);
    const row = await findStaffByCode(body.staff_code);
    if (!row) {
      throw notFound('That staff code was not found. Check it with the business owner.');
    }
    if (row.status === 'disabled') throw forbidden('This staff code has been disabled.');
    if (row.status !== 'invited') {
      throw conflict('This code has already been activated. Sign in instead.', 'staff_code_claimed');
    }

    const passwordHash = await hashPassword(body.password);
    const now = new Date().toISOString();

    await transaction(async () => {
      await run(
        `UPDATE users SET full_name = COALESCE(?, full_name), password_hash = ?, updated_at = ?
          WHERE id = ?`,
        body.full_name ?? null,
        passwordHash,
        now,
        row.user_id
      );
      await run(
        `UPDATE staff_members SET status = 'active', activated_at = ?, updated_at = ?
          WHERE id = ?`,
        now,
        now,
        row.id
      );
    });

    return res.json({ status: 'success' });
  }
);

// ─────────────────────────────────────────────────────────────
// Owner: manage the business's staff
// ─────────────────────────────────────────────────────────────

// POST /api/v1/staff — add a staff, issuing their permanent code.
staffRouter.post('/', requireAuth, requireBusiness, requireOwner, async (req, res) => {
  const body = parse(staffCreateSchema, req.body);

  // Re-read the business so a code set by a concurrent add is seen rather than
  // overwritten with a fresh one.
  const business = await queryOne('SELECT * FROM businesses WHERE id = ?', req.business.id);
  const businessCode = await ensureBusinessCode(business);
  const staffCode = await nextStaffCode(businessCode, business.id);

  const userId = crypto.randomUUID();
  const staffId = crypto.randomUUID();
  // A placeholder hash the owner does not know and the staff will replace at
  // activation; login is impossible until then regardless of staff_members.status.
  const placeholderHash = await hashPassword(randomToken(32));

  await transaction(async () => {
    await run(
      `INSERT INTO users (id, full_name, email, phone, password_hash, role, status)
       VALUES (?, ?, NULL, ?, ?, 'staff', 'active')`,
      userId,
      body.full_name,
      body.phone ?? null,
      placeholderHash
    );
    await run(
      `INSERT INTO staff_members (id, user_id, business_id, staff_code, status, created_by)
       VALUES (?, ?, ?, ?, 'invited', ?)`,
      staffId,
      userId,
      business.id,
      staffCode,
      req.auth.userId
    );
  });

  const created = await findOwnedStaff(business.id, staffId);
  return res.status(201).json({ staff: publicStaff(created) });
});

// GET /api/v1/staff — the business's staff.
staffRouter.get('/', requireAuth, requireBusiness, requireOwner, async (req, res) => {
  const rows = await queryAll(
    `${STAFF_SELECT} WHERE sm.business_id = ? ORDER BY sm.created_at ASC`,
    req.business.id
  );
  return res.json({ staff: rows.map(publicStaff) });
});

// GET /api/v1/staff/:id — one staff.
staffRouter.get('/:id', requireAuth, requireBusiness, requireOwner, async (req, res) => {
  const row = await findOwnedStaff(req.business.id, req.params.id);
  return res.json({ staff: publicStaff(row) });
});

// PATCH /api/v1/staff/:id — rename, re-phone, or disable/re-enable.
staffRouter.patch('/:id', requireAuth, requireBusiness, requireOwner, async (req, res) => {
  const existing = await queryOne(
    'SELECT * FROM staff_members WHERE id = ? AND business_id = ?',
    req.params.id,
    req.business.id
  );
  if (!existing) throw notFound('That staff member does not exist.');

  const body = parse(staffUpdateSchema, req.body);
  const now = new Date().toISOString();

  await transaction(async () => {
    const assignments = [];
    const values = [];
    if (body.full_name !== undefined) {
      assignments.push('full_name = ?');
      values.push(body.full_name);
    }
    if (body.phone !== undefined) {
      assignments.push('phone = ?');
      values.push(body.phone ?? null);
    }
    if (assignments.length > 0) {
      assignments.push('updated_at = ?');
      values.push(now, existing.user_id);
      await run(`UPDATE users SET ${assignments.join(', ')} WHERE id = ?`, ...values);
    }

    if (body.status !== undefined) {
      await run(
        'UPDATE staff_members SET status = ?, updated_at = ? WHERE id = ?',
        body.status,
        now,
        existing.id
      );
      // Disabling must end live sessions, not just block the next login.
      if (body.status === 'disabled') {
        await run(
          'UPDATE refresh_tokens SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL',
          now,
          existing.user_id
        );
      }
    }
  });

  const updated = await findOwnedStaff(req.business.id, existing.id);
  return res.json({ staff: publicStaff(updated) });
});

// GET /api/v1/staff/:id/transactions — only this staff's sales.
staffRouter.get('/:id/transactions', requireAuth, requireBusiness, requireOwner, async (req, res) => {
  const staff = await queryOne(
    'SELECT * FROM staff_members WHERE id = ? AND business_id = ?',
    req.params.id,
    req.business.id
  );
  if (!staff) throw notFound('That staff member does not exist.');

  const rows = await queryAll(
    `SELECT * FROM transactions
      WHERE business_id = ? AND created_by_user_id = ?
      ORDER BY created_at DESC LIMIT 100`,
    req.business.id,
    staff.user_id
  );
  return res.json({ transactions: rows.map((row) => publicTransaction(row)) });
});

export default staffRouter;
