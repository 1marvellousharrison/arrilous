import test, { describe, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import crypto from 'node:crypto';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { api, baseUrl, createUser, uniqueEmail, uniquePhone } from './helpers.js';
import { run } from '../src/db/index.js';
import { resetRateLimits } from '../src/middleware/rateLimit.js';

afterEach(() => {
  resetRateLimits();
});

describe('health', () => {
  test('reports database connectivity', async () => {
    const res = await api('GET', '/health');
    assert.equal(res.status, 200);
    assert.equal(res.body.status, 'ok');
    assert.equal(res.body.database, 'up');
  });
});

describe('signup', () => {
  test('creates an account and returns a usable session', async () => {
    const email = uniqueEmail('signup');
    const phone = uniquePhone();
    const res = await api('POST', '/auth/signup', {
      body: { full_name: 'Ada Lovelace', email, phone, password: 'Str0ngPass!23' },
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.token_type, 'Bearer');
    assert.ok(res.body.access_token, 'access token issued');
    assert.ok(res.body.refresh_token, 'refresh token issued');
    assert.equal(res.body.user.email, email);
    assert.equal(res.body.user.role, 'business');
    assert.equal(res.body.user.fullName, 'Ada Lovelace');
    assert.equal(res.body.user.phone, phone);
  });

  test('signs up successfully without a phone number', async () => {
    const res = await api('POST', '/auth/signup', {
      body: { full_name: 'No Phone', email: uniqueEmail('nophone'), password: 'Str0ngPass!23' },
    });
    assert.equal(res.status, 201);
    assert.equal(res.body.user.phone, null);
  });

  test('never leaks the password hash', async () => {
    const { body } = await api('POST', '/auth/signup', {
      body: { full_name: 'Hash Check', email: uniqueEmail('hash'), phone: uniquePhone(), password: 'Str0ngPass!23' },
    });
    assert.equal(body.user.password_hash, undefined);
    assert.equal(body.user.passwordHash, undefined);
    assert.ok(!JSON.stringify(body).toLowerCase().includes('scrypt$'));
  });

  test('normalises email casing and whitespace', async () => {
    const email = uniqueEmail('MiXeD');
    const res = await api('POST', '/auth/signup', {
      body: {
        full_name: 'Case Test',
        email: `  ${email.toUpperCase()}  `,
        phone: uniquePhone(),
        password: 'Str0ngPass!23',
      },
    });
    assert.equal(res.status, 201);
    assert.equal(res.body.user.email, email.toLowerCase());
  });

  test('rejects a duplicate email with 409', async () => {
    const { payload } = await createUser();
    const res = await api('POST', '/auth/signup', { body: payload });
    assert.equal(res.status, 409);
    assert.equal(res.body.error.code, 'email_taken');
  });

  test('rejects a duplicate phone number with 409', async () => {
    const phone = '+2348099998888';
    await createUser({ phone });
    const res = await api('POST', '/auth/signup', {
      body: {
        full_name: 'Second',
        email: uniqueEmail('dupe-phone'),
        password: 'Str0ngPass!23',
        phone,
      },
    });
    assert.equal(res.status, 409);
    assert.equal(res.body.error.code, 'phone_taken');
  });

  test('supports all three account roles from the spec', async () => {
    for (const role of ['business', 'logistics_partner', 'rider']) {
      const res = await api('POST', '/auth/signup', {
        body: {
          full_name: `Role ${role}`,
          email: uniqueEmail(role),
          phone: uniquePhone(),
          password: 'Str0ngPass!23',
          role,
        },
      });
      assert.equal(res.status, 201, `role ${role} should be accepted`);
      assert.equal(res.body.user.role, role);
    }
  });

  test('rejects an unknown role', async () => {
    const res = await api('POST', '/auth/signup', {
      body: {
        full_name: 'Bad Role',
        email: uniqueEmail('role'),
        phone: uniquePhone(),
        password: 'Str0ngPass!23',
        role: 'admin',
      },
    });
    assert.equal(res.status, 422);
    assert.equal(res.body.error.code, 'validation_failed');
  });

  test('rejects a short password with a field-level message', async () => {
    const res = await api('POST', '/auth/signup', {
      body: { full_name: 'Short Pass', email: uniqueEmail('short'), phone: uniquePhone(), password: 'abc' },
    });
    assert.equal(res.status, 422);
    assert.equal(res.body.error.details[0].field, 'password');
  });

  test('rejects a malformed email', async () => {
    const res = await api('POST', '/auth/signup', {
      body: { full_name: 'Bad Email', email: 'not-an-email', phone: uniquePhone(), password: 'Str0ngPass!23' },
    });
    assert.equal(res.status, 422);
    assert.equal(res.body.error.details[0].field, 'email');
  });

  test('stores a full international phone number unchanged', async () => {
    const res = await createUser({ phone: '+234 803 123 4567' });
    assert.equal(res.session.user.phone, '+2348031234567');
  });

  test('rejects a local phone number with no country code', async () => {
    const res = await api('POST', '/auth/signup', {
      body: {
        full_name: 'Local Number',
        email: uniqueEmail('local'),
        password: 'Str0ngPass!23',
        phone: '08031234567',
      },
    });
    assert.equal(res.status, 422);
    assert.equal(res.body.error.details[0].field, 'phone');
  });

  test('two accounts never share a user id', async () => {
    const a = await createUser();
    const b = await createUser();
    assert.notEqual(a.session.user.id, b.session.user.id);
  });

  test('ignores client-supplied id and privilege fields', async () => {
    const res = await api('POST', '/auth/signup', {
      body: {
        full_name: 'Extra Fields',
        email: uniqueEmail('extra'),
        phone: uniquePhone(),
        password: 'Str0ngPass!23',
        id: 'hijack-me',
        role: 'business',
        status: 'active',
      },
    });
    assert.equal(res.status, 201);
    assert.notEqual(res.body.user.id, 'hijack-me', 'client-supplied id is ignored');
  });
});

describe('login', () => {
  test('signs in with email and password', async () => {
    const { payload, session } = await createUser();
    const res = await api('POST', '/auth/login', {
      body: { identifier: payload.email, password: payload.password },
    });
    assert.equal(res.status, 200);
    assert.equal(res.body.user.id, session.user.id);
  });

  test('signs in with phone number and password', async () => {
    const phone = '+2348011112222';
    const { payload } = await createUser({ phone });
    const res = await api('POST', '/auth/login', {
      body: { identifier: phone, password: payload.password },
    });
    assert.equal(res.status, 200);
  });

  test('rejects a wrong password', async () => {
    const { payload } = await createUser();
    const res = await api('POST', '/auth/login', {
      body: { identifier: payload.email, password: 'WrongPass!99' },
    });
    assert.equal(res.status, 401);
    assert.match(res.body.error.message, /Incorrect/i);
  });

  test('gives an identical error for an unknown account (no enumeration)', async () => {
    const { payload } = await createUser();
    const wrongPassword = await api('POST', '/auth/login', {
      body: { identifier: payload.email, password: 'WrongPass!99' },
    });
    const unknownUser = await api('POST', '/auth/login', {
      body: { identifier: uniqueEmail('ghost'), password: 'WrongPass!99' },
    });
    assert.equal(unknownUser.status, wrongPassword.status);
    assert.equal(unknownUser.body.error.message, wrongPassword.body.error.message);
  });

  test('rejects a suspended account', async () => {
    const { payload } = await createUser();
    await run("UPDATE users SET status = 'suspended' WHERE email = ?", payload.email);
    const res = await api('POST', '/auth/login', {
      body: { identifier: payload.email, password: payload.password },
    });
    assert.equal(res.status, 401);
    await run("UPDATE users SET status = 'active' WHERE email = ?", payload.email);
  });
});

describe('access tokens', () => {
  test('GET /me returns the authenticated user', async () => {
    const { session } = await createUser();
    const res = await api('GET', '/auth/me', { token: session.access_token });
    assert.equal(res.status, 200);
    assert.equal(res.body.user.id, session.user.id);
    assert.ok(res.body.active_sessions >= 1);
  });

  test('rejects a missing token', async () => {
    const res = await api('GET', '/auth/me');
    assert.equal(res.status, 401);
    assert.equal(res.body.error.code, 'unauthorized');
  });

  test('rejects a tampered signature', async () => {
    const { session } = await createUser();
    const [header, payload] = session.access_token.split('.');
    const forged = `${header}.${payload}.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`;
    const res = await api('GET', '/auth/me', { token: forged });
    assert.equal(res.status, 401);
  });

  test('rejects an alg:none downgrade attempt', async () => {
    const { session } = await createUser();
    const parts = session.access_token.split('.');
    const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
    const res = await api('GET', '/auth/me', { token: `${header}.${parts[1]}.` });
    assert.equal(res.status, 401);
  });

  test('rejects a token signed with a different secret', async () => {
    const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
    const payload = Buffer.from(
      JSON.stringify({
        sub: 'someone-else',
        role: 'business',
        iss: 'dee-api',
        aud: 'dee-app',
        iat: Math.floor(Date.now() / 1000),
        exp: Math.floor(Date.now() / 1000) + 900,
      })
    ).toString('base64url');
    const signature = crypto
      .createHmac('sha256', 'attacker-secret')
      .update(`${header}.${payload}`)
      .digest('base64url');

    const res = await api('GET', '/auth/me', { token: `${header}.${payload}.${signature}` });
    assert.equal(res.status, 401);
  });

  test('rejects an expired token', async () => {
    const { signAccessToken } = await import('../src/lib/jwt.js');
    const expired = signAccessToken({ id: 'nobody', role: 'business' }, { ttlSeconds: -10 });
    const res = await api('GET', '/auth/me', { token: expired.token });
    assert.equal(res.status, 401);
  });

  test('rejects a valid token whose user was deleted', async () => {
    const { session } = await createUser();
    await run('DELETE FROM users WHERE id = ?', session.user.id);
    const res = await api('GET', '/auth/me', { token: session.access_token });
    assert.equal(res.status, 401);
  });

  test('rejects a valid token for a suspended user', async () => {
    const { session } = await createUser();
    await run("UPDATE users SET status = 'suspended' WHERE id = ?", session.user.id);
    const res = await api('GET', '/auth/me', { token: session.access_token });
    assert.equal(res.status, 403);
    await run("UPDATE users SET status = 'active' WHERE id = ?", session.user.id);
  });
});

describe('error envelope', () => {
  test('unknown routes return the standard 404 shape', async () => {
    const res = await api('GET', '/does-not-exist');
    assert.equal(res.status, 404);
    assert.equal(res.body.error.code, 'not_found');
  });

  test('malformed JSON returns 400 invalid_json', async () => {
    const res = await fetch(`${baseUrl()}/auth/login`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{ not json',
    });
    assert.equal(res.status, 400);
    assert.equal((await res.json()).error.code, 'invalid_json');
  });

  test('login with a missing body returns 422, not 500', async () => {
    const res = await api('POST', '/auth/login');
    assert.equal(res.status, 422);
  });
});

describe('password hashing internals', () => {
  test('scrypt hashes are salted, so identical passwords differ', async () => {
    const { hashPassword, verifyPassword } = await import('../src/lib/password.js');
    const a = await hashPassword('SamePassword!1');
    const b = await hashPassword('SamePassword!1');

    assert.notEqual(a, b, 'each hash gets a fresh random salt');
    assert.match(a, /^scrypt\$16384\$8\$1\$[0-9a-f]{32}\$[0-9a-f]{128}$/);
    assert.equal(await verifyPassword('SamePassword!1', a), true);
    assert.equal(await verifyPassword('SamePassword!1', b), true);
  });

  test('verify rejects a wrong password and a corrupt hash without throwing', async () => {
    const { hashPassword, verifyPassword } = await import('../src/lib/password.js');
    const hash = await hashPassword('Correct!1');
    assert.equal(await verifyPassword('wrong', hash), false);
    assert.equal(await verifyPassword('Correct!1', 'garbage'), false);
    assert.equal(await verifyPassword('Correct!1', ''), false);
    assert.equal(await verifyPassword('Correct!1', null), false);
  });
});

describe('JWT internals', () => {
  test('verify accepts a freshly signed token', async () => {
    const { signAccessToken, verifyAccessToken } = await import('../src/lib/jwt.js');
    const { token } = signAccessToken({ id: 'user-1', role: 'business', email: 'a@b.co' });
    const claims = verifyAccessToken(token);
    assert.equal(claims.sub, 'user-1');
    assert.equal(claims.role, 'business');
  });

  test('verify rejects malformed input without throwing', async () => {
    const { verifyAccessToken } = await import('../src/lib/jwt.js');
    for (const bad of [null, undefined, '', 'abc', 'a.b', 'a.b.c.d', 42, {}]) {
      assert.equal(verifyAccessToken(bad), null);
    }
  });

  test('verify rejects a payload edited after signing', async () => {
    const { signAccessToken, verifyAccessToken } = await import('../src/lib/jwt.js');
    const { token } = signAccessToken({ id: 'user-1', role: 'business' });
    const [header, payload, signature] = token.split('.');
    const tampered = Buffer.from(
      JSON.stringify({ ...JSON.parse(Buffer.from(payload, 'base64url')), role: 'rider' })
    ).toString('base64url');
    assert.equal(verifyAccessToken(`${header}.${tampered}.${signature}`), null);
  });
});

describe('rate limiting', () => {
  test('blocks a burst from one IP', async () => {
    const { rateLimit } = await import('../src/middleware/rateLimit.js');
    const app = express();
    app.post('/tight', rateLimit({ max: 3, windowMs: 60_000, keyPrefix: 'test-tight' }), (_req, res) =>
      res.json({ ok: true })
    );

    const server = app.listen(0, '127.0.0.1');
    await new Promise((resolve) => server.once('listening', resolve));
    const url = `http://127.0.0.1:${server.address().port}/tight`;

    const statuses = [];
    for (let i = 0; i < 5; i += 1) {
      statuses.push((await fetch(url, { method: 'POST' })).status);
    }
    await new Promise((resolve) => server.close(resolve));

    assert.deepEqual(statuses.slice(0, 3), [200, 200, 200]);
    assert.deepEqual(statuses.slice(3), [429, 429]);
  });

  test('repeated wrong-password logins are eventually blocked', async () => {
    // A dedicated app with a tight limit, so the assertion does not depend on
    // the (deliberately high) RATE_LIMIT_MAX used by the rest of the suite.
    const { rateLimit } = await import('../src/middleware/rateLimit.js');
    const app = express();
    app.post(
      '/login',
      rateLimit({ max: 4, windowMs: 60_000, keyPrefix: 'test-brute' }),
      (_req, res) => res.status(401).json({ error: { code: 'unauthorized' } })
    );

    const server = app.listen(0, '127.0.0.1');
    await new Promise((resolve) => server.once('listening', resolve));
    const url = `http://127.0.0.1:${server.address().port}/login`;

    const statuses = [];
    for (let i = 0; i < 8; i += 1) {
      statuses.push(
        (await fetch(url, {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ identifier: 'victim@example.com', password: 'guess' }),
        })).status
      );
    }
    await new Promise((resolve) => server.close(resolve));

    assert.equal(statuses.filter((s) => s === 401).length, 4, 'wrong passwords are all rejected');
    assert.equal(statuses.filter((s) => s === 429).length, 4, 'the burst is then blocked');
  });
});

