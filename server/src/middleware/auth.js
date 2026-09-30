import { verifyAccessToken } from '../lib/jwt.js';
import { queryOne } from '../db/index.js';
import { unauthorized, forbidden } from '../lib/errors.js';

function readBearer(req) {
  const header = req.get('authorization') ?? '';
  const [scheme, value] = header.split(' ');
  if (!value || scheme.toLowerCase() !== 'bearer') return null;
  return value.trim();
}

/**
 * Establishes req.auth = { userId, role } from a valid access token.
 * Re-reads the user row so a suspended or deleted account cannot keep using an
 * unexpired token.
 */
export function requireAuth(req, _res, next) {
  const token = readBearer(req);
  if (!token) return next(unauthorized('Missing access token.'));

  const claims = verifyAccessToken(token);
  if (!claims) return next(unauthorized('Your session has expired. Please sign in again.'));

  const user = queryOne(
    'SELECT id, role, status FROM users WHERE id = ?',
    claims.sub
  );
  if (!user) return next(unauthorized('Account no longer exists.'));
  if (user.status !== 'active') return next(forbidden('This account has been suspended.'));

  req.auth = { userId: user.id, role: user.role };
  return next();
}

export function optionalAuth(req, _res, next) {
  const token = readBearer(req);
  if (token) {
    const claims = verifyAccessToken(token);
    if (claims) {
      const user = queryOne('SELECT id, role, status FROM users WHERE id = ?', claims.sub);
      if (user && user.status === 'active') {
        req.auth = { userId: user.id, role: user.role };
      }
    }
  }
  return next();
}
