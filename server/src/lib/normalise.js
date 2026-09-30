/**
 * Normalises identifiers so "John@Example.com " and "john@example.com"
 * can never become two accounts.
 */
export function normaliseEmail(email) {
  return String(email).trim().toLowerCase();
}

/**
 * Phones are stored in E.164 form: '+', country code, then the national
 * number — no spaces or punctuation.
 *
 * A bare local number such as "08031234567" is NOT guessable (the country code
 * is unknown), so it is left invalid and rejected by the schema. The mobile
 * client is expected to submit the full international number.
 */
export function normalisePhone(phone) {
  const trimmed = String(phone).trim();
  const digits = trimmed.replace(/\D/g, '');
  if (digits.length === 0) return '';
  const withoutIdd = digits.startsWith('00') ? digits.slice(2) : digits;
  return `+${withoutIdd}`;
}

export function maskEmail(email) {
  const [local, domain] = String(email).split('@');
  if (!domain) return '***';
  const head = local.slice(0, 1);
  return `${head}${'*'.repeat(Math.max(local.length - 1, 1))}@${domain}`;
}

export function maskPhone(phone) {
  const value = String(phone);
  if (value.length < 5) return '***';
  return `${'*'.repeat(value.length - 4)}${value.slice(-4)}`;
}
