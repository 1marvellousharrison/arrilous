import crypto from 'node:crypto';

import { IntegrationService } from './extension.js';
import { badRequest } from '../lib/errors.js';

/**
 * The banks the simulated provider knows about. Real gateways return a list
 * like this from their API; keeping it here means the wallet flow can be built
 * and exercised end to end before a live gateway is wired in.
 */
const SIMULATED_BANKS = Object.freeze([
  { code: '044', name: 'Access Bank' },
  { code: '058', name: 'Guaranty Trust Bank' },
  { code: '011', name: 'First Bank of Nigeria' },
  { code: '057', name: 'Zenith Bank' },
  { code: '033', name: 'United Bank for Africa' },
  { code: '214', name: 'First City Monument Bank' },
  { code: '070', name: 'Fidelity Bank' },
  { code: '232', name: 'Sterling Bank' },
  { code: '035', name: 'Wema Bank' },
  { code: '999', name: 'Simulated Test Bank' },
]);

const VIRTUAL_ACCOUNT_BANK = 'Wema Bank';

class PaymentService extends IntegrationService {
  constructor() {
    super(
      'payments',
      'Payment references, a simulated wallet gateway, webhook verification, and payment status.',
      [
        'createReference',
        'listBanks',
        'resolveAccount',
        'openVirtualAccount',
        'chargeCard',
        'sendPayout',
        'verifyWebhook',
        'applyProviderStatus',
      ]
    );
  }

  /**
   * A reference that ties a wallet or order to one provider attempt. Unique
   * enough to be the idempotency key the webhook arrives with.
   */
  async createReference(prefix = 'WTX') {
    const suffix = `${Date.now().toString(36)}${crypto.randomBytes(3).toString('hex')}`.toUpperCase();
    return `${prefix.toUpperCase()}-${suffix}`;
  }

  /** The list of transfer destinations the wallet can pay out to. */
  async listBanks() {
    return SIMULATED_BANKS.map((bank) => ({ ...bank }));
  }

  /**
   * Resolves an account number to the name on it. The simulated provider
   * derives a stable fake name from the digits, so the same account always
   * resolves the same way within a demo.
   */
  async resolveAccount({ bankCode, accountNumber }) {
    const bank = this._bank(bankCode);
    const digits = String(accountNumber ?? '').trim();
    if (!/^\d{10}$/.test(digits)) {
      throw badRequest('Account number must be 10 digits.');
    }
    const names = ['ADEBAYO', 'CHIAMAKA', 'EMEKA', 'FUNMILAYO', 'IBRAHIM', 'NGOZI', 'TUNDE', 'YETUNDE'];
    const surnames = ['OKAFOR', 'BALOGUN', 'ADELEKE', 'MUSA', 'EWUZIE', 'OGUNDIPE', 'CHUKWU', 'BELLO'];
    const seed = Number(digits.slice(-2));
    const accountName = `${names[seed % names.length]} ${surnames[(seed * 7) % surnames.length]}`;
    return { bankCode: bank.code, bankName: bank.name, accountNumber: digits, accountName };
  }

  /**
   * Opens a dedicated virtual account a customer can transfer into. The
   * simulated number is deterministic from the reference and the name is the
   * wallet owner's, so the statement the customer sees matches the business.
   */
  async openVirtualAccount({ name, reference }) {
    const hash = crypto.createHash('sha256').update(String(reference)).digest();
    let accountNumber = '';
    for (let i = 0; i < 10; i += 1) accountNumber += String(hash[i] % 10);
    return {
      reference,
      bankName: VIRTUAL_ACCOUNT_BANK,
      accountNumber,
      accountName: (name && String(name).trim()) || 'Dee Business Wallet',
    };
  }

  /**
   * Charges a card. In simulation a card ending in 0000 is declined, so the
   * failure path is reachable without a real gateway; everything else succeeds.
   */
  async chargeCard({ amountKobo, reference, cardNumber }) {
    if (Number(amountKobo) <= 0) throw badRequest('Enter an amount to add.');
    const digits = String(cardNumber ?? '').replace(/\D/g, '');
    if (digits.endsWith('0000')) {
      return { reference, providerReference: reference, status: 'failed' };
    }
    return { reference, providerReference: reference, status: 'successful' };
  }

  /** Sends a payout to another bank. The simulated provider always accepts it. */
  async sendPayout({ amountKobo, reference, bankCode, accountNumber, accountName }) {
    if (Number(amountKobo) <= 0) throw badRequest('Enter an amount to send.');
    const bank = this._bank(bankCode);
    const digits = String(accountNumber ?? '').trim();
    if (!/^\d{10}$/.test(digits)) {
      throw badRequest('Account number must be 10 digits.');
    }
    return {
      reference,
      providerReference: reference,
      status: 'successful',
      bankCode: bank.code,
      bankName: bank.name,
      accountNumber: digits,
      accountName,
    };
  }

  /**
   * Verifies a provider webhook signature. Real gateways sign the raw body with
   * a shared secret; the secret is read from the environment here, never stored
   * on this object, so it cannot be logged or serialised.
   */
  async verifyWebhook({ signature, rawBody }) {
    const given = String(signature ?? '');
    if (!given) throw badRequest('Missing webhook signature.');
    const expected = this.signWebhook(rawBody);
    const a = Buffer.from(given, 'utf8');
    const b = Buffer.from(expected, 'utf8');
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
      throw badRequest('Invalid webhook signature.');
    }
    try {
      return rawBody ? JSON.parse(rawBody) : {};
    } catch {
      throw badRequest('Webhook body is not valid JSON.');
    }
  }

  /**
   * Produces the signature the simulated provider would send. This is what lets
   * the dev flow and the tests stand in for a real gateway.
   */
  signWebhook(rawBody) {
    const secret = process.env.PAYMENT_WEBHOOK_SECRET ?? 'simulated-webhook-secret';
    return crypto.createHmac('sha256', secret).update(String(rawBody ?? '')).digest('hex');
  }

  /** Maps a provider's status onto the wallet's three states. */
  async applyProviderStatus({ providerStatus }) {
    const value = String(providerStatus ?? '').toLowerCase();
    if (['success', 'successful', 'completed', 'paid'].includes(value)) return 'successful';
    if (['failed', 'declined', 'reversed', 'cancelled'].includes(value)) return 'failed';
    return 'pending';
  }

  _bank(bankCode) {
    const code = String(bankCode ?? '').trim();
    const bank = SIMULATED_BANKS.find((entry) => entry.code === code);
    if (!bank) throw badRequest('Choose a supported bank.');
    return bank;
  }
}

export const paymentService = new PaymentService();

/** Exposed for the seed and tests to mint a believable virtual account number. */
export const simulatedBankName = VIRTUAL_ACCOUNT_BANK;
