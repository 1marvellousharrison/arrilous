import express from 'express';
import crypto from 'node:crypto';

import { queryOne, queryAll, run, transaction } from '../db/index.js';
import { requireAuth } from '../middleware/auth.js';
import { findBusinessForUser } from '../middleware/business.js';
import { paymentService } from '../services/payments.js';
import { notFound, badRequest, validationFailed } from '../lib/errors.js';
import {
  bankResolveSchema,
  walletFundSchema,
  walletPayoutSchema,
  walletPayoutConfirmSchema,
  toFieldErrors,
} from '../lib/validators.js';
import { randomDigits } from '../lib/password.js';

export const walletRouter = express.Router();

function parse(schema, payload) {
  const result = schema.safeParse(payload ?? {});
  if (!result.success) throw validationFailed(toFieldErrors(result.error));
  return result.data;
}

export function publicWallet(row) {
  if (!row) return null;
  return {
    id: row.id,
    ownerType: row.owner_type,
    ownerId: row.owner_id,
    balanceKobo: row.balance_kobo,
    virtualAccountBank: row.virtual_account_bank,
    virtualAccountNumber: row.virtual_account_number,
    virtualAccountName: row.virtual_account_name,
    virtualAccountReference: row.virtual_account_reference,
    updatedAt: row.updated_at,
  };
}

export function publicWalletTransaction(row) {
  return {
    id: row.id,
    direction: row.direction,
    kind: row.kind,
    channel: row.channel,
    status: row.status,
    amountKobo: row.amount_kobo,
    balanceAfterKobo: row.balance_after_kobo,
    reference: row.reference,
    providerReference: row.provider_reference,
    counterpartyBank: row.counterparty_bank,
    counterpartyBankCode: row.counterparty_bank_code,
    counterpartyAccount: row.counterparty_account,
    counterpartyName: row.counterparty_name,
    narration: row.narration,
    createdAt: row.created_at,
  };
}

async function walletForOwner(ownerType, ownerId) {
  return await queryOne(
    'SELECT * FROM wallets WHERE owner_type = ? AND owner_id = ?',
    ownerType,
    ownerId
  );
}

async function walletForUser(user) {
  const uid = user.userId || user.id;
  const role = user.role;
  const fullName = user.fullName || user.full_name;
  const u = { id: uid, role, fullName };
  if (role === 'business') {
    const business = await findBusinessForUser(uid);
    if (!business) return null;
    return await walletForOwner('business', business.id);
  }
  if (role === 'logistics_partner') {
    const org = await queryOne('SELECT * FROM logistics_organizations WHERE owner_user_id = ?', uid);
    if (!org) return null;
    return await walletForOwner('organization', org.id);
  }
  if (role === 'rider') {
    const rider = await queryOne('SELECT * FROM logistics_riders WHERE user_id = ?', uid);
    if (!rider) return null;
    return await walletForOwner('rider', rider.id);
  }
  return null;
}

async function ensureWallet(user) {
  const uid = user.userId || user.id;
  const role = user.role;
  const wallet = await walletForUser(user);
  if (wallet) return wallet;
  if (role === 'business') {
    const business = await findBusinessForUser(uid);
    if (!business) throw notFound('Finish setting up your business first.');
    const id = crypto.randomUUID();
    await run(
      `INSERT INTO wallets (id, owner_type, owner_id, owner_user_id, balance_kobo)
       VALUES (?, 'business', ?, ?, 0)`,
      id,
      business.id,
      uid
    );
    return await queryOne('SELECT * FROM wallets WHERE id = ?', id);
  }
  throw notFound('Wallet not found for this account.');
}

async function publicAccountName(user) {
  const role = user.role;
  const uid = user.userId || user.id;
  const fullName = user.fullName || user.full_name;
  if (role === 'business') {
    const business = await findBusinessForUser(uid);
    if (business) return business.business_name;
  }
  return fullName || 'Wallet';
}

walletRouter.get('/', requireAuth, async (req, res, next) => {
  try {
    const wallet = await ensureWallet(req.auth);
    res.json({ wallet: publicWallet(wallet) });
  } catch (e) {
    next(e);
  }
});

walletRouter.get('/banks', requireAuth, (_req, res, next) => {
  paymentService
    .listBanks()
    .then((banks) => res.json({ banks }))
    .catch(next);
});

walletRouter.post('/resolve-account', requireAuth, (req, res, next) => {
  const body = parse(bankResolveSchema, req.body);
  paymentService
    .resolveAccount({ bankCode: body.bank_code, accountNumber: body.account_number })
    .then((result) => res.json(result))
    .catch(next);
});

