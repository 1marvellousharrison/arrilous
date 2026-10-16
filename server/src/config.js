import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
export const ROOT = path.resolve(here, '..');

/**
 * Minimal .env loader (no dependency). Values already present in
 * process.env always win, so real environment variables are never overwritten.
 */
function loadDotEnv() {
  const envPath = path.join(ROOT, '.env');
  if (!fs.existsSync(envPath)) return;
  const raw = fs.readFileSync(envPath, 'utf8');
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (!(key in process.env)) process.env[key] = value;
  }
}

loadDotEnv();

const NODE_ENV = process.env.NODE_ENV ?? 'development';
const isProd = NODE_ENV === 'production';

function requiredInProd(name, fallback) {
  const value = process.env[name];
  if (value && value.trim()) return value.trim();
  if (isProd) {
    throw new Error(
      `Missing required environment variable ${name}. Refusing to start in production.`
    );
  }
  return fallback;
}

function corsOrigins() {
  const raw = process.env.CORS_ORIGINS ?? '';
  const origins = raw
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean);

  if (origins.includes('*')) {
    if (isProd) {
      throw new Error(
        'CORS_ORIGINS must list explicit origins in production. '
          + 'Refusing to start with a wildcard origin.'
      );
    }
    return origins;
  }

  if (origins.length === 0) {
    if (isProd) {
      throw new Error(
        'Missing required environment variable CORS_ORIGINS. '
          + 'Refusing to start in production without an origin allowlist.'
      );
    }
    return ['*'];
  }

  return origins;
}

if (isProd && !process.env.DATABASE_URL) {
  throw new Error(
    'Missing required environment variable DATABASE_URL. Refusing to start in '
      + 'production without a Postgres connection.'
  );
}

export const config = {
  env: NODE_ENV,
  isProd,
  host: process.env.HOST ?? '0.0.0.0',
  port: Number.parseInt(process.env.PORT ?? '4000', 10),

  // Postgres connection string (Supabase or any Postgres). When absent, the
  // server falls back to an in-process PGlite database — convenient for local
  // development and the test suite, and never used in production.
  databaseUrl: process.env.DATABASE_URL ?? null,
  // Optional on-disk directory for the PGlite fallback. When unset the fallback
  // is in-memory (fresh every boot), which is what the tests rely on.
  pgliteDataDir: process.env.PGLITE_DATA_DIR ?? null,

  jwt: {
    secret: requiredInProd('JWT_SECRET', 'dev-only-insecure-secret-change-me'),
    issuer: process.env.JWT_ISSUER ?? 'dee-api',
    audience: process.env.JWT_AUDIENCE ?? 'dee-app',
    accessTtlSeconds: Number.parseInt(process.env.JWT_ACCESS_TTL ?? '900', 10),
    refreshTtlSeconds: Number.parseInt(
      process.env.JWT_REFRESH_TTL ?? `${60 * 60 * 24 * 30}`,
      10
    ),
  },

  otp: {
    length: 6,
    ttlSeconds: Number.parseInt(process.env.OTP_TTL ?? '600', 10),
    maxAttempts: 5,
    resendCooldownSeconds: 45,
    // Dev only: returns the OTP in the API response because no SMS/SMS
    // provider is integrated yet (explicitly out of scope for this phase).
    exposeInResponse: !isProd && process.env.OTP_EXPOSE_IN_RESPONSE !== 'false',
  },

  // The owner-confirmation gate before an existing business profile may be
  // edited. The code rides the same TTL/cooldown shape as the auth OTP; the
  // token it mints covers one editing session. See
  // docs/business-details-edit-otp.md.
  businessEdit: {
    ttlSeconds: Number.parseInt(process.env.BUSINESS_EDIT_OTP_TTL ?? '600', 10),
    tokenTtlSeconds: Number.parseInt(
      process.env.BUSINESS_EDIT_TOKEN_TTL ?? '900',
      10
    ),
    resendCooldownSeconds: 45,
  },

  // Email is the cheapest owner-confirmation channel and the one every owner
  // already has. Delivery turns on when a provider key is present; without one,
  // non-prod echoes the code and prod refuses to pretend the mail was sent.
  email: {
    apiKey: process.env.RESEND_API_KEY ?? null,
    from: process.env.OTP_EMAIL_FROM ?? 'Biziness <onboarding@resend.dev>',
  },

  rateLimit: {
    windowMs: Number.parseInt(process.env.RATE_LIMIT_WINDOW_MS ?? '900000', 10),
    maxAuthAttempts: Number.parseInt(process.env.RATE_LIMIT_MAX ?? '20', 10),
  },

  cors: {
    origins: corsOrigins(),
  },

  /**
   * Phase 14 — extension points only. A provider name being present flips the
   * matching service to "configured", but nothing calls a provider yet; the
   * credential itself is read from the environment at the point of use and is
   * deliberately never copied into this object (or logged).
   */
  integrations: {
    whatsapp: { provider: process.env.WHATSAPP_PROVIDER ?? null },
    payments: { provider: process.env.PAYMENT_PROVIDER ?? 'simulated' },
    logistics: { provider: process.env.LOGISTICS_PROVIDER ?? null },
    notifications: { provider: process.env.NOTIFICATION_PROVIDER ?? null },
  },
};
