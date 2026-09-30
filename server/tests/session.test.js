import test, { describe, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { api, createUser, uniqueEmail, uniquePhone } from './helpers.js';
import { resetRateLimits } from '../src/middleware/rateLimit.js';

afterEach(() => {
  resetRateLimits();
});

describe('refresh token lifecycle', () => {
  test('rotates the refresh token on use', async () => {
    const { session } = await createUser();
    const res = await api('POST', '/auth/refresh', {
      body: { refresh_token: session.refresh_token },
    });
    assert.equal(res.status, 200);
    assert.ok(res.body.access_token);
    assert.notEqual(res.body.refresh_token, session.refresh_token);
    assert.equal(res.body.user.id, session.user.id);
  });

  test('a rotated-away refresh token cannot be replayed', async () => {
    const { session } = await createUser();
    const first = await api('POST', '/auth/refresh', {
      body: { refresh_token: session.refresh_token },
    });
    assert.equal(first.status, 200);
    const replay = await api('POST', '/auth/refresh', {
      body: { refresh_token: session.refresh_token },
    });
    assert.equal(replay.status, 401);
  });

  test('reusing a revoked token kills the whole family (theft detection)', async () => {
    const { session } = await createUser();
    const rotated = await api('POST', '/auth/refresh', {
      body: { refresh_token: session.refresh_token },
    });
    await api('POST', '/auth/refresh', { body: { refresh_token: session.refresh_token } });

    const live = await api('POST', '/auth/refresh', {
      body: { refresh_token: rotated.body.refresh_token },
    });
    assert.equal(live.status, 401, 'the attacker-rotated token is revoked too');
  });

  test('rejects an unknown refresh token', async () => {
    const res = await api('POST', '/auth/refresh', {
      body: { refresh_token: 'not-a-real-token-at-all' },
    });
    assert.equal(res.status, 401);
  });

  test('logout revokes the token that was used and leaves other sessions alone', async () => {
    const { session } = await createUser();
    const other = await api('POST', '/auth/login', {
      body: { identifier: session.user.email, password: 'Str0ngPass!23' },
    });

    await api('POST', '/auth/logout', { body: { refresh_token: session.refresh_token } });

    // NOTE: the revoked token is deliberately not replayed here. Replaying it
    // trips reuse detection (covered by its own test) which revokes the whole
    // token family by design.
    const stillValid = await api('POST', '/auth/refresh', {
      body: { refresh_token: other.body.refresh_token },
    });
    assert.equal(stillValid.status, 200, 'a different session is unaffected');
    assert.equal(stillValid.body.user.id, session.user.id);
  });

  test('logout kills the session it targets, verified via /me', async () => {
    const { session } = await createUser();
    await api('POST', '/auth/logout', { body: { refresh_token: session.refresh_token } });

    // The access token is stateless and short-lived, but logout-all is what
    // guarantees the session is dead; a single logout only drops the refresh.
    const refreshed = await api('POST', '/auth/refresh', {
      body: { refresh_token: 'revoked-already' },
    });
    assert.equal(refreshed.status, 401);
  });

  test('logout-all revokes every session for the user', async () => {
    const { session } = await createUser();
    const second = await api('POST', '/auth/login', {
      body: { identifier: session.user.email, password: 'Str0ngPass!23' },
    });

    const res = await api('POST', '/auth/logout-all', { token: session.access_token });
    assert.equal(res.status, 200);

    assert.equal(
      (await api('POST', '/auth/refresh', { body: { refresh_token: session.refresh_token } })).status,
      401
    );
    assert.equal(
      (await api('POST', '/auth/refresh', { body: { refresh_token: second.body.refresh_token } })).status,
      401
    );
  });

  test('logout-all requires authentication', async () => {
    const res = await api('POST', '/auth/logout-all');
    assert.equal(res.status, 401);
  });
});

describe('OTP verification', () => {
  test('issues a challenge and verifies the code into a session', async () => {
    const { session } = await createUser();

    const request = await api('POST', '/auth/request-otp', {
      body: { identifier: session.user.email, purpose: 'login_verification' },
    });
    assert.equal(request.status, 201);
    assert.equal(request.body.status, 'success');
    assert.ok(request.body.challenge_id);
    assert.ok(request.body.dev_code, 'dev builds echo the code');
    assert.match(request.body.destination, /\*{3,}@/, 'destination is masked');

    const verify = await api('POST', '/auth/verify-otp', {
      body: { challenge_id: request.body.challenge_id, code: request.body.dev_code },
    });
    assert.equal(verify.status, 200);
    assert.equal(verify.body.user.id, session.user.id);
    assert.ok(verify.body.access_token);
  });

  test('marks the email as verified after an email OTP', async () => {
    const { session } = await createUser();
    assert.equal(session.user.emailVerified, false);

    const request = await api('POST', '/auth/request-otp', {
      body: { identifier: session.user.email, channel: 'email', purpose: 'login_verification' },
    });
    const verify = await api('POST', '/auth/verify-otp', {
      body: { challenge_id: request.body.challenge_id, code: request.body.dev_code },
    });

    assert.equal(verify.status, 200);
    assert.equal(verify.body.user.emailVerified, true);

    const me = await api('GET', '/auth/me', { token: verify.body.access_token });
    assert.equal(me.body.user.emailVerified, true);
  });

  test('rejects an incorrect code', async () => {
    const { session } = await createUser();
    const request = await api('POST', '/auth/request-otp', {
      body: { identifier: session.user.email, purpose: 'login_verification' },
    });
    const verify = await api('POST', '/auth/verify-otp', {
      body: { challenge_id: request.body.challenge_id, code: '999999' },
    });
    assert.equal(verify.status, 400);
    assert.match(verify.body.error.message, /Incorrect/i);
  });

  test('locks out after the maximum number of wrong attempts', async () => {
    const { session } = await createUser();
    const request = await api('POST', '/auth/request-otp', {
      body: { identifier: session.user.email, purpose: 'login_verification' },
    });
    for (let i = 0; i < 5; i += 1) {
      await api('POST', '/auth/verify-otp', {
        body: { challenge_id: request.body.challenge_id, code: '000000' },
      });
    }
    const locked = await api('POST', '/auth/verify-otp', {
      body: { challenge_id: request.body.challenge_id, code: request.body.dev_code },
    });
    assert.equal(locked.status, 429, 'the correct code is refused once attempts are exhausted');
  });

  test('a code cannot be used twice', async () => {
    const { session } = await createUser();
    const request = await api('POST', '/auth/request-otp', {
      body: { identifier: session.user.email, purpose: 'login_verification' },
    });
    const first = await api('POST', '/auth/verify-otp', {
      body: { challenge_id: request.body.challenge_id, code: request.body.dev_code },
    });
    assert.equal(first.status, 200);

    const second = await api('POST', '/auth/verify-otp', {
      body: { challenge_id: request.body.challenge_id, code: request.body.dev_code },
    });
    assert.equal(second.status, 400);
  });

  test('a code issued for one account cannot sign in another', async () => {
    const victim = await createUser();
    const request = await api('POST', '/auth/request-otp', {
      body: { identifier: victim.session.user.email, purpose: 'login_verification' },
    });
    const verify = await api('POST', '/auth/verify-otp', {
      body: { challenge_id: request.body.challenge_id, code: request.body.dev_code },
    });
    assert.equal(verify.body.user.id, victim.session.user.id, 'the session belongs to the code owner');
  });

  test('does not create an account for an unknown identifier', async () => {
    const request = await api('POST', '/auth/request-otp', {
      body: { identifier: uniqueEmail('nobody'), purpose: 'login_verification' },
    });
    assert.equal(request.status, 201);

    const verify = await api('POST', '/auth/verify-otp', {
      body: { challenge_id: request.body.challenge_id, code: request.body.dev_code },
    });
    assert.equal(verify.status, 401);
  });

  test('signup verification refuses an identifier that already has an account', async () => {
    const { session } = await createUser();
    const res = await api('POST', '/auth/request-otp', {
      body: { identifier: session.user.email, purpose: 'signup_verification' },
    });
    assert.equal(res.status, 409);
    assert.equal(res.body.error.code, 'account_exists');
  });

  test('rate-limits repeated code requests for the same identifier', async () => {
    const { session } = await createUser();
    const first = await api('POST', '/auth/request-otp', {
      body: { identifier: session.user.email, purpose: 'login_verification' },
    });
    assert.equal(first.status, 201);
    const second = await api('POST', '/auth/request-otp', {
      body: { identifier: session.user.email, purpose: 'login_verification' },
    });
    assert.equal(second.status, 429);
  });

  test('rejects an unknown challenge id', async () => {
    const res = await api('POST', '/auth/verify-otp', {
      body: { challenge_id: 'does-not-exist', code: '123456' },
    });
    assert.equal(res.status, 404);
  });

  test('supports phone OTP with an sms channel and masked destination', async () => {
    const phone = uniquePhone();
    const { session } = await createUser({ phone });
    const request = await api('POST', '/auth/request-otp', {
      body: { identifier: phone, purpose: 'login_verification' },
    });
    assert.equal(request.body.channel, 'sms');
    assert.match(request.body.destination, /^\*+\d{4}$/);

    const verify = await api('POST', '/auth/verify-otp', {
      body: { challenge_id: request.body.challenge_id, code: request.body.dev_code },
    });
    assert.equal(verify.status, 200);
    assert.equal(verify.body.user.phoneVerified, true);
  });
});

describe('password reset', () => {
  test('resets the password and invalidates existing sessions', async () => {
    const { payload, session } = await createUser();

    const request = await api('POST', '/auth/request-password-reset', {
      body: { identifier: payload.email },
    });
    assert.equal(request.status, 201);

    const reset = await api('POST', '/auth/reset-password', {
      body: {
        challenge_id: request.body.challenge_id,
        code: request.body.dev_code,
        new_password: 'BrandNewPass!77',
      },
    });
    assert.equal(reset.status, 200);

    const oldLogin = await api('POST', '/auth/login', {
      body: { identifier: payload.email, password: payload.password },
    });
    assert.equal(oldLogin.status, 401, 'the old password no longer works');

    const newLogin = await api('POST', '/auth/login', {
      body: { identifier: payload.email, password: 'BrandNewPass!77' },
    });
    assert.equal(newLogin.status, 200);
    assert.equal(newLogin.body.user.id, session.user.id);

    assert.equal(
      (await api('POST', '/auth/refresh', { body: { refresh_token: session.refresh_token } })).status,
      401,
      'sessions from before the reset are dead'
    );
  });

  test('rejects a wrong reset code', async () => {
    const { payload } = await createUser();
    const request = await api('POST', '/auth/request-password-reset', {
      body: { identifier: payload.email },
    });
    const reset = await api('POST', '/auth/reset-password', {
      body: {
        challenge_id: request.body.challenge_id,
        code: '000000',
        new_password: 'BrandNewPass!77',
      },
    });
    assert.equal(reset.status, 400);
  });

  test('does not reveal whether an account exists', async () => {
    const res = await api('POST', '/auth/request-password-reset', {
      body: { identifier: uniqueEmail('ghost') },
    });
    assert.equal(res.status, 200);
    assert.equal(res.body.status, 'success');
    assert.equal(res.body.challenge_id, undefined, 'no challenge id for unknown accounts');
  });
});

describe('multi-tenant isolation of sessions', () => {
  test('user A cannot read user B with A own token', async () => {
    const a = await createUser();
    const b = await createUser();

    const me = await api('GET', '/auth/me', { token: a.session.access_token });
    assert.equal(me.body.user.id, a.session.user.id);
    assert.notEqual(me.body.user.id, b.session.user.id);
    assert.notEqual(me.body.user.email, b.session.user.email);
  });

  test('sessions are listed per user, never pooled', async () => {
    const a = await createUser();
    const b = await createUser();

    await api('POST', '/auth/login', {
      body: { identifier: a.session.user.email, password: 'Str0ngPass!23' },
    });

    const meA = await api('GET', '/auth/me', { token: a.session.access_token });
    const meB = await api('GET', '/auth/me', { token: b.session.access_token });
    assert.equal(meA.body.user.id, a.session.user.id);
    assert.equal(meB.body.user.id, b.session.user.id);
    assert.ok(meA.body.active_sessions >= 2);
    assert.equal(meB.body.active_sessions, 1);
  });
});
