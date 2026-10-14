import express from 'express';
import crypto from 'node:crypto';
import { config } from '../config.js';
import { queryOne, queryAll, run, transaction } from '../db/index.js';
import {
  hashPassword,
  verifyPassword,
  fakeVerify,
  randomToken,
  sha256,
  randomDigits,
} from '../lib/password.js';
import { signAccessToken } from '../lib/jwt.js';
import { requireAuth } from '../middleware/auth.js';
import { rateLimit } from '../middleware/rateLimit.js';
import {
  unauthorized,
  conflict,
  notFound,
  tooManyRequests,
  badRequest,
  validationFailed,
} from '../lib/errors.js';
import {
  signupSchema,
  loginSchema,
  requestOtpSchema,
  verifyOtpSchema,
  refreshSchema,
  resetPasswordSchema,
  toFieldErrors,
} from '../lib/validators.js';
import { maskEmail, maskPhone } from '../lib/normalise.js';

export const authRouter = express.Router();

function parse(schema, payload) {
  const result = schema.safeParse(payload ?? {});
  if (!result.success) throw validationFailed(toFieldErrors(result.error));
  return result.data;
}

export function publicUser(row) {
  return {
    id: row.id,
    fullName: row.full_name,
    email: row.email,
    phone: row.phone ?? null,
    role: row.role,
    emailVerified: Boolean(row.email_verified_at),
    phoneVerified: Boolean(row.phone_verified_at),
    createdAt: row.created_at,
  };
}

async function findUserByIdentifier(identifier) {
  return identifier.includes('@')
    ? await queryOne('SELECT * FROM users WHERE email = ?', identifier)
    : await queryOne('SELECT * FROM users WHERE phone = ?', identifier);
}