walletRouter.post('/fund', requireAuth, async (req, res, next) => {
  const body = parse(walletFundSchema, req.body);
  const wallet = await ensureWallet(req.auth);

  (async () => {
    if (body.channel === 'virtual_account') {
      if (!wallet.virtual_account_number) {
        const reference = await paymentService.createReference('VA');
        const va = await paymentService.openVirtualAccount({
          name: await publicAccountName(req.auth),
          reference,
        });
        await run(
          `UPDATE wallets SET virtual_account_bank = ?, virtual_account_number = ?, virtual_account_name = ?, virtual_account_reference = ?, updated_at = ? WHERE id = ?`,
          va.bankName,
          va.accountNumber,
          va.accountName,
          va.reference,
          new Date().toISOString(),
          wallet.id
        );
      }
      const updated = await queryOne('SELECT * FROM wallets WHERE id = ?', wallet.id);
      return res.json({
        wallet: publicWallet(updated),
        instructions: {
          bank: updated.virtual_account_bank,
          accountNumber: updated.virtual_account_number,
          accountName: updated.virtual_account_name,
          note: 'Transfer any amount to the virtual account. The system credits it on confirmation.',
        },
      });
    } else if (body.channel === 'card') {
      const reference = await paymentService.createReference('CARD');
      const charge = await paymentService.chargeCard({
        amountKobo: body.amount_kobo,
        reference,
        cardNumber: body.card_number,
      });
      if (charge.status !== 'successful') {
        throw badRequest('Card payment was declined. Try a different card.');
      }
      const txnId = crypto.randomUUID();
      const newBalance = wallet.balance_kobo + body.amount_kobo;
      await transaction(async () => {
        await run(
          `INSERT INTO wallet_transactions (id, wallet_id, direction, kind, channel, status, amount_kobo, balance_after_kobo, reference, provider_reference, narration, created_at, updated_at)
           VALUES (?, ?, 'credit', 'funding', 'card', 'successful', ?, ?, ?, ?, ?, ?, ?)`,
          txnId,
          wallet.id,
          body.amount_kobo,
          newBalance,
          reference,
          charge.providerReference,
          body.narration,
          new Date().toISOString(),
          new Date().toISOString()
        );
        await run('UPDATE wallets SET balance_kobo = ?, updated_at = ? WHERE id = ?', newBalance, new Date().toISOString(), wallet.id);
      });
      const updated = await queryOne('SELECT * FROM wallets WHERE id = ?', wallet.id);
      const txn = await queryOne('SELECT * FROM wallet_transactions WHERE id = ?', txnId);
      return res.json({ wallet: publicWallet(updated), transaction: publicWalletTransaction(txn) });
    }
    throw badRequest('Unsupported channel.');
  })().catch(next);
});

walletRouter.post('/webhook', express.json({ type: '*/*' }), (req, res, next) => {
  (async () => {
    const signature = req.get('x-dee-signature') || req.get('x-paystack-signature') || req.get('x-webhook-signature');
    const raw = JSON.stringify(req.body);
    let payload;
    try {
      payload = await paymentService.verifyWebhook({ signature, rawBody: raw });
    } catch (e) {
      return res.status(400).json({ status: 'bad_signature' });
    }
    if (payload.event === 'transfer.success' || payload.event === 'charge.success') {
      const data = payload.data || {};
      const reference = data.reference;
      const amountKobo = Number(data.amount_kobo || data.amount || 0);
      const w = await queryOne('SELECT * FROM wallets WHERE virtual_account_reference = ?', reference);
      if (w && amountKobo > 0) {
        const txn = await queryOne('SELECT id, status FROM wallet_transactions WHERE reference = ? AND wallet_id = ?', reference, w.id);
        const newBalance = w.balance_kobo + amountKobo;
        await transaction(async () => {
          if (!txn) {
            await run(
              `INSERT INTO wallet_transactions (id, wallet_id, direction, kind, channel, status, amount_kobo, balance_after_kobo, reference, provider_reference, created_at, updated_at)
               VALUES (?, ?, 'credit', 'funding', 'virtual_account', 'successful', ?, ?, ?, ?, ?, ?)`,
              crypto.randomUUID(),
              w.id,
              amountKobo,
              newBalance,
              reference,
              data.provider_reference || reference,
              new Date().toISOString(),
              new Date().toISOString()
            );
          } else if (txn.status !== 'successful') {
            await run(
              `UPDATE wallet_transactions SET status = 'successful', balance_after_kobo = ?, amount_kobo = ?, updated_at = ? WHERE id = ?`,
              newBalance,
              amountKobo,
              new Date().toISOString(),
              txn.id
            );
          }
          await run('UPDATE wallets SET balance_kobo = ?, updated_at = ? WHERE id = ?', newBalance, new Date().toISOString(), w.id);
        });
      }
    }
    res.json({ status: 'ok' });
  })().catch((err) => res.status(200).json({ status: 'ignored', error: err.code || 'unknown' }));
});

