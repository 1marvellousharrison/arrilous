import { tooManyRequests } from '../lib/errors.js';
import { config } from '../config.js';

/**
 * Fixed-window, in-memory limiter. Keyed by client IP + route so one noisy
 * device cannot lock out everyone behind the same NAT on a different route.
 *
 * NOTE: state is per-process. A multi-instance deployment must swap this for a
 * shared store (Redis) before relying on it for security.
 */
const buckets = new Map();

export function rateLimit({ max, windowMs, keyPrefix = '' } = {}) {
  const limit = max ?? config.rateLimit.maxAuthAttempts;
  const window = windowMs ?? config.rateLimit.windowMs;

  return function rateLimitMiddleware(req, _res, next) {
    const now = Date.now();
    const ip = req.ip ?? req.socket?.remoteAddress ?? 'unknown';
    const key = `${keyPrefix}:${ip}`;
    const bucket = buckets.get(key);

    if (!bucket || now >= bucket.resetAt) {
      buckets.set(key, { count: 1, resetAt: now + window });
      return next();
    }

    bucket.count += 1;
    if (bucket.count > limit) {
      const retryAfter = Math.ceil((bucket.resetAt - now) / 1000);
      return next(
        tooManyRequests('Too many attempts. Please wait a moment and try again.', retryAfter)
      );
    }
    return next();
  };
}

/** Test helper: forget all counters between suites. */
export function resetRateLimits() {
  buckets.clear();
}
