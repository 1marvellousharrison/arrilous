import test, { describe } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { api, createBusinessOwner, createUser } from './helpers.js';

describe('wallet', () => {
  test('business owner gets a wallet (auto-created) with zero balance', async () => {
    const owner = await createBusinessOwner('Wallet Shop');
    const res = await api('GET', '/wallet', { token: owner.token });
    assert.equal(res.status, 200);
    assert.ok(res.body.wallet);
    assert.equal(res.body.wallet.balanceKobo, 0);
    assert.equal(res.body.wallet.ownerType, 'business');
  });

  test('returns list of supported banks', async () => {
    const owner = await createBusinessOwner();
    const res = await api('GET', '/wallet/banks', { token: owner.token });
    assert.equal(res.status, 200);
    assert.ok(Array.isArray(res.body.banks));
    assert.ok(res.body.banks.length > 0);
  });

  test('resolves bank account number to name', async () => {
    const owner = await createBusinessOwner();
    const banks = await api('GET', '/wallet/banks', { token: owner.token });
    const res = await api('POST', '/wallet/resolve-account', {
      token: owner.token,
      body: { bank_code: banks.body.banks[0].code, account_number: '0123456789' },
    });
    assert.equal(res.status, 200);
    assert.equal(res.body.accountNumber, '0123456789');
    assert.ok(res.body.accountName);
  });

  test('rejects invalid account number', async () => {
    const owner = await createBusinessOwner();
    const banks = await api('GET', '/wallet/banks', { token: owner.token });
    const res = await api('POST', '/wallet/resolve-account', {
      token: owner.token,
      body: { bank_code: banks.body.banks[0].code, account_number: '12345' },
    });
    assert.equal(res.status, 422);
  });

  test('virtual account funding returns instructions', async () => {
    const owner = await createBusinessOwner('VA Shop');
    const res = await api('POST', '/wallet/fund', {
      token: owner.token,
      body: { amount_kobo: 10000, channel: 'virtual_account' },
    });
    assert.equal(res.status, 200);
    assert.ok(res.body.wallet);
    assert.ok(res.body.instructions);
    assert.ok(res.body.instructions.accountNumber);
    assert.ok(res.body.instructions.bank);
  });

  test('card funding credits wallet', async () => {
    const owner = await createBusinessOwner('Card Shop');
    const res = await api('POST', '/wallet/fund', {
      token: owner.token,
      body: { amount_kobo: 500000, channel: 'card', card_number: '4242424242424242' },
    });
    assert.equal(res.status, 200);
    assert.equal(res.body.wallet.balanceKobo, 500000);
    assert.ok(res.body.transaction);
    assert.equal(res.body.transaction.status, 'successful');
  });

  test('declined card returns error', async () => {
    const owner = await createBusinessOwner('Bad Card');
    const res = await api('POST', '/wallet/fund', {
      token: owner.token,
      body: { amount_kobo: 10000, channel: 'card', card_number: '4000000000000000' },
    });
    assert.equal(res.status, 400);
  });

  test('payout flow: create pending then confirm with OTP', async () => {
    const owner = await createBusinessOwner('Pay Shop');
    // fund
    await api('POST', '/wallet/fund', {
      token: owner.token,
      body: { amount_kobo: 200000, channel: 'card', card_number: '5555555555554444' },
    });
    // banks
    const banks = await api('GET', '/wallet/banks', { token: owner.token });
    const payout = await api('POST', '/wallet/payout', {
      token: owner.token,
      body: {
        amount_kobo: 50000,
        bank_code: banks.body.banks[0].code,
        account_number: '1234567890',
        account_name: 'Tunde Balogun',
      },
    });
    assert.equal(payout.status, 200);
    assert.ok(payout.body.transactionReference);
    assert.ok(payout.body.otp); // exposed in test env
    const confirm = await api('POST', '/wallet/payout/confirm', {
      token: owner.token,
      body: { otp: payout.body.otp },
    });
    assert.equal(confirm.status, 200);
    assert.equal(confirm.body.wallet.balanceKobo, 150000);
    assert.equal(confirm.body.transaction.status, 'successful');
  });

  test('insufficient balance for payout', async () => {
    const owner = await createBusinessOwner('Poor Shop');
    const banks = await api('GET', '/wallet/banks', { token: owner.token });
    const res = await api('POST', '/wallet/payout', {
      token: owner.token,
      body: {
        amount_kobo: 1000,
        bank_code: banks.body.banks[0].code,
        account_number: '1234567890',
        account_name: 'John Doe',
      },
    });
    assert.equal(res.status, 400);
  });

  test('wrong OTP for payout confirm fails', async () => {
    const owner = await createBusinessOwner('Wrong Shop');
    await api('POST', '/wallet/fund', {
      token: owner.token,
      body: { amount_kobo: 100000, channel: 'card', card_number: '5555555555554444' },
    });
    const banks = await api('GET', '/wallet/banks', { token: owner.token });
    const payout = await api('POST', '/wallet/payout', {
      token: owner.token,
      body: {
        amount_kobo: 10000,
        bank_code: banks.body.banks[0].code,
        account_number: '1234567890',
        account_name: 'Jane Doe',
      },
    });
    assert.equal(payout.status, 200);
    const bad = await api('POST', '/wallet/payout/confirm', {
      token: owner.token,
      body: { otp: '000000' },
    });
    assert.equal(bad.status, 400);
  });

  test('webhook credits wallet for virtual account transfer', async () => {
    const owner = await createBusinessOwner('Webhook Shop');
    const va = await api('POST', '/wallet/fund', {
      token: owner.token,
      body: { amount_kobo: 5000, channel: 'virtual_account' },
    });
    assert.equal(va.status, 200);
    const reference = va.body.wallet.virtualAccountReference;
    const secret = process.env.PAYMENT_WEBHOOK_SECRET ?? 'simulated-webhook-secret';
    const payload = {
      event: 'transfer.success',
      data: { reference, amount_kobo: 250000, status: 'successful' },
    };
    const raw = JSON.stringify(payload);
    const sig = crypto.createHmac('sha256', secret).update(raw).digest('hex');
    const hook = await api('POST', '/wallet/webhook', {
      body: payload,
      headers: { 'x-dee-signature': sig },
    });
    // webhook endpoint accepts JSON; our api helper sends JSON body
    assert.equal(hook.status, 200);
    const w = await api('GET', '/wallet', { token: owner.token });
    assert.equal(w.body.wallet.balanceKobo, 250000);
  });
});