/** Creates an opaque refresh token; only its SHA-256 hash is persisted. */
async function issueSession(user, req) {
  const refreshToken = randomToken(48);
  const expiresAt = new Date(Date.now() + config.jwt.refreshTtlSeconds * 1000).toISOString();

  await run(
    `INSERT INTO refresh_tokens (id, user_id, token_hash, user_agent, ip_address, expires_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
    crypto.randomUUID(),
    user.id,
    sha256(refreshToken),
    req.get('user-agent')?.slice(0, 255) ?? null,
    req.ip ?? null,
    expiresAt
  );

  await run('UPDATE users SET last_login_at = ? WHERE id = ?', new Date().toISOString(), user.id);

  const access = signAccessToken(user);
  return {
    token_type: 'Bearer',
    access_token: access.token,
    expires_in: access.expiresIn,
    expires_at: access.expiresAt,
    refresh_token: refreshToken,
    refresh_expires_at: expiresAt,
    user: publicUser(user),
  };
}

// ─────────────────────────────────────────────────────────────
// POST /api/v1/auth/signup
// ─────────────────────────────────────────────────────────────
authRouter.post(
  '/signup',
  rateLimit({ keyPrefix: 'signup' }),
  async (req, res) => {
    const body = parse(signupSchema, req.body);

    const existingEmail = await queryOne('SELECT id FROM users WHERE email = ?', body.email);
    if (existingEmail) {
      throw conflict('An account with this email already exists.', 'email_taken');
    }
    if (body.phone) {
      const existingPhone = await queryOne('SELECT id FROM users WHERE phone = ?', body.phone);
      if (existingPhone) {
        throw conflict('An account with this phone number already exists.', 'phone_taken');
      }
    }

    const passwordHash = await hashPassword(body.password);
    const now = new Date().toISOString();
    const user = {
      id: crypto.randomUUID(),
      full_name: body.full_name,
      email: body.email,
      phone: body.phone ?? null,
      password_hash: passwordHash,
      role: body.role,
      status: 'active',
      created_at: now,
    };

    await run(
      `INSERT INTO users (id, full_name, email, phone, password_hash, role, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?)`,
      user.id,
      user.full_name,
      user.email,
      user.phone,
      user.password_hash,
      user.role,
      now,
      now
    );

    const session = await issueSession(user, req);
    return res.status(201).json(session);
  }
);

// ─────────────────────────────────────────────────────────────
// POST /api/v1/auth/login  (email or phone + password)
// ─────────────────────────────────────────────────────────────
authRouter.post(
  '/login',
  rateLimit({ keyPrefix: 'login' }),
  async (req, res) => {
    const body = parse(loginSchema, req.body);
    const user = await findUserByIdentifier(body.identifier);

    if (!user) {
      await fakeVerify();
      throw unauthorized('Incorrect email/phone or password.');
    }
    if (user.status !== 'active') {
      throw unauthorized('This account has been suspended.');
    }

    const ok = await verifyPassword(body.password, user.password_hash);
    if (!ok) throw unauthorized('Incorrect email/phone or password.');

    return res.json(await issueSession(user, req));
  }
);

// ─────────────────────────────────────────────────────────────
// POST /api/v1/auth/request-otp
// Dev-only echo of the code until an SMS/email provider is wired in.
// ─────────────────────────────────────────────────────────────
authRouter.post(
  '/request-otp',
  rateLimit({ keyPrefix: 'otp-request', max: 10 }),
  async (req, res) => {
    const body = parse(requestOtpSchema, req.body);
    const channel = body.channel ?? (body.identifier.includes('@') ? 'email' : 'sms');
    const now = new Date();
    const cooldownUntil = new Date(now.getTime() - config.otp.resendCooldownSeconds * 1000);

    const recent = await queryOne(
      `SELECT id FROM otp_challenges
       WHERE identifier = ? AND purpose = ? AND created_at > ?
       ORDER BY created_at DESC LIMIT 1`,
      body.identifier,
      body.purpose,
      cooldownUntil.toISOString()
    );
    if (recent) {
      throw tooManyRequests(
        `Please wait ${config.otp.resendCooldownSeconds} seconds before requesting another code.`
      );
    }

    if (body.purpose === 'signup_verification') {
      const taken = await findUserByIdentifier(body.identifier);
      if (taken) {
        throw conflict('An account with this email/phone already exists.', 'account_exists');
      }
    }
    if (body.purpose === 'password_reset') {
      const existing = await findUserByIdentifier(body.identifier);
      // Always answer 200 so the endpoint cannot be used to discover accounts.
      if (!existing) return res.json({ status: 'success' });
    }

    const code = randomDigits(config.otp.length);
    const expiresAt = new Date(now.getTime() + config.otp.ttlSeconds * 1000).toISOString();
    const challengeId = crypto.randomUUID();

    await run(
      `INSERT INTO otp_challenges (id, identifier, channel, purpose, code_hash, max_attempts, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      challengeId,
      body.identifier,
      channel,
      body.purpose,
      sha256(`${body.identifier}:${code}`),
      config.otp.maxAttempts,
      expiresAt
    );

    return res.status(201).json({
      status: 'success',
      challenge_id: challengeId,
      channel,
      purpose: body.purpose,
      destination: channel === 'email' ? maskEmail(body.identifier) : maskPhone(body.identifier),
      expires_at: expiresAt,
      ...(config.otp.exposeInResponse ? { dev_code: code } : {}),
    });
  }
);

