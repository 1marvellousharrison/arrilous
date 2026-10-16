import crypto from 'node:crypto';
import { queryOne, run } from '../db/index.js';

/**
 * Business wallet helpers shared by the wallet routes and the sale path.
 *
 * The real money always belongs to the owner: a sale recorded by a staff still
 * credits the business's wallet. A wallet is created lazily, on first need, so a
 * business that has never funded or sold still has an empty one to credit.
 */

async function walletForBusiness(businessId) {
  return queryOne(
    "SELECT * FROM wallets WHERE owner_type = 'business' AND owner_id = ?",
    businessId
  );
}

export async function ensureBusinessWallet(business) {
  const existing = await walletForBusiness(business.id);
  if (existing) return existing;

  const id = crypto.randomUUID();
  await run(
    `INSERT INTO wallets (id, owner_type, owner_id, owner_user_id, balance_kobo)
     VALUES (?, 'business', ?, ?, 0)`,
    id,
    business.id,
    business.owner_user_id
  );
  return await queryOne('SELECT * FROM wallets WHERE id = ?', id);
}

/**
 * Credits the owner's wallet for a sale that has just been marked paid.
 *
 * Idempotent by construction: the ledger reference is `sale:<transactionId>`,
 * which is UNIQUE, and the existing row is checked first. So a retried status
 * update (or a status that passes through paid twice for any reason) can never
 * double-credit the owner.
 *
 * Callers run this inside the same database transaction as the status change, so
 * the ledger and the sale can never disagree. Returns the new balance, or null
 * when there was nothing to credit.
 */
export async function creditSaleToWallet(business, transaction) {
  const total = Number(transaction.total_kobo ?? 0);
  if (!Number.isFinite(total) || total <= 0) return null;

  const reference = `sale:${transaction.id}`;
  const already = await queryOne(
    'SELECT id FROM wallet_transactions WHERE reference = ?',
    reference
  );
  if (already) return null;

  const wallet = await ensureBusinessWallet(business);
  const newBalance = wallet.balance_kobo + total;
  const now = new Date().toISOString();

  await run(
    `INSERT INTO wallet_transactions
       (id, wallet_id, direction, kind, channel, status, amount_kobo,
        balance_after_kobo, reference, narration, created_at, updated_at)
     VALUES (?, ?, 'credit', 'sale', 'sale', 'successful', ?, ?, ?, ?, ?, ?)`,
    crypto.randomUUID(),
    wallet.id,
    total,
    newBalance,
    reference,
    `Sale ${transaction.transaction_number}`,
    now,
    now
  );
  await run(
    'UPDATE wallets SET balance_kobo = ?, updated_at = ? WHERE id = ?',
    newBalance,
    now,
    wallet.id
  );

  return newBalance;
}
