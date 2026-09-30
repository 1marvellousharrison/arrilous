import { z } from 'zod';
import { normaliseEmail, normalisePhone } from './normalise.js';
import { toKobo } from './money.js';
import {
  ORDER_STATUSES,
  PAYMENT_STATUSES,
  DELIVERY_STATUSES,
  COMPLETION_STATUSES,
} from './statuses.js';

export const ROLES = ['business', 'logistics_partner', 'rider'];

export const emailSchema = z
  .string({ required_error: 'Email is required.' })
  .trim()
  .min(3, 'Email is required.')
  .max(254, 'Email is too long.')
  .email('Enter a valid email address.')
  .transform(normaliseEmail);

export const phoneSchema = z
  .string({ required_error: 'Phone number is required.' })
  .trim()
  .transform((value) => normalisePhone(value))
  .refine((value) => /^\+[1-9]\d{6,14}$/.test(value), 'Enter a valid phone number.');

export const passwordSchema = z
  .string({ required_error: 'Password is required.' })
  .min(8, 'Password must be at least 8 characters.')
  .max(128, 'Password must be 128 characters or fewer.');

export const identifierSchema = z
  .string({ required_error: 'Enter your email or phone number.' })
  .trim()
  .min(3, 'Enter your email or phone number.')
  .transform((value) => (value.includes('@') ? normaliseEmail(value) : normalisePhone(value)))
  .refine(
    (value) => /^\+[1-9]\d{6,14}$/.test(value) || /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value),
    'Enter a valid email address or phone number.'
  );

export const signupSchema = z.object({
  full_name: z
    .string({ required_error: 'Full name is required.' })
    .trim()
    .min(2, 'Full name is required.')
    .max(120, 'Full name is too long.'),
  email: emailSchema,
  phone: phoneSchema.optional(),
  password: passwordSchema,
  role: z.enum(ROLES).default('business'),
});

export const loginSchema = z.object({
  identifier: identifierSchema,
  password: z.string({ required_error: 'Password is required.' }).min(1, 'Password is required.'),
});

export const requestOtpSchema = z.object({
  identifier: identifierSchema,
  channel: z.enum(['email', 'sms']).optional(),
  purpose: z.enum(['signup_verification', 'login_verification', 'password_reset']).default('login_verification'),
});

export const verifyOtpSchema = z.object({
  challenge_id: z.string({ required_error: 'Challenge is required.' }).trim().min(1),
  code: z
    .string({ required_error: 'Enter the verification code.' })
    .trim()
    .regex(/^[0-9]{4,8}$/, 'Enter the verification code.'),
});

export const refreshSchema = z.object({
  refresh_token: z.string({ required_error: 'Refresh token is required.' }).min(10),
});

export const resetPasswordSchema = z.object({
  challenge_id: z.string({ required_error: 'Challenge is required.' }).trim().min(1),
  code: z.string({ required_error: 'Enter the verification code.' }).trim().regex(/^[0-9]{4,8}$/),
  new_password: passwordSchema,
});

/**
 * Converts a ZodError into the API's field-level details array so the mobile
 * client can highlight the exact inputs that failed.
 */
export function toFieldErrors(error) {
  return error.issues.map((issue) => ({
    field: issue.path.join('.') || 'form',
    message: issue.message,
  }));
}

// ─────────────────────────────────────────────────────────────
// Phases 1-7: business, location, products, customers, transactions
// ─────────────────────────────────────────────────────────────

/**
 * A money input, normalised to integer kobo.
 *
 * Accepts "15000", "15,000.00" or 1500000 (kobo) and rejects anything with more
 * precision than a cent can hold, so a typo becomes a field error instead of
 * silently truncated money.
 */
const moneySchema = (label) =>
  z
    .union([z.string(), z.number()])
    .transform((value, ctx) => {
      try {
        return toKobo(value);
      } catch {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: `${label} must be an amount like 15000 or 15000.50.`,
        });
        return z.NEVER;
      }
    });

const nonNegativeKobo = (label) =>
  moneySchema(label).refine(
    (kobo) => kobo >= 0,
    `${label} cannot be negative.`
  );

const optionalText = (max) =>
  z
    .string()
    .trim()
    .max(max, `Must be ${max} characters or fewer.`)
    .optional()
    .nullable()
    .transform((value) => (value ? value : null));

// Phase 1 — business profile
export const businessCreateSchema = z.object({
  business_name: z
    .string({ required_error: 'Business name is required.' })
    .trim()
    .min(2, 'Business name must be at least 2 characters.')
    .max(160, 'Business name is too long.'),
  business_category: optionalText(80),
  business_description: optionalText(1000),
  phone: phoneSchema.optional().nullable(),
  email: emailSchema.optional().nullable(),
});

export const businessUpdateSchema = businessCreateSchema.partial().refine(
  (value) => Object.keys(value).length > 0,
  { message: 'Send at least one field to update.' }
);