// ─────────────────────────────────────────────────────────────
// POST /api/v1/auth/verify-otp
// ─────────────────────────────────────────────────────────────
authRouter.post(
  '/verify-otp',
  rateLimit({ keyPrefix: 'otp-verify', max: 15 }),
  async (req, res) => {
    const body = parse(verifyOtpSchema, req.body);
    const challenge = await queryOne('SELECT * FROM otp_challenges WHERE id = ?', body.challenge_id);
    if (!challenge) throw notFound('This verification request is no longer valid.');

    if (challenge.consumed_at) throw badRequest('This code has already been used.');
    if (challenge.attempts >= challenge.max_attempts) {
      throw tooManyRequests('Too many incorrect codes. Request a new one.');
    }
    if (new Date(challenge.expires_at).getTime() <= Date.now()) {
      throw badRequest('This code has expired. Request a new one.');
    }

    const submitted = sha256(`${challenge.identifier}:${body.code}`);
    if (submitted !== challenge.code_hash) {
      await run('UPDATE otp_challenges SET attempts = attempts + 1 WHERE id = ?', challenge.id);
      throw badRequest('Incorrect verification code.');
    }

    if (challenge.purpose === 'password_reset') return res.json({ status: 'success' });

    let user = challenge.user_id
      ? await queryOne('SELECT * FROM users WHERE id = ?', challenge.user_id)
      : await findUserByIdentifier(challenge.identifier);

    if (!user) {
      // Login-by-OTP against an unknown account must not create one silently.
      throw unauthorized('No account found for this email/phone.');
    }
    if (user.status !== 'active') throw unauthorized('This account has been suspended.');

    const now = new Date().toISOString();
    await run(
      `UPDATE otp_challenges SET consumed_at = ? WHERE id = ?`,
      now,
      challenge.id
    );
    if (challenge.channel === 'email' && !user.email_verified_at) {
      await run('UPDATE users SET email_verified_at = ?, updated_at = ? WHERE id = ?', now, now, user.id);
    }
    if (challenge.channel === 'sms' && !user.phone_verified_at) {
      await run('UPDATE users SET phone_verified_at = ?, updated_at = ? WHERE id = ?', now, now, user.id);
    }

    user = await queryOne('SELECT * FROM users WHERE id = ?', user.id);
    return res.json(await issueSession(user, req));
  }
);

// ─────────────────────────────────────────────────────────────
// POST /api/v1/auth/refresh  (rotates the refresh token)
// ─────────────────────────────────────────────────────────────
authRouter.post('/refresh', rateLimit({ keyPrefix: 'refresh' }), async (req, res) => {
  const body = parse(refreshSchema, req.body);
  const hash = sha256(body.refresh_token);

  const row = await queryOne('SELECT * FROM refresh_tokens WHERE token_hash = ?', hash);
  if (!row) throw unauthorized('Invalid refresh token.');
  if (row.revoked_at) {
    // A revoked token being replayed is a signal worth failing loudly on.
    await transaction(async () => {
      await run(
        `UPDATE refresh_tokens SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL`,
        new Date().toISOString(),
        row.user_id
      );
    });
    throw unauthorized('This session has been revoked. Please sign in again.');
  }
  if (new Date(row.expires_at).getTime() <= Date.now()) {
    throw unauthorized('Your session has expired. Please sign in again.');
  }

  const user = await queryOne('SELECT * FROM users WHERE id = ?', row.user_id);
  if (!user) throw unauthorized('Account no longer exists.');
  if (user.status !== 'active') throw unauthorized('This account has been suspended.');

  const rotated = await issueSession(user, req);
  await run('UPDATE refresh_tokens SET revoked_at = ? WHERE id = ?', new Date().toISOString(), row.id);
  return res.json(rotated);
});

// ─────────────────────────────────────────────────────────────
// POST /api/v1/auth/logout
// ─────────────────────────────────────────────────────────────
authRouter.post('/logout', async (req, res) => {
  const parsed = refreshSchema.safeParse(req.body ?? {});
  if (parsed.success) {
    await run(
      'UPDATE refresh_tokens SET revoked_at = ? WHERE token_hash = ? AND revoked_at IS NULL',
      new Date().toISOString(),
      sha256(parsed.data.refresh_token)
    );
  }
  return res.json({ status: 'success' });
});

// ─────────────────────────────────────────────────────────────
// POST /api/v1/auth/logout-all
// ─────────────────────────────────────────────────────────────
authRouter.post('/logout-all', requireAuth, async (req, res) => {
  await run(
    'UPDATE refresh_tokens SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL',
    new Date().toISOString(),
    req.auth.userId
  );
  return res.json({ status: 'success' });
});

