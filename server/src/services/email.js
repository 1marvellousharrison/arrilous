import { config } from '../config.js';

/**
 * Delivery for the owner-confirmation code that guards business-detail edits.
 *
 * Email is the channel: it is the cheapest option in Nigeria by a wide margin
 * and it is the identifier every owner already has. Delivery runs through
 * Resend when `RESEND_API_KEY` is set. Without a key, non-prod builds simply log
 * a breadcrumb (the route already echoes `dev_code`), and prod refuses rather
 * than telling the owner a mail is on its way when nothing was sent.
 *
 * Kept channel-agnostic at the call site so a WhatsApp/SMS fallback can be added
 * later without touching the route. See docs/business-details-edit-otp.md.
 */

function codeMessage({ code, ttlSeconds }) {
  const minutes = Math.max(1, Math.round(ttlSeconds / 60));
  return (
    'Your Biziness confirmation code is ' +
    `${code}.\n\n` +
    'Enter it to confirm a change to your business details. ' +
    `It expires in ${minutes} minute${minutes === 1 ? '' : 's'}.\n\n` +
    'If you did not ask to change your business details, ignore this message ' +
    'and consider changing your password.'
  );
}

async function sendViaResend({ to, subject, text }) {
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      authorization: `Bearer ${config.email.apiKey}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({ from: config.email.from, to, subject, text }),
  });
  if (!response.ok) {
    const detail = await response.text().catch(() => '');
    throw new Error(
      `Email provider refused the message (HTTP ${response.status}). ${detail}`.trim()
    );
  }
}

export const emailService = {
  /** True when a provider key is present, so a code can really be delivered. */
  get configured() {
    return Boolean(config.email.apiKey);
  },

  /**
   * Sends the business-edit code. Throws when production has no provider, so the
   * caller can surface an honest failure instead of a silent dead end.
   */
  async sendBusinessEditCode({ to, code, ttlSeconds }) {
    if (!this.configured) {
      if (!config.isProd) {
        console.log(`[email:dev] business-edit code for ${to} is ${code}`);
        return { delivered: false, dev: true };
      }
      throw new Error('No email provider is configured.');
    }
    await sendViaResend({
      to,
      subject: 'Your Biziness business-details code',
      text: codeMessage({ code, ttlSeconds }),
    });
    return { delivered: true, dev: false };
  },
};
