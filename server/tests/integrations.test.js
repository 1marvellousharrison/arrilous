import test from 'node:test';
import assert from 'node:assert/strict';

// config.js reads process.env at import time, so set this before any import.
process.env.NODE_ENV = 'test';

const { services, integrationCapabilities } = await import('../src/services/index.js');
const { IntegrationService, reservedMethod } = await import('../src/services/extension.js');
const { ApiError } = await import('../src/lib/errors.js');
const { config } = await import('../src/config.js');

const NAMES = ['whatsapp', 'payments', 'logistics', 'notifications'];

// The payments boundary is implemented (the simulated wallet gateway); the
// other three remain reserved integration points that must stay inert.
const RESERVED = ['whatsapp', 'logistics', 'notifications'];

test('Phase 14 exposes exactly the four integration boundaries', () => {
  assert.deepEqual(Object.keys(services).sort(), [...NAMES].sort());
  for (const name of NAMES) {
    assert.equal(services[name].name, name);
    assert.ok(services[name].summary.length > 0, `${name} has a summary`);
    assert.ok(services[name].methods.length > 0, `${name} declares methods`);
  }
});

test('the registry describes every boundary in a stable shape', () => {
  const described = integrationCapabilities();
  assert.equal(described.length, 4);
  for (const entry of described) {
    assert.deepEqual(Object.keys(entry).sort(), ['configured', 'methods', 'name', 'summary']);
    assert.equal(typeof entry.configured, 'boolean');
  }
});

test('a configured flag tracks the provider name, never a secret', () => {
  for (const name of NAMES) {
    const slot = config.integrations[name];
    // Only the provider name lives in the config object; credentials are read
    // where they are used so they cannot be logged or serialised by accident.
    assert.deepEqual(Object.keys(slot), ['provider']);
    assert.equal(services[name].configured, Boolean(slot.provider));
  }
});

test('every reserved method is inert and reports not-implemented', async () => {
  for (const name of RESERVED) {
    const service = services[name];
    for (const method of service.methods) {
      await assert.rejects(
        () => service[method](),
        (error) => {
          assert.ok(error instanceof ApiError, `${name}.${method} throws ApiError`);
          assert.equal(error.status, 501);
          assert.equal(error.code, 'not_implemented');
          return true;
        },
        `${name}.${method}() must reject as reserved`
      );
    }
  }
});

test('the payments boundary is implemented, not reserved', async () => {
  const banks = await services.payments.listBanks();
  assert.ok(Array.isArray(banks) && banks.length > 0, 'payments.listBanks() returns banks');
  const reference = await services.payments.createReference('TEST');
  assert.match(reference, /^TEST-[A-Z0-9]+$/);
  const account = await services.payments.resolveAccount({
    bankCode: banks[0].code,
    accountNumber: '0123456789',
  });
  assert.equal(account.accountNumber, '0123456789');
  assert.ok(account.accountName.length > 0);
});

test('a reserved call attempts no external network request', async () => {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = () => {
    calls += 1;
    throw new Error('fetch must not be called from a reserved integration');
  };
  try {
    for (const name of RESERVED) {
      for (const method of services[name].methods) {
        await services[name][method]().catch(() => {});
      }
    }
  } finally {
    globalThis.fetch = original;
  }
  assert.equal(calls, 0, 'nothing reached out to a provider');
});

test('reservedMethod builds the standard 501 envelope', () => {
  const error = reservedMethod('payments', 'createReference');
  assert.equal(error.status, 501);
  assert.equal(error.code, 'not_implemented');
  assert.match(error.message, /payments\.createReference\(\)/);
});

test('a boundary that declares a method it does not define fails fast', () => {
  assert.throws(
    () => new IntegrationService('broken', 'x', ['missing']),
    /declares method "missing" but does not define it/
  );
});
