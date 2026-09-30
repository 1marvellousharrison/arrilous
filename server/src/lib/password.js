import crypto from 'node:crypto';

const SCRYPT_N = 16384;
const SCRYPT_R = 8;
const SCRYPT_P = 1;
const KEY_LENGTH = 64;
const SALT_LENGTH = 16;

function derive(password, salt, keyLength, cost = {}) {
  return new Promise((resolve, reject) => {
    crypto.scrypt(
      password,
      salt,
      keyLength,
      {
        N: cost.N ?? SCRYPT_N,
        r: cost.r ?? SCRYPT_R,
        p: cost.p ?? SCRYPT_P,
        maxmem: 128 * 1024 * 1024,
      },
      (err, derived) => (err ? reject(err) : resolve(derived))
    );
  });
}

/**
 * Hashes a password with scrypt. Format: scrypt$N$r$p$saltHex$hashHex
 * Parameters travel with the hash so they can be raised later without
 * invalidating existing passwords.
 */
export async function hashPassword(password) {
  const salt = crypto.randomBytes(SALT_LENGTH);
  const derived = await derive(password, salt, KEY_LENGTH);
  return [
    'scrypt',
    SCRYPT_N,
    SCRYPT_R,
    SCRYPT_P,
    salt.toString('hex'),
    derived.toString('hex'),
  ].join('$');
}

/**
 * Verifies a password. Returns false (never throws) for malformed hashes so a
 * corrupt row cannot turn into a 500.
 */
export async function verifyPassword(password, storedHash) {
  if (typeof storedHash !== 'string') return false;
  const parts = storedHash.split('$');
  if (parts.length !== 6 || parts[0] !== 'scrypt') return false;

  const [, n, r, p, saltHex, hashHex] = parts;
  const salt = Buffer.from(saltHex, 'hex');
  const expected = Buffer.from(hashHex, 'hex');
  if (salt.length === 0 || expected.length === 0) return false;

  // Cost parameters come from the stored hash, so raising the defaults later
  // still lets old hashes verify.
  const derived = await derive(password, salt, expected.length, {
    N: Number.parseInt(n, 10),
    r: Number.parseInt(r, 10),
    p: Number.parseInt(p, 10),
  });

  return crypto.timingSafeEqual(derived, expected);
}

/** Burns roughly the same CPU as a real hash so "user not found" is not faster. */
export async function fakeVerify() {
  await hashPassword('timing-equalisation');
}

export function randomToken(bytes = 32) {
  return crypto.randomBytes(bytes).toString('base64url');
}

export function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

export function randomDigits(length) {
  let out = '';
  while (out.length < length) {
    out += crypto.randomInt(0, 10).toString();
  }
  return out;
}
