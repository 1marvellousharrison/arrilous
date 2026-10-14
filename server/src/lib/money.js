/**
 * Money is handled as an integer count of kobo. 1 naira = 100 kobo.
 *
 * The alternative — REAL columns in naira — accumulates binary floating point
 * drift, and Phase 6 requires totals to be derived (sum of line items) rather
 * than accepted. Exact integers make "the sum of the items equals the stored
 * subtotal" a decidable check instead of a rounding argument.
 *
 * Every column and every JSON money field in this API carries the `_kobo`
 * suffix so the unit is never ambiguous.
 */
export const KOBO_PER_NAIRA = 100;

const AMOUNT_PATTERN = /^-?\d+(\.\d{1,2})?$/;

/**
 * Converts user input to kobo without ever going through a float.
 *
 * Accepts an integer (already kobo), or a decimal string in major units such as
 * "15000", "15,000.00" or "₦15000.5". A float literal is accepted last and
 * rounded, because JavaScript callers cannot express 15000.50 exactly.
 */
export function toKobo(value) {
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) {
      throw new TypeError('Amount is not a finite number.');
    }
    return Math.round(value * KOBO_PER_NAIRA);
  }

  const cleaned = String(value).replace(/[,\s ]/g, '');
  if (!AMOUNT_PATTERN.test(cleaned)) {
    throw new TypeError('Amount must look like 15000 or 15000.50.');
  }

  const negative = cleaned.startsWith('-');
  const [whole, fraction = ''] = cleaned.replace('-', '').split('.');
  const padded = `${fraction}00`.slice(0, 2);
  const kobo = Number(whole) * KOBO_PER_NAIRA + Number(padded);
  return negative ? -kobo : kobo;
}

/** Renders kobo as a human amount, e.g. 1500000 -> "₦15,000.00". */
export function formatKobo(kobo) {
  const value = Number(kobo ?? 0);
  const negative = value < 0;
  const abs = Math.abs(value);
  const major = Math.floor(abs / KOBO_PER_NAIRA);
  const minor = abs % KOBO_PER_NAIRA;
  const grouped = String(major).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return `${negative ? '-' : ''}₦${grouped}.${String(minor).padStart(2, '0')}`;
}

/**
 * Parses the value of a field that is already denominated in kobo — that is,
 * any JSON field carrying the `_kobo` suffix.
 *
 * The two input shapes mean different things, and conflating them is a 100x bug:
 *
 *   - A JSON **number** is already kobo and is taken as-is. The field name says
 *     so, so `price_kobo: 1500000` is ₦15,000.00. A fractional number is
 *     rejected: it means the caller sent naira to a kobo field.
 *   - A **string** is what a human typed, so it is read as major units and
 *     `price_kobo: "15000.50"` is ₦15,000.50.
 *
 * Both spellings of the same amount therefore agree, and the loser of that
 * disagreement gets an error instead of a silently wrong total.
 */
export function toKoboField(value) {
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) {
      throw new TypeError('Amount is not a finite number.');
    }
    if (!Number.isInteger(value)) {
      throw new TypeError(
        'Amount is already in kobo, so it cannot have decimals. Use a string such as "15000.50" to send naira.'
      );
    }
    return value;
  }

  return toKobo(value);
}
