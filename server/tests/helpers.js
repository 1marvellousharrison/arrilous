import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

// Each test run gets its own throwaway SQLite file. Env must be set BEFORE the
// app modules are imported, because config.js reads process.env at load time.
const dbDir = fs.mkdtempSync(path.join(os.tmpdir(), 'dee-auth-test-'));
process.env.NODE_ENV = 'test';
process.env.DATABASE_PATH = path.join(dbDir, 'test.db');
process.env.JWT_SECRET = 'test-secret-not-used-in-production';
process.env.OTP_EXPOSE_IN_RESPONSE = 'true';
process.env.RATE_LIMIT_MAX = '1000';
process.env.DATABASE_URL = '';

const { createApp } = await import('../src/app.js');
const { closeDb, run } = await import('../src/db/index.js');
const { resetRateLimits } = await import('../src/middleware/rateLimit.js');
const { signAccessToken } = await import('../src/lib/jwt.js');

let server;
let baseUrl_;

before(async () => {
  const app = await createApp();
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  baseUrl_ = `http://127.0.0.1:${server.address().port}/api/v1`;
  resetRateLimits();
});

after(async () => {
  await new Promise((resolve) => server.close(resolve));
  closeDb();
  fs.rmSync(dbDir, { recursive: true, force: true });
});

export async function api(method, route, { body, token, headers } = {}) {
  const res = await fetch(`${baseUrl_}${route}`, {
    method,
    headers: {
      ...(body ? { 'content-type': 'application/json' } : {}),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(headers ?? {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { raw: text };
  }
  return { status: res.status, body: json };
}

let counter = 0;
export function baseUrl() {
  return baseUrl_;
}
export function uniqueEmail(label = 'user') {
  counter += 1;
  return `${label}-${Date.now()}-${counter}@example.com`;
}

export function uniquePhone() {
  return `+23480${String(Math.floor(10000000 + Math.random() * 89999999))}`;
}

export async function createUser(overrides = {}) {
  const payload = {
    full_name: 'Test Owner',
    email: uniqueEmail('owner'),
    phone: uniquePhone(),
    password: 'Str0ngPass!23',
    role: 'business',
    ...overrides,
  };
  const res = await api('POST', '/auth/signup', { body: payload });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return { payload, session: res.body };
}

/**
 * Signs up a fresh business owner and creates its business profile, returning
 * the access token plus the business id. Used by every Phase 1-7 suite so each
 * test owns an isolated business.
 */
export async function createBusinessOwner(name = 'Test Store') {
  const { session } = await createUser();
  const res = await api('POST', '/business', {
    token: session.access_token,
    body: {
      business_name: name,
      phone: uniquePhone(),
      business_category: 'Testing',
      business_description: 'Test merchandise for the suite.',
    },
  });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return {
    token: session.access_token,
    userId: session.user.id,
    business: res.body.business,
  };
}