// Phase 2 — business location
export const locationSchema = z
  .object({
    address: z
      .string({ required_error: 'Address is required.' })
      .trim()
      .min(3, 'Enter the street address.')
      .max(400, 'Address is too long.'),
    city: optionalText(120),
    state: optionalText(120),
    country: optionalText(120),
    latitude: z.number().min(-90, 'Latitude must be between -90 and 90.').max(90).optional().nullable(),
    longitude: z.number().min(-180, 'Longitude must be between -180 and 180.').max(180).optional().nullable(),
  })
  .refine(
    (value) => (value.latitude == null) === (value.longitude == null),
    { message: 'Send latitude and longitude together.', path: ['latitude'] }
  );

// Phase 3 — products
export const productCreateSchema = z.object({
  name: z
    .string({ required_error: 'Product name is required.' })
    .trim()
    .min(2, 'Product name must be at least 2 characters.')
    .max(160, 'Product name is too long.'),
  description: optionalText(1000),
  category: optionalText(80),
  price_kobo: nonNegativeKobo('Price'),
  sku: optionalText(64),
  stock_quantity: z
    .number({ required_error: 'Stock quantity is required.' })
    .int('Stock quantity must be a whole number.')
    .min(0, 'Stock quantity cannot be negative.')
    .max(1_000_000, 'That is more stock than this app tracks.')
    .optional()
    .default(0),
  image_url: optionalText(600),
});

export const productUpdateSchema = productCreateSchema
  .partial()
  .refine((value) => Object.keys(value).length > 0, {
    message: 'Send at least one field to update.',
  });

export const productListQuerySchema = z.object({
  search: z.string().trim().max(160).optional(),
  category: z.string().trim().max(80).optional(),
  include_archived: z
    .enum(['true', 'false'])
    .optional()
    .transform((value) => value === 'true'),
});

// Phase 4 — customers
export const customerCreateSchema = z.object({
  name: z
    .string({ required_error: 'Customer name is required.' })
    .trim()
    .min(2, 'Customer name must be at least 2 characters.')
    .max(160, 'Customer name is too long.'),
  phone: phoneSchema.optional().nullable(),
  email: emailSchema.optional().nullable(),
  address: optionalText(400),
  notes: optionalText(1000),
});

export const customerUpdateSchema = customerCreateSchema
  .partial()
  .refine((value) => Object.keys(value).length > 0, {
    message: 'Send at least one field to update.',
  });

export const customerListQuerySchema = z.object({
  search: z.string().trim().max(160).optional(),
});

// Phase 5-6 — transactions
const transactionItemSchema = z.object({
  product_id: z.string().trim().min(1, 'Unknown product.').optional().nullable(),
  name: z
    .string()
    .trim()
    .min(1, 'Item name is required.')
    .max(160)
    .optional(),
  quantity: z
    .number({ required_error: 'Quantity is required.' })
    .int('Quantity must be a whole number.')
    .min(1, 'Quantity must be at least 1.'),
  unit_price_kobo: nonNegativeKobo('Unit price').optional(),
});

/**
 * Totals are NOT part of this schema on purpose.
 *
 * Phase 6 forbids trusting money sent by a client, so subtotal/total are never
 * accepted from the payload — they are recomputed from the items on the server.
 * `discount_kobo` and `delivery_fee_kobo` are real inputs (the owner chooses
 * them) but are still capped against the computed subtotal below.
 */
export const transactionCreateSchema = z.object({
  customer_id: z.string().trim().min(1, 'Unknown customer.').optional().nullable(),
  source: z.enum(['manual', 'whatsapp']).default('manual'),
  discount_kobo: nonNegativeKobo('Discount').optional().default(0),
  delivery_fee_kobo: nonNegativeKobo('Delivery fee').optional().default(0),
  delivery_required: z.boolean().optional().default(false),
  delivery_address: optionalText(400),
  notes: optionalText(1000),
  items: z
    .array(transactionItemSchema)
    .min(1, 'Add at least one item to the transaction.')
    .max(200, 'That is too many items for one transaction.'),
});

export const transactionListQuerySchema = z.object({
  search: z.string().trim().max(160).optional(),
  order_status: z.enum(ORDER_STATUSES).optional(),
  payment_status: z.enum(PAYMENT_STATUSES).optional(),
  delivery_status: z.enum(DELIVERY_STATUSES).optional(),
  completion_status: z.enum(COMPLETION_STATUSES).optional(),
  customer_id: z.string().trim().max(64).optional(),
  source: z.enum(['manual', 'whatsapp']).optional(),
  limit: z.coerce.number().int().min(1).max(100).optional().default(50),
  offset: z.coerce.number().int().min(0).max(100_000).optional().default(0),
});

// Phase 7 — status updates
export const statusUpdateSchema = z
  .object({
    orderStatus: z.enum(ORDER_STATUSES).optional(),
    paymentStatus: z.enum(PAYMENT_STATUSES).optional(),
    deliveryStatus: z.enum(DELIVERY_STATUSES).optional(),
    completionStatus: z.enum(COMPLETION_STATUSES).optional(),
  })
  .refine(
    (value) => Object.values(value).some((entry) => entry !== undefined),
    { message: 'Send at least one status to change.' }
  );

export { nonNegativeKobo, moneySchema };
