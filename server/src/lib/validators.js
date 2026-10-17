import { z } from 'zod';
import { normaliseEmail, normalisePhone } from './normalise.js';
import { toKoboField } from './money.js';
import {
  ORDER_STATUSES,
  PAYMENT_STATUSES,
  DELIVERY_STATUSES,
  COMPLETION_STATUSES,
} from './statuses.js';

// Roles a person may choose when they create their own account. `staff` is
// deliberately absent: a staff login is always created for them by a business
// owner (see routes/staff.js), never self-selected at signup.
export const ROLES = ['business', 'logistics_partner', 'rider'];

// The permanent login ID of a staff account, e.g. "ABC47-03": a stable business
// code (3 letters + 2 digits) plus a per-business sequence.
export const BUSINESS_CODE_PATTERN = /^[A-Z]{3}[0-9]{2}$/;
export const STAFF_CODE_PATTERN = /^[A-Z]{3}[0-9]{2}-[0-9]{2}$/;

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

// A sign-in identifier is one of three things: an email, a phone number, or a
// staff code. The staff code is checked before the phone path so its digits and
// letters are not mangled by the E.164 normaliser, and it is upper-cased so a
// staff can type it however they like.
export const identifierSchema = z
  .string({ required_error: 'Enter your email, phone number or staff code.' })
  .trim()
  .min(3, 'Enter your email, phone number or staff code.')
  .transform((value) => {
    if (value.includes('@')) return normaliseEmail(value);
    if (STAFF_CODE_PATTERN.test(value.toUpperCase())) return value.toUpperCase();
    return normalisePhone(value);
  })
  .refine(
    (value) =>
      STAFF_CODE_PATTERN.test(value) ||
      /^\+[1-9]\d{6,14}$/.test(value) ||
      /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value),
    'Enter a valid email address, phone number or staff code.'
  );

