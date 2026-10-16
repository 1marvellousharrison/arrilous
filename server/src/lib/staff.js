import { queryOne, queryAll, run } from '../db/index.js';
import { randomDigits } from './password.js';
import { conflict } from './errors.js';

/**
 * Staff codes (docs/staff-accounts.md).
 *
 * A staff's permanent login is `<business_code>-<seq>`, e.g. "ABC47-03". The
 * business_code is a stable prefix snapshotted once from the business name; the
 * sequence counts the business's staff. Because the prefix is globally unique,
 * so is every code.
 */

/** Uppercase the first three letters of a name, padding short names with "X". */
export function lettersPrefix(businessName) {
  const letters = String(businessName ?? '')
    .toUpperCase()
    .replace(/[^A-Z]/g, '');
  if (letters.length === 0) return 'BIZ';
  return letters.slice(0, 3).padEnd(3, 'X');
}

/**
 * Allocates a business code that no other business holds. Three letters from the
 * name plus two random digits, regenerated on the rare clash — random rather
 * than sequential so the code is not guessable from a business's age.
 */
export async function generateBusinessCode(businessName) {
  const prefix = lettersPrefix(businessName);
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const candidate = `${prefix}${randomDigits(2)}`;
    const clash = await queryOne(
      'SELECT id FROM businesses WHERE business_code = ?',
      candidate
    );
    if (!clash) return candidate;
  }
  throw new Error('Could not allocate a unique business code.');
}

/**
 * Returns a business's code, creating and persisting one on first use.
 *
 * A code is set when the business is created; this also backfills businesses
 * that existed before staff accounts, so the first staff add always succeeds.
 */
export async function ensureBusinessCode(business) {
  if (business?.business_code) return business.business_code;
  const code = await generateBusinessCode(business?.business_name ?? '');
  await run(
    'UPDATE businesses SET business_code = ?, updated_at = ? WHERE id = ?',
    code,
    new Date().toISOString(),
    business.id
  );
  return code;
}

/** The next free sequence for a business: highest existing + 1. */
export async function nextStaffCode(businessCode, businessId) {
  const rows = await queryAll(
    'SELECT staff_code FROM staff_members WHERE business_id = ?',
    businessId
  );
  let highest = 0;
  for (const row of rows) {
    const seq = Number.parseInt(String(row.staff_code).split('-')[1] ?? '', 10);
    if (Number.isFinite(seq) && seq > highest) highest = seq;
  }
  if (highest >= 99) {
    throw conflict('This business has reached the maximum number of staff codes.');
  }
  return `${businessCode}-${String(highest + 1).padStart(2, '0')}`;
}

/** A staff link row joined to its user, by permanent code. */
export async function findStaffByCode(staffCode) {
  return queryOne(
    `SELECT sm.*, u.full_name, u.phone, u.email, u.status AS user_status
       FROM staff_members sm
       JOIN users u ON u.id = sm.user_id
      WHERE sm.staff_code = ?`,
    staffCode
  );
}

export function publicStaff(row) {
  if (!row) return null;
  return {
    id: row.id,
    userId: row.user_id,
    businessId: row.business_id,
    fullName: row.full_name,
    phone: row.phone ?? null,
    staffCode: row.staff_code,
    status: row.status,
    activatedAt: row.activated_at ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    ...(row.sales_count !== undefined && row.sales_count !== null
      ? { salesCount: Number(row.sales_count) }
      : {}),
  };
}