// ─────────────────────────────────────────────────────────────
// GET /api/v1/auth/me  — the session every later phase builds on
// ─────────────────────────────────────────────────────────────
authRouter.get('/me', requireAuth, async (req, res) => {
  const user = await queryOne('SELECT * FROM users WHERE id = ?', req.auth.userId);
  if (!user) throw notFound('Account not found.');

  const sessions = await queryAll(
    `SELECT id, user_agent, ip_address, expires_at, created_at
     FROM refresh_tokens
     WHERE user_id = ? AND revoked_at IS NULL AND expires_at > ?
     ORDER BY created_at DESC`,
    req.auth.userId,
    new Date().toISOString()
  );

  return res.json({ user: publicUser(user), active_sessions: sessions.length, sessions });
});

// ─────────────────────────────────────────────────────────────
// POST /api/v1/auth/request-password-reset
// ─────────────────────────────────────────────────────────────
authRouter.post(
  '/request-password-reset',
  rateLimit({ keyPrefix: 'pwd-reset', max: 10 }),
  async (req, res) => {
    const body = parse(requestOtpSchema.pick({ identifier: true, channel: true }), req.body);
    req.otpPurpose = 'password_reset';
    const channel = body.channel ?? (body.identifier.includes('@') ? 'email' : 'sms');
    const user = await findUserByIdentifier(body.identifier);

    if (!user) return res.json({ status: 'success' });

    const code = randomDigits(config.otp.length);
    const expiresAt = new Date(Date.now() + config.otp.ttlSeconds * 1000).toISOString();
    const challengeId = crypto.randomUUID();

    await run(
      `INSERT INTO otp_challenges (id, identifier, channel, purpose, code_hash, max_attempts, user_id, expires_at)
       VALUES (?, ?, ?, 'password_reset', ?, ?, ?, ?)`,
      challengeId,
      body.identifier,
      channel,
      sha256(`${body.identifier}:${code}`),
      config.otp.maxAttempts,
      user.id,
      expiresAt
    );

    return res.status(201).json({
      status: 'success',
      challenge_id: challengeId,
      channel,
      destination: channel === 'email' ? maskEmail(body.identifier) : maskPhone(body.identifier),
      expires_at: expiresAt,
      ...(config.otp.exposeInResponse ? { dev_code: code } : {}),
    });
  }
);

// ─────────────────────────────────────────────────────────────
// POST /api/v1/auth/reset-password
// ─────────────────────────────────────────────────────────────
authRouter.post(
  '/reset-password',
  rateLimit({ keyPrefix: 'pwd-set', max: 10 }),
  async (req, res) => {
    const body = parse(resetPasswordSchema, req.body);
    const challenge = await queryOne('SELECT * FROM otp_challenges WHERE id = ?', body.challenge_id);
    if (!challenge || challenge.purpose !== 'password_reset') {
      throw notFound('This reset request is no longer valid.');
    }
    if (challenge.consumed_at) throw badRequest('This code has already been used.');
    if (challenge.attempts >= challenge.max_attempts) {
      throw tooManyRequests('Too many incorrect codes. Request a new one.');
    }
    if (new Date(challenge.expires_at).getTime() <= Date.now()) {
      throw badRequest('This code has expired. Request a new one.');
    }

    if (sha256(`${challenge.identifier}:${body.code}`) !== challenge.code_hash) {
      await run('UPDATE otp_challenges SET attempts = attempts + 1 WHERE id = ?', challenge.id);
      throw badRequest('Incorrect verification code.');
    }

    const passwordHash = await hashPassword(body.new_password);
    const now = new Date().toISOString();

    await transaction(async () => {
      await run('UPDATE otp_challenges SET consumed_at = ? WHERE id = ?', now, challenge.id);
      await run('UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?', passwordHash, now, challenge.user_id);
      // A password change invalidates every existing session.
      await run(
        'UPDATE refresh_tokens SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL',
        now,
        challenge.user_id
      );
    });

    return res.json({ status: 'success' });
  }
);
