import crypto from 'node:crypto';
import { config } from '../config.js';

const HEADER = { alg: 'HS256', typ: 'JWT' };

function base64url(input) {
  return Buffer.from(input).toString('base64url');
}

function sign(data, secret) {
  return crypto.createHmac('sha256', secret).update(data).digest('base64url');
}

/**
 * Issues an HS256 access token. The algorithm is hard-coded and never read
 * from the token itself, so an attacker cannot downgrade to "alg": "none".
 */
export function signAccessToken(user, { ttlSeconds } = {}) {
  const now = Math.floor(Date.now() / 1000);
  const ttl = ttlSeconds ?? config.jwt.accessTtlSeconds;
  const header = base64url(JSON.stringify(HEADER));
  const payload = base64url(
    JSON.stringify({
      sub: user.id,
      role: user.role,
      email: user.email,
      iss: config.jwt.issuer,
      aud: config.jwt.audience,
      iat: now,
      exp: now + ttl,
    })
  );
  const signature = sign(`${header}.${payload}`, config.jwt.secret);
  return {
    token: `${header}.${payload}.${signature}`,
    expiresAt: new Date((now + ttl) * 1000).toISOString(),
    expiresIn: ttl,
  };
}

// The audience that marks a token as "this owner passed the business-edit OTP
// gate". Distinct from the session audience so a session token can never be
// replayed as an edit token, or the other way round.
export const BUSINESS_EDIT_AUDIENCE = `${config.jwt.audience}:business-edit`;

/**
 * Mints the short-lived token that authorises one editing session of a business
 * profile. It carries the owner's id; the route re-checks that this owner really
 * owns the business being edited.
 */
export function signBusinessEditToken(userId, { ttlSeconds } = {}) {
  const now = Math.floor(Date.now() / 1000);
  const ttl = ttlSeconds ?? config.businessEdit.tokenTtlSeconds;
  const header = base64url(JSON.stringify(HEADER));
  const payload = base64url(
    JSON.stringify({
      sub: userId,
      typ: 'business_edit',
      iss: config.jwt.issuer,
      aud: BUSINESS_EDIT_AUDIENCE,
      iat: now,
      exp: now + ttl,
    })
  );
  const signature = sign(`${header}.${payload}`, config.jwt.secret);
  return {
    token: `${header}.${payload}.${signature}`,
    expiresAt: new Date((now + ttl) * 1000).toISOString(),
    expiresIn: ttl,
  };
}

/** Verifies an edit token minted by signBusinessEditToken; null when invalid. */
export function verifyBusinessEditToken(token) {
  if (typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;

  const [header, payload, signature] = parts;

  let decodedHeader;
  try {
    decodedHeader = JSON.parse(Buffer.from(header, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
  if (decodedHeader?.alg !== 'HS256' || decodedHeader?.typ !== 'JWT') return null;

  const expected = sign(`${header}.${payload}`, config.jwt.secret);
  const given = Buffer.from(signature);
  const want = Buffer.from(expected);
  if (given.length !== want.length) return null;
  if (!crypto.timingSafeEqual(given, want)) return null;

  let claims;
  try {
    claims = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
  } catch {
    return null;
  }

  const now = Math.floor(Date.now() / 1000);
  if (typeof claims.exp !== 'number' || claims.exp <= now) return null;
  if (claims.iss !== config.jwt.issuer) return null;
  if (claims.aud !== BUSINESS_EDIT_AUDIENCE) return null;
  if (claims.typ !== 'business_edit') return null;
  if (typeof claims.sub !== 'string' || claims.sub.length === 0) return null;

  return claims;
}

export function verifyAccessToken(token) {
  if (typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;

  const [header, payload, signature] = parts;

  let decodedHeader;
  try {
    decodedHeader = JSON.parse(Buffer.from(header, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
  if (decodedHeader?.alg !== 'HS256' || decodedHeader?.typ !== 'JWT') return null;

  const expected = sign(`${header}.${payload}`, config.jwt.secret);
  const given = Buffer.from(signature);
  const want = Buffer.from(expected);
  if (given.length !== want.length) return null;
  if (!crypto.timingSafeEqual(given, want)) return null;

  let claims;
  try {
    claims = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
  } catch {
    return null;
  }

  const now = Math.floor(Date.now() / 1000);
  if (typeof claims.exp !== 'number' || claims.exp <= now) return null;
  if (claims.iss !== config.jwt.issuer) return null;
  if (claims.aud !== config.jwt.audience) return null;
  if (typeof claims.sub !== 'string' || claims.sub.length === 0) return null;

  return claims;
}