export const signupSchema = z.object({
  full_name: z
    .string({ required_error: 'Full name is required.' })
    .trim()
    .min(2, 'Full name is required.')
    .max(120, 'Full name is too long.'),
  email: emailSchema,
  // The phone number is now collected at the business/logistics profile step.
  phone: phoneSchema.optional().nullable(),
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
 * A money input for a `*_kobo` field.
 *
 * `toKoboField` decides the scale: a JSON number is already kobo, a string is
 * a human-typed naira amount like "15000" or "15,000.50". Precision beyond a
 * kobo becomes a field error rather than silently truncated money.
 */
const moneySchema = (label) =>
  z
    .union([z.string(), z.number()])
    .transform((value, ctx) => {
      try {
        return toKoboField(value);
      } catch (error) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: error instanceof TypeError
            ? error.message
            : `${label} must be an amount like 15000 or 15000.50.`,
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

// An optional picture carried as a data-URL image so it travels in the same
// JSON as the record it belongs to. The client downscales before sending, so
// this cap only has to stop an outsized body, and only the shapes the client
// can produce are accepted. Blank clears it, which is why the transform folds
// "" to null. The business logo and the product photos are both this shape.
const imageDataUrlSchema = z
  .string()
  .trim()
  .max(400000, 'Image is too large.')
  .regex(
    /^data:image\/(png|jpe?g|webp);base64,[A-Za-z0-9+/]+={0,2}$/,
    'Image must be a PNG, JPEG or WebP.'
  )
  .optional()
  .nullable()
  .transform((value) => (value ? value : null));

// The owner picks this from their gallery, so it only ever arrives as a
// data URL — a plain link is refused the same way a stray text file is.
const logoUrlSchema = imageDataUrlSchema;

// Phase 1 — business profile
export const businessCreateSchema = z.object({
  business_name: z
    .string({ required_error: 'Business name is required.' })
    .trim()
    .min(2, 'Business name must be at least 2 characters.')
    .max(160, 'Business name is too long.'),
  // Spec 6 — a reachable phone and a clear category and offer are part of a
  // complete business profile, not optional decorations.
  phone: phoneSchema,
  business_category: z
    .string({ required_error: 'Category is required.' })
    .trim()
    .min(2, 'Category must be at least 2 characters.')
    .max(80, 'Category is too long.'),
  business_description: z
    .string({ required_error: 'Tell us what you sell.' })
    .trim()
    .min(3, 'Tell us what you sell.')
    .max(1000, 'Description is too long.'),
  email: emailSchema.optional().nullable(),
  logo_url: logoUrlSchema,
});

export const businessUpdateSchema = businessCreateSchema.partial().refine(
  (value) => Object.keys(value).length > 0,
  { message: 'Send at least one field to update.' }
);

// Phase 2 — business location. `city`, `area` and `state` are what the
// delivery partner reads on the request, so the client requires them in setup;
// they stay optional here so a partially-filled location is still a valid row.
export const locationSchema = z
  .object({
    address: z
      .string({ required_error: 'Address is required.' })
      .trim()
      .min(3, 'Enter the street address.')
      .max(400, 'Address is too long.'),
    city: optionalText(120),
    area: optionalText(120),
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
  image_url: imageDataUrlSchema,
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
  phone: phoneSchema,
  email: emailSchema.optional().nullable(),
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

const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;

/**
 * One end of a Phase 11 date range.
 *
 * `endOfDay` decides what a bare calendar date means: the first instant of that
 * UTC day for a `from`, the last for a `to`. A full timestamp passes through.
 */
const dateBound = (endOfDay) =>
  z
    .union([z.string(), z.date()])
    .refine((value) => !Number.isNaN(toDateBound(value, endOfDay).getTime()), {
      message: 'Enter a valid date.',
    })
    .transform((value) => toDateBound(value, endOfDay));

function toDateBound(value, endOfDay) {
  if (typeof value === 'string' && DATE_ONLY.test(value)) {
    return new Date(`${value}T${endOfDay ? '23:59:59.999' : '00:00:00.000'}Z`);
  }
  return value instanceof Date ? value : new Date(value);
}

export const transactionListQuerySchema = z.object({
  search: z.string().trim().max(160).optional(),
  order_status: z.enum(ORDER_STATUSES).optional(),
  payment_status: z.enum(PAYMENT_STATUSES).optional(),
  delivery_status: z.enum(DELIVERY_STATUSES).optional(),
  completion_status: z.enum(COMPLETION_STATUSES).optional(),
  customer_id: z.string().trim().max(64).optional(),
  source: z.enum(['manual', 'whatsapp']).optional(),
  // Phase 11 — date range over created_at. A full timestamp is used as given and
  // re-serialised to UTC before the query runs: created_at is stored as an
  // ISO-8601 UTC string, so comparing it to a client-supplied local-time string
  // lexicographically would silently shift results by the client's offset.
  //
  // A bare `YYYY-MM-DD` is expanded instead. Leaving `to` at midnight would
  // exclude everything sold during that day, which is the opposite of what an
  // owner filtering "up to today" means.
  from: dateBound(false).optional(),
  to: dateBound(true).optional(),
  limit: z.coerce.number().int().min(1).max(100).optional().default(50),
  offset: z.coerce.number().int().min(0).max(100_000).optional().default(0),
}).refine(
  (value) => !value.from || !value.to || value.from <= value.to,
  { message: 'The start date must not be after the end date.', path: ['from'] }
);

// Phase 7 — status updates. `note` is Phase 8: it is stored on every timeline
// entry the change writes, so an owner can say why money moved.
export const statusUpdateSchema = z
  .object({
    orderStatus: z.enum(ORDER_STATUSES).optional(),
    paymentStatus: z.enum(PAYMENT_STATUSES).optional(),
    deliveryStatus: z.enum(DELIVERY_STATUSES).optional(),
    completionStatus: z.enum(COMPLETION_STATUSES).optional(),
    note: z.string().trim().max(500).optional(),
  })
  // Counts the four axes explicitly rather than testing every value: with a
  // `note` in the shape, `{ note: "just looking" }` would otherwise satisfy a
  // generic "some value is defined" check and silently change nothing. A
  // non-empty note on its own is allowed — that is how a staff (who may not move
  // any status) annotates a sale, and it lands on the timeline as its own entry.
  .refine(
    (value) =>
      value.orderStatus !== undefined ||
      value.paymentStatus !== undefined ||
      value.deliveryStatus !== undefined ||
      value.completionStatus !== undefined ||
      (typeof value.note === 'string' && value.note.trim().length > 0),
    { message: 'Send at least one status to change or a note.' }
  );

// Logistics extension. These schemas keep delivery data separate from the
// existing transaction payload and accept human-entered money consistently.
const capacitySchema = z.enum(['small', 'medium', 'large', 'very_large']);
const vehicleSchema = z.enum(['motorcycle', 'tricycle', 'car', 'van', 'pickup', 'truck', 'other']);
const riderModeSchema = z.enum(['motorcycle', 'car', 'bicycle', 'other']);

export const logisticsOrganizationSchema = z.object({
  name: z.string({ required_error: 'Organization name is required.' }).trim().min(2).max(160),
  phone: phoneSchema,
  // A partner may serve more than one category, so the field carries the
  // selected ones joined into a single string; the cap allows several.
  category: z
    .string({ required_error: 'Category is required.' })
    .trim()
    .min(2, 'Category must be at least 2 characters.')
    .max(400, 'Category is too long.'),
  description: z
    .string({ required_error: 'Tell us what you deliver.' })
    .trim()
    .min(3, 'Tell us what you deliver.')
    .max(1000, 'Description is too long.'),
  email: emailSchema.optional().nullable(),
});

// Spec 6 — a rider arrives with the same reachability details as a business:
// a phone to book them on, and a category plus a description of what they carry.
export const riderProfileSchema = z.object({
  phone: phoneSchema,
  category: z
    .string({ required_error: 'Category is required.' })
    .trim()
    .min(2, 'Category must be at least 2 characters.')
    .max(400, 'Category is too long.'),
  description: z
    .string({ required_error: 'Tell us what you deliver.' })
    .trim()
    .min(3, 'Tell us what you deliver.')
    .max(1000, 'Description is too long.'),
});

// Spec 16/17 v2 — when a provider goes active they decide how long today's
// shift runs. `planned_hours` becomes the closing time (now + N hours) and is
// kept so the Active page can show and edit the plan. A client may instead
// pin `availability_expires_at` directly; both forms create a closing time.
export const availabilitySchema = z
  .object({
    is_available: z.boolean(),
    availability_expires_at: z.string().datetime().optional().nullable(),
    planned_hours: z.number().min(1, 'Plan at least 1 hour.').max(24, 'A shift cannot exceed 24 hours.').optional().nullable(),
  })
  .refine(
    (value) =>
      !value.is_available ||
      value.availability_expires_at == null ||
      new Date(value.availability_expires_at) > new Date(),
    { message: 'Availability closing time must be in the future.', path: ['availability_expires_at'] }
  );

export const serviceAreaSchema = z.object({
  city: z.string({ required_error: 'City is required.' }).trim().min(2).max(120),
  area: optionalText(120),
  state: optionalText(120),
  country: optionalText(120),
  // Spec 19 — coordinates and radius are what make distance ranking and route
  // coverage computable rather than a name match on the city string.
  latitude: z.number().min(-90, 'Latitude must be between -90 and 90.').max(90).optional().nullable(),
  longitude: z.number().min(-180, 'Longitude must be between -180 and 180.').max(180).optional().nullable(),
  radius_km: z.number().min(0).max(20_000).optional().nullable(),
}).refine((value) => (value.latitude == null) === (value.longitude == null), {
  message: 'Send latitude and longitude together.', path: ['latitude'],
});

export const pricingSchema = z.object({
  destination: z.string({ required_error: 'Destination is required.' }).trim().min(2).max(160),
  price_kobo: nonNegativeKobo('Price'),
  vehicle_type: vehicleSchema.optional().nullable(),
});

export const vehicleCreateSchema = z.object({
  vehicle_type: vehicleSchema,
  total_quantity: z.number().int().min(0).max(10000),
  available_quantity: z.number().int().min(0).max(10000),
  capacity_category: capacitySchema,
  starting_price_kobo: nonNegativeKobo('Starting price').optional().default(0),
  active: z.boolean().optional().default(true),
  description: optionalText(500),
}).refine((value) => value.available_quantity <= value.total_quantity, {
  message: 'Available quantity cannot exceed total quantity.', path: ['available_quantity'],
});

export const riderModeCreateSchema = z.object({
  mode: riderModeSchema,
  capacity_category: capacitySchema,
  rate_kobo: nonNegativeKobo('Rate').optional().default(0),
  is_primary: z.boolean().optional().default(false),
  active: z.boolean().optional().default(true),
});

export const deliveryRequestSchema = z.object({
  transaction_id: z.string().trim().min(1),
  organization_id: z.string().trim().min(1).optional(),
  rider_id: z.string().trim().min(1).optional(),
  package_description: optionalText(500),
  package_size: capacitySchema.optional(),
  preferred_mode: z.string().trim().max(40).optional().nullable(),
}).refine((value) => Boolean(value.organization_id) !== Boolean(value.rider_id), {
  message: 'Choose one logistics organization or one rider.', path: ['organization_id'],
});

export const quoteSchema = z.object({
  quoted_price_kobo: nonNegativeKobo('Quote'),
});

export const assignmentSchema = z.object({
  rider_id: z.string().trim().min(1).optional().nullable(),
  vehicle_id: z.string().trim().min(1).optional().nullable(),
});

export const deliveryUpdateSchema = z.object({
  status: z.enum(['accepted', 'picked_up', 'in_transit', 'delivered', 'failed', 'declined']),
  failure_reason: optionalText(500),
}).refine((value) => value.status !== 'failed' || Boolean(value.failure_reason), {
  message: 'Give a reason for a failed delivery.', path: ['failure_reason'],
});

export const confirmationSchema = z.object({
  method: z.enum(['otp', 'signature', 'photo', 'manual']),
  otp: z.string().trim().regex(/^\d{6}$/, 'Enter the 6-digit customer OTP.').optional(),
  proof_note: optionalText(1000),
}).refine((value) => value.method !== 'otp' || Boolean(value.otp), {
  message: 'Enter the customer OTP.', path: ['otp'],
});

export const riderAssignmentSchema = z.object({
  rider_user_id: z.string().trim().min(1),
});

// Spec 16/17 v2 — a provider can lengthen OR trim today's shift by minutes, so
// `minutes` is signed: +30 extends the closing time, -30 pulls it earlier. A
// trim that removes more than is left ends the shift by writing the closing
// time as "now". Zero is rejected so an unspoken tap does nothing.
export const availabilityAdjustSchema = z.object({
  minutes: z.number().int().min(-24 * 60).max(24 * 60).refine((value) => value !== 0, {
    message: 'Minutes cannot be zero.',
  }),
});

export const deliveryOtpSchema = z.object({
  expires_in_minutes: z.number().int().min(5).max(24 * 60).optional().default(30),
});

// ─────────────────────────────────────────────────────────────
// Wallet: funding (virtual account / card) and payout
// ─────────────────────────────────────────────────────────────

const positiveKobo = (label) =>
  moneySchema(label).refine((kobo) => kobo > 0, `${label} must be greater than zero.`);

const accountNumberSchema = z
  .string({ required_error: 'Account number is required.' })
  .trim()
  .regex(/^\d{10}$/, 'Account number must be 10 digits.');

export const bankResolveSchema = z.object({
  bank_code: z.string({ required_error: 'Choose a bank.' }).trim().min(1, 'Choose a bank.'),
  account_number: accountNumberSchema,
});

export const walletFundSchema = z.object({
  amount_kobo: positiveKobo('Amount'),
  channel: z.enum(['virtual_account', 'card'], {
    required_error: 'Choose how the money arrives.',
  }),
  // Only read by the simulated card channel; a real gateway would tokenise the
  // card client-side and send a token instead of the number.
  card_number: z.string().trim().optional(),
  narration: optionalText(140),
});

export const walletPayoutSchema = z.object({
  amount_kobo: positiveKobo('Amount'),
  bank_code: z.string({ required_error: 'Choose a bank.' }).trim().min(1, 'Choose a bank.'),
  account_number: accountNumberSchema,
  account_name: z
    .string({ required_error: 'Account name is required.' })
    .trim()
    .min(2, 'Account name is required.')
    .max(120, 'Account name is too long.'),
  narration: optionalText(140),
});

export const walletPayoutConfirmSchema = z.object({
  otp: z.string().trim().regex(/^\d{6}$/, 'Enter the 6-digit code.'),
});

// ─────────────────────────────────────────────────────────────
// Staff accounts (docs/staff-accounts.md)
// ─────────────────────────────────────────────────────────────

const staffCodeField = z
  .string({ required_error: 'Enter your staff code.' })
  .trim()
  .min(4, 'Enter your staff code.')
  .max(16, 'That is not a valid staff code.')
  .transform((value) => value.toUpperCase())
  .refine((value) => STAFF_CODE_PATTERN.test(value), 'Enter a valid staff code.');

// The owner adds a staff by name; the server issues the code. Nothing else about
// the staff (password, code) is ever supplied by the owner.
export const staffCreateSchema = z.object({
  full_name: z
    .string({ required_error: 'Staff name is required.' })
    .trim()
    .min(2, 'Staff name is required.')
    .max(120, 'Staff name is too long.'),
  phone: phoneSchema.optional().nullable(),
});

export const staffUpdateSchema = z
  .object({
    full_name: z.string().trim().min(2, 'Staff name is required.').max(120).optional(),
    phone: phoneSchema.optional().nullable(),
    status: z.enum(['active', 'disabled']).optional(),
  })
  .refine((value) => Object.keys(value).length > 0, {
    message: 'Send at least one field to update.',
  });

// Step 1 of activation: prove the code exists and is unclaimed.
export const staffClaimSchema = z.object({ staff_code: staffCodeField });

// Step 2 of activation: set the name and password. The code is re-sent (it is
// carried in client state, not re-typed) and re-checked here, so an activate
// call can never touch a code the claimant did not actually hold.
export const staffActivateSchema = z.object({
  staff_code: staffCodeField,
  full_name: z.string().trim().min(2, 'Enter your name.').max(120).optional(),
  password: passwordSchema,
});

export { nonNegativeKobo, moneySchema };