walletRouter.get('/transactions', requireAuth, async (req, res, next) => {
  try {
    const wallet = await ensureWallet(req.auth);
    const txns = await queryAll('SELECT * FROM wallet_transactions WHERE wallet_id = ? ORDER BY created_at DESC LIMIT 50', wallet.id);
    res.json({ transactions: txns.map(publicWalletTransaction) });
  } catch (e) {
    next(e);
  }
});

walletRouter.post('/payout', requireAuth, async (req, res, next) => {
  const body = parse(walletPayoutSchema, req.body);
  const wallet = await ensureWallet(req.auth);

  (async () => {
    if (body.amount_kobo > wallet.balance_kobo) {
      throw badRequest('Insufficient balance.');
    }
    const reference = await paymentService.createReference('PAYOUT');
    const txnId = crypto.randomUUID();
    await transaction(async () => {
      await run(
        `INSERT INTO wallet_transactions (id, wallet_id, direction, kind, channel, status, amount_kobo, balance_after_kobo, reference, counterparty_bank, counterparty_bank_code, counterparty_account, counterparty_name, narration, created_at, updated_at)
         VALUES (?, ?, 'debit', 'payout', 'payout', 'pending', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        txnId,
        wallet.id,
        body.amount_kobo,
        null,
        reference,
        '', // not used
        body.bank_code,
        body.account_number,
        body.account_name,
        body.narration,
        new Date().toISOString(),
        new Date().toISOString()
      );
    });
    const otpId = crypto.randomUUID();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
    const otpPlain = randomDigits(6);
    await run(
      `INSERT INTO wallet_payout_otps (id, wallet_transaction_id, otp_hash, expires_at)
       VALUES (?, ?, ?, ?)`,
      otpId,
      txnId,
      crypto.createHash('sha256').update(otpPlain).digest('hex'),
      expiresAt
    );
    res.json({
      transactionReference: reference,
      message: 'Enter the 6-digit code sent to confirm this payout.',
      otp: process.env.OTP_EXPOSE_IN_RESPONSE === 'true' ? otpPlain : undefined,
    });
  })().catch(next);
});

walletRouter.post('/payout/confirm', requireAuth, async (req, res, next) => {
  const body = parse(walletPayoutConfirmSchema, req.body);
  const wallet = await ensureWallet(req.auth);

  (async () => {
    const pending = await queryOne(
      'SELECT * FROM wallet_transactions WHERE wallet_id = ? AND kind = \'payout\' AND status = \'pending\' ORDER BY created_at DESC LIMIT 1',
      wallet.id
    );
    if (!pending) throw badRequest('No pending payout to confirm.');
    const otp = await queryOne(
      'SELECT * FROM wallet_payout_otps WHERE wallet_transaction_id = ? AND consumed_at IS NULL ORDER BY created_at DESC LIMIT 1',
      pending.id
    );
    if (!otp) throw badRequest('OTP expired or not found.');
    if (new Date(otp.expires_at) < new Date()) throw badRequest('OTP expired.');
    const given = crypto.createHash('sha256').update(body.otp).digest('hex');
    if (otp.otp_hash !== given) {
      await run('UPDATE wallet_payout_otps SET attempts = attempts + 1 WHERE id = ?', otp.id);
      throw badRequest('Invalid code.');
    }
    if (otp.attempts >= 5) throw badRequest('Too many attempts.');
    const newBalance = wallet.balance_kobo - pending.amount_kobo;
    if (newBalance < 0) throw badRequest('Insufficient balance.');
    const payout = await paymentService.sendPayout({
      amountKobo: pending.amount_kobo,
      reference: pending.reference,
      bankCode: pending.counterparty_bank_code,
      accountNumber: pending.counterparty_account,
      accountName: pending.counterparty_name,
    });
    await transaction(async () => {
      await run(
        `UPDATE wallet_transactions SET status = 'successful', balance_after_kobo = ?, provider_reference = ?, updated_at = ? WHERE id = ?`,
        newBalance,
        payout.providerReference,
        new Date().toISOString(),
        pending.id
      );
      await run('UPDATE wallets SET balance_kobo = ?, updated_at = ? WHERE id = ?', newBalance, new Date().toISOString(), wallet.id);
      await run('UPDATE wallet_payout_otps SET consumed_at = ? WHERE id = ?', new Date().toISOString(), otp.id);
    });
    const updatedWallet = await queryOne('SELECT * FROM wallets WHERE id = ?', wallet.id);
    const updatedTxn = await queryOne('SELECT * FROM wallet_transactions WHERE id = ?', pending.id);
    res.json({ wallet: publicWallet(updatedWallet), transaction: publicWalletTransaction(updatedTxn) });
  })().catch(next);
});

export default walletRouter;