describe('production hardening invariants', () => {
  const loadConfig = (extraEnv) =>
    new Promise((resolve) => {
      const child = spawnSync(
        process.execPath,
        ['--input-type=module', '-e', "await import('./src/config.js');"],
        {
          cwd: path.join(import.meta.dirname, '..'),
          encoding: 'utf8',
          env: {
            PATH: process.env.PATH,
            NODE_ENV: 'production',
            JWT_SECRET: 'a-real-production-secret',
            CORS_ORIGINS: '',
            ...extraEnv,
          },
        }
      );
      resolve({
        status: child.status,
        stderr: child.stderr ?? '',
        stdout: child.stdout ?? '',
      });
    });

  test('the dev OTP echo is disabled whenever NODE_ENV is production', async () => {
    const { config } = await import('../src/config.js');
    assert.equal(config.otp.exposeInResponse, !config.isProd && config.otp.exposeInResponse);
  });

  test('production refuses to start without an explicit CORS allowlist', async () => {
    const result = await loadConfig();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /CORS_ORIGINS/);
  });

  test('production refuses a wildcard CORS origin', async () => {
    const result = await loadConfig({ CORS_ORIGINS: '*' });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /CORS_ORIGINS/);
  });

  test('production starts with an explicit CORS allowlist', async () => {
    const result = await loadConfig({ CORS_ORIGINS: 'https://app.example.com' });
    assert.equal(result.status, 0, result.stderr);
  });

  test('development still defaults to a permissive CORS origin', async () => {
    const child = spawnSync(
      process.execPath,
      [
        '--input-type=module',
        '-e',
        "console.log((await import('./src/config.js')).config.cors.origins.join(','));",
      ],
      {
        cwd: path.join(import.meta.dirname, '..'),
        encoding: 'utf8',
        env: {
          PATH: process.env.PATH,
          NODE_ENV: 'development',
          JWT_SECRET: 'dev-secret',
          CORS_ORIGINS: '',
        },
      }
    );
    assert.equal(child.status, 0, child.stderr);
    assert.equal(child.stdout.trim(), '*');
  });
});
